import Combine
import Foundation

// MARK: - Antigravity Provider
// Zero-config state tracking: reads the agent's own transcript.jsonl directly.
// No SQLite, no protobuf heuristics, no binary parsing. Just clean JSON.
final class AntigravityProvider: LLMProviderProtocol, ObservableObject, @unchecked Sendable {

    let id = "antigravity"
    let name = "Antigravity (AGY)"

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isInstalledLocally: Bool = false

    // Transcript-derived state — read by the UI
    @Published private(set) var currentTool: String? = nil  // e.g. "grep_search", "replace_file_content"
    @Published private(set) var stepCount: Int = 0  // total steps seen in current conversation

    // Quota-derived state (Stamina)
    @Published private(set) var currentStamina: Double? = nil  // 0.0 to 1.0
    @Published private(set) var dailyStamina: Double? = nil
    @Published private(set) var weeklyStamina: Double? = nil
    @Published private(set) var activeModelName: String? = nil
    @Published private(set) var staminaLastUpdated: Date? = nil

    private let subject = PassthroughSubject<AgentEvent, Never>()
    var eventPublisher: AnyPublisher<AgentEvent, Never> { subject.eraseToAnyPublisher() }

    private var directoryPollingTimer: Timer?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var currentFileOffset: UInt64 = 0
    private var idleTimeoutWorkItem: DispatchWorkItem?

    // Transcript tracking
    private var lastActiveTranscriptPath: String = ""
    private var lastSeenStepIndex: Int = -1
    private var lastKnownPhase: TranscriptPhase = .idle
    private var lastParsedPhase: TranscriptPhase = .idle

    // Queue for replaying intermediate steps
    private var pendingPhaseQueue:
        [(phase: TranscriptPhase, tool: String?, stepIndex: Int, stepType: String)] = []
    private var drainTimer: Timer?

    // Fast-poll timer active only while waiting for user input
    private var waitingPollTimer: Timer?

    // CSV status-duration logging
    private var currentStatusStartTime: Date = Date()
    private var currentStatusPhase: TranscriptPhase = .idle
    private var currentStatusTool: String? = nil

    // MARK: - Phase Model
    enum TranscriptPhase: Equatable {
        case reading
        case thinking
        case writing
        case executing
        case searching
        case planning
        case building
        case running
        case generic  // unrecognized tool — falls back to focused busy
        case waitingForUser  // ask_question / ask_permission
        case completed
        case error
        case idle
    }

    // MARK: Init
    init() {
        checkLocalInstallation()
    }

    private func checkLocalInstallation() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        let pathsToCheck = [
            "/Applications/Antigravity IDE.app",
            "/Applications/Antigravity.app",
            "\(homeDir)/.gemini/antigravity-ide",
            "\(homeDir)/.gemini/antigravity",
            "\(homeDir)/.gemini/config",
        ]
        isInstalledLocally = pathsToCheck.contains { fileManager.fileExists(atPath: $0) }
    }

    // MARK: Connect / Disconnect
    func connect(config: ProviderConfig) async throws {
        isConnected = true
        await MainActor.run {
            startPolling()
            Task { await self.fetchStamina() }
        }
    }

    func disconnect() {
        directoryPollingTimer?.invalidate()
        directoryPollingTimer = nil
        drainTimer?.invalidate()
        drainTimer = nil
        cancelWaitingPollTimer()
        cancelFileWatcher()
        cancelIdleTimeout()
        isConnected = false
        subject.send(.disconnected)
    }

    // MARK: - Polling Loop
    @MainActor
    private func startPolling() {
        directoryPollingTimer?.invalidate()
        directoryPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.pollDirectory()
                if self.staminaLastUpdated == nil {
                    await self.fetchStamina()
                }
            }
        }
        pollDirectory()
    }

    @MainActor
    private func pollDirectory() {
        guard let transcriptPath = findActiveTranscript() else { return }

        if transcriptPath != lastActiveTranscriptPath {
            if lastActiveTranscriptPath != "" {
                handleConversationSwitch()
            }
            lastActiveTranscriptPath = transcriptPath
            setupFileWatcher(for: transcriptPath)
        }
    }

    private func setupFileWatcher(for path: String) {
        cancelFileWatcher()

        let fd = open(path, O_EVTONLY)
        guard fd != -1 else {
            print("Failed to open transcript for watching: \(path)")
            return
        }
        self.fileDescriptor = fd

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attrs[.size] as? UInt64
        {
            // Initial read of last 8KB to quickly get current state
            let readOffset = size > 8192 ? size - 8192 : 0
            currentFileOffset = readOffset

            Task { @MainActor in
                self.handleFileWrite(fromInitialAttach: true)
            }
        }

        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main)

        fileWatcher?.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleFileWrite(fromInitialAttach: false)
            }
        }

        fileWatcher?.setCancelHandler {
            close(fd)
        }

        fileWatcher?.resume()
    }

    private func cancelFileWatcher() {
        if let watcher = fileWatcher {
            watcher.cancel()
            fileWatcher = nil
        } else if fileDescriptor != -1 {
            close(fileDescriptor)
        }
        fileDescriptor = -1
    }

    @MainActor
    private func handleFileWrite(fromInitialAttach: Bool) {
        let newSteps = collectNewStepsFromOffset(path: lastActiveTranscriptPath)

        if let maxStep = newSteps.map({ $0.stepIndex }).max() {
            if maxStep + 1 != stepCount {
                stepCount = maxStep + 1
            }
        }

        if !newSteps.isEmpty {
            if fromInitialAttach {
                if let lastStep = newSteps.last {
                    lastSeenStepIndex = lastStep.stepIndex
                    applyPhase(
                        phase: lastStep.phase,
                        tool: lastStep.tool,
                        stepIndex: lastStep.stepIndex,
                        lastStepType: lastStep.stepType,
                        reason: "initial_attach"
                    )
                }
            } else {
                pendingPhaseQueue.append(contentsOf: newSteps)
                ensureDrainTimerRunning()
            }
            scheduleIdleTimeout()
        }
    }

    private func scheduleIdleTimeout() {
        cancelIdleTimeout()

        // waitingForUser is a persistent state — the agent is blocked waiting
        // for the user to respond. We must NOT auto-transition to idle; the
        // next USER_INPUT step will move us out of waiting on its own.
        guard lastKnownPhase != .waitingForUser else { return }

        let isIdleState = (lastKnownPhase == .completed || lastKnownPhase == .idle)
        let timeoutSeconds = isIdleState ? 1.5 : 60.0

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                // Re-check at fire time: the phase may have transitioned to
                // .waitingForUser between scheduling and firing (e.g. a busy
                // timeout was scheduled, then the agent asked a question).
                guard self.lastKnownPhase != .idle,
                    self.lastKnownPhase != .waitingForUser,
                    self.pendingPhaseQueue.isEmpty
                else { return }
                self.transitionToIdle(reason: "idle_timeout")
            }
        }

        idleTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: workItem)
    }

    private func cancelIdleTimeout() {
        idleTimeoutWorkItem?.cancel()
        idleTimeoutWorkItem = nil
    }

    @MainActor
    private func ensureDrainTimerRunning() {
        guard drainTimer == nil else { return }

        drainTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.drainNextPhase() }
        }
        // Fire immediately for the first one
        drainNextPhase()
    }

    @MainActor
    private func drainNextPhase() {
        guard !pendingPhaseQueue.isEmpty else {
            drainTimer?.invalidate()
            drainTimer = nil
            return
        }

        let next = pendingPhaseQueue.removeFirst()
        // applyPhase handles logging and publishing
        applyPhase(
            phase: next.phase, tool: next.tool, stepIndex: next.stepIndex,
            lastStepType: next.stepType, reason: "queue_drained")
    }

    // MARK: - Conversation Switch
    private func handleConversationSwitch() {
        // Log the outgoing status before resetting
        let convId = conversationId(from: lastActiveTranscriptPath)
        logStatusTransition(
            eventType: "END",
            phase: currentStatusPhase,
            tool: currentStatusTool,
            stepIndex: lastSeenStepIndex,
            conversationId: convId,
            startTime: currentStatusStartTime,
            endTime: Date(),
            reason: "conversation_switched",
            lastStepType: ""
        )
        if lastKnownPhase != .idle {
            subject.send(.completed(taskId: UUID().uuidString, totalTokens: 0))
            subject.send(.idle)
        }
        lastSeenStepIndex = -1
        cancelFileWatcher()
        cancelIdleTimeout()
        cancelWaitingPollTimer()
        lastKnownPhase = .idle
        lastParsedPhase = .idle
        pendingPhaseQueue.removeAll()
        drainTimer?.invalidate()
        drainTimer = nil
        currentTool = nil
        stepCount = 0
        // Reset status tracking for new conversation
        currentStatusStartTime = Date()
        currentStatusPhase = .idle
        currentStatusTool = nil
    }

    // MARK: - Apply Phase → Emit Events
    private func applyPhase(
        phase: TranscriptPhase, tool: String?, stepIndex: Int, lastStepType: String, reason: String
    ) {
        currentTool = tool

        guard phase != lastKnownPhase else { return }

        // ── Log the OUTGOING status row before transitioning ─────────────
        let now = Date()
        let convId = conversationId(from: lastActiveTranscriptPath)
        logStatusTransition(
            eventType: "END",
            phase: currentStatusPhase,
            tool: currentStatusTool,
            stepIndex: lastSeenStepIndex,  // use the last recorded step index
            conversationId: convId,
            startTime: currentStatusStartTime,
            endTime: now,
            reason: reason,
            lastStepType: lastStepType
        )
        // Reset tracking for the INCOMING status
        currentStatusStartTime = now
        currentStatusPhase = phase
        currentStatusTool = tool
        lastSeenStepIndex = stepIndex

        // Log the INCOMING status row
        logStatusTransition(
            eventType: "START",
            phase: phase,
            tool: tool,
            stepIndex: stepIndex,
            conversationId: convId,
            startTime: now,
            endTime: now,
            reason: reason,
            lastStepType: lastStepType
        )
        // ─────────────────────────────────────────────────────────────────

        let previousPhase = lastKnownPhase
        lastKnownPhase = phase

        // Manage the fast-poll timer: only active while waiting for user
        if phase == .waitingForUser {
            startWaitingPollTimer()
        } else {
            cancelWaitingPollTimer()
        }

        switch phase {
        case .reading:
            if previousPhase == .idle || previousPhase == .completed {
                subject.send(.started(taskId: UUID().uuidString))
            }
            subject.send(.busy(subMode: .reading))
        case .thinking:
            if previousPhase == .idle || previousPhase == .completed {
                subject.send(.started(taskId: UUID().uuidString))
            }
            subject.send(.busy(subMode: .thinking))
        case .writing, .executing:
            subject.send(.busy(subMode: .writing))
        case .searching:
            subject.send(.busy(subMode: .searching))
        case .planning:
            subject.send(.busy(subMode: .planning))
        case .building:
            subject.send(.busy(subMode: .building))
        case .running:
            subject.send(.busy(subMode: .running))
        case .generic:
            if previousPhase == .idle || previousPhase == .completed {
                subject.send(.started(taskId: UUID().uuidString))
            }
            subject.send(.busy(subMode: nil))
        case .waitingForUser:
            subject.send(.waiting)
        case .completed:
            subject.send(.completed(taskId: UUID().uuidString, totalTokens: 0))
        case .error:
            subject.send(
                .failed(taskId: UUID().uuidString, error: AGYError.agentFailed("Transcript error")))
        case .idle:
            break
        }
    }

    private func transitionToIdle(reason: String) {
        // Log the outgoing status before going idle
        let now = Date()
        let convId = conversationId(from: lastActiveTranscriptPath)
        logStatusTransition(
            eventType: "END",
            phase: currentStatusPhase,
            tool: currentStatusTool,
            stepIndex: lastSeenStepIndex,
            conversationId: convId,
            startTime: currentStatusStartTime,
            endTime: now,
            reason: reason,
            lastStepType: ""
        )
        // Reset tracking to idle
        currentStatusStartTime = now
        currentStatusPhase = .idle
        currentStatusTool = nil
        pendingPhaseQueue.removeAll()
        drainTimer?.invalidate()
        drainTimer = nil

        cancelIdleTimeout()
        cancelWaitingPollTimer()
        lastKnownPhase = .idle
        currentTool = nil
        subject.send(.completed(taskId: UUID().uuidString, totalTokens: 0))
        subject.send(.idle)

        // Fetch quota/stamina on transition to idle
        Task { @MainActor in
            await fetchStamina()
        }
    }

    // MARK: - Waiting Poll Timer
    /// Starts a 0.5-second repeating timer that re-reads the transcript while the
    /// agent is blocked waiting for user input. This ensures the pet exits the
    /// waiting state promptly (within ~0.5 s) after the user answers, rather than
    /// relying solely on the OS file-write event from the DispatchSource watcher.
    private func startWaitingPollTimer() {
        cancelWaitingPollTimer()
        waitingPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.lastKnownPhase == .waitingForUser else {
                    self.cancelWaitingPollTimer()
                    return
                }
                self.handleFileWrite(fromInitialAttach: false)
            }
        }
    }

    private func cancelWaitingPollTimer() {
        waitingPollTimer?.invalidate()
        waitingPollTimer = nil
    }

    // MARK: - Find Active Transcript
    /// Scans ~/.gemini/antigravity-ide/brain/*/system_generated/logs/transcript.jsonl
    /// and returns the path of the most recently modified one.
    private func findActiveTranscript() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let brainDir = "\(homeDir)/.gemini/antigravity-ide/brain"

        guard let conversationIds = try? FileManager.default.contentsOfDirectory(atPath: brainDir)
        else {
            return nil
        }

        let candidatePaths = conversationIds.map { id in
            "\(brainDir)/\(id)/.system_generated/logs/transcript.jsonl"
        }.filter { FileManager.default.fileExists(atPath: $0) }

        // Return most recently modified transcript
        return candidatePaths.max { a, b in
            let dateA =
                (try? FileManager.default.attributesOfItem(atPath: a))?[.modificationDate] as? Date
                ?? .distantPast
            let dateB =
                (try? FileManager.default.attributesOfItem(atPath: b))?[.modificationDate] as? Date
                ?? .distantPast
            return dateA < dateB
        }
    }

    // MARK: - Collect New Steps
    private func collectNewStepsFromOffset(path: String) -> [(
        phase: TranscriptPhase, tool: String?, stepIndex: Int, stepType: String
    )] {
        guard let fileHandle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return []
        }
        defer { try? fileHandle.close() }

        let fileSize = (try? fileHandle.seekToEnd()) ?? 0
        guard fileSize >= currentFileOffset else { return [] }  // File might have been truncated

        try? fileHandle.seek(toOffset: currentFileOffset)
        currentFileOffset = UInt64(fileSize)

        guard let data = try? fileHandle.readToEnd(),
            let rawString = String(data: data, encoding: .utf8)
        else { return [] }

        let lines = rawString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var results: [(phase: TranscriptPhase, tool: String?, stepIndex: Int, stepType: String)] =
            []

        for line in lines {
            guard let jsonData = line.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                let stepIndex = obj["step_index"] as? Int
            else { continue }

            // Only process steps we haven't seen in the queue
            // We use the highest stepIndex collected so far or lastSeenStepIndex
            let highestSeen = max(lastSeenStepIndex, results.last?.stepIndex ?? -1)
            guard stepIndex > highestSeen else { continue }

            let source = obj["source"] as? String ?? ""
            let type_ = obj["type"] as? String ?? ""
            let status = obj["status"] as? String ?? ""

            guard status == "DONE" || status == "RUNNING" || status == "ERROR" else { continue }

            if status == "ERROR" {
                results.append((.error, nil, stepIndex, type_))
            } else if source == "USER_EXPLICIT" || source == "SYSTEM" {
                if type_ == "USER_INPUT" {
                    results.append((.thinking, nil, stepIndex, type_))
                }
            } else if source == "MODEL" {
                switch type_ {
                case "PLANNER_RESPONSE":
                    if let toolCalls = obj["tool_calls"] as? [[String: Any]],
                        let firstCall = toolCalls.first,
                        let toolName = firstCall["name"] as? String
                    {
                        // Insert a brief planning phase before the actual tool action
                        results.append((.planning, nil, stepIndex, type_))
                        results.append((phase(for: toolName), toolName, stepIndex, type_))
                    } else {
                        results.append((.completed, nil, stepIndex, type_))
                    }
                case "ASK_QUESTION", "ASK_PERMISSION":
                    results.append((.waitingForUser, nil, stepIndex, type_))
                case "GENERIC":
                    results.append((.thinking, nil, stepIndex, type_))
                default:
                    break
                }
            }
        }
        return results
    }

    // MARK: - Tool → Phase Mapping
    private func phase(for toolName: String) -> TranscriptPhase {
        switch toolName {
        case "view_file", "read_file":
            return .reading

        case "write_to_file", "replace_file_content", "multi_replace_file_content":
            return .writing

        case "grep_search", "list_dir",
            "read_url_content", "list_permissions",
            "search_web":
            return .searching

        case "run_command", "manage_task", "schedule",
            "execute_url":
            return .running

        case "ask_question", "ask_permission":
            return .waitingForUser

        case "generate_image":
            return .building

        default:
            return .generic
        }
    }

    // MARK: - CSV Status Transition Logging

    /// Extracts the conversation UUID from a transcript path.
    private func conversationId(from transcriptPath: String) -> String {
        // Path pattern: .../brain/{uuid}/.system_generated/logs/transcript.jsonl
        let components = transcriptPath.components(separatedBy: "/")
        if let brainIdx = components.firstIndex(of: "brain"), brainIdx + 1 < components.count {
            return components[brainIdx + 1]
        }
        return "unknown"
    }

    /// Human-readable label for a TranscriptPhase.
    private func phaseLabel(_ phase: TranscriptPhase) -> String {
        switch phase {
        case .reading: return "reading"
        case .thinking: return "thinking"
        case .writing: return "writing"
        case .executing: return "executing"
        case .searching: return "searching"
        case .planning: return "planning"
        case .building: return "building"
        case .running: return "running"
        case .generic: return "generic"
        case .waitingForUser: return "waiting_for_user"
        case .completed: return "completed"
        case .error: return "error"
        case .idle: return "idle"
        }
    }

    /// Appends one CSV row to token_log.csv when a status period ends.
    /// Automatically trims the file to the most recent 1000 data rows.
    private var logWriteCount: Int = 0
    private func logStatusTransition(
        eventType: String,
        phase: TranscriptPhase,
        tool: String?,
        stepIndex: Int,
        conversationId: String,
        startTime: Date,
        endTime: Date,
        reason: String,
        lastStepType: String
    ) {
        let logURL = URL(fileURLWithPath: "/Users/fong/Documents/FHY/tokengotchi/token_log.csv")
        let iso = ISO8601DateFormatter()
        let start = iso.string(from: startTime)
        let end = iso.string(from: endTime)
        let duration = String(format: "%.2f", endTime.timeIntervalSince(startTime))
        let toolStr = tool ?? ""
        let stepStr = stepIndex >= 0 ? "\(stepIndex)" : ""

        let header =
            "timestamp_start,timestamp_end,duration_seconds,pet_status,transcript_phase,current_tool,step_index_at_transition,conversation_id,transition_reason,last_step_type,event_type\n"
        let row =
            "\(start),\(end),\(duration),\(phaseLabel(phase)),\(phaseLabel(phase)),\(toolStr),\(stepStr),\(conversationId),\(reason),\(lastStepType),\(eventType)\n"

        let fm = FileManager.default
        if !fm.fileExists(atPath: logURL.path) {
            try? header.write(to: logURL, atomically: true, encoding: .utf8)
        }
        if let fileHandle = try? FileHandle(forWritingTo: logURL) {
            fileHandle.seekToEndOfFile()
            if let data = row.data(using: .utf8) {
                fileHandle.write(data)
            }
            try? fileHandle.close()
        }

        // Trim to 1000 data rows every 50 writes
        logWriteCount += 1
        if logWriteCount % 50 == 0 {
            trimLogIfNeeded(logURL: logURL, header: header, maxRows: 1000)
        }
    }

    /// Keeps only the most recent `maxRows` data rows in the CSV, preserving the header.
    private func trimLogIfNeeded(logURL: URL, header: String, maxRows: Int) {
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        var lines = content.components(separatedBy: "\n")
        // Remove trailing empty line(s)
        while lines.last?.isEmpty == true { lines.removeLast() }
        // lines[0] is the header, lines[1...] are data rows
        guard lines.count > maxRows + 1 else { return }
        let trimmed = [lines[0]] + lines.suffix(maxRows)
        let newContent = trimmed.joined(separator: "\n") + "\n"
        try? newContent.write(to: logURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Errors
    enum AGYError: LocalizedError {
        case agentFailed(String)
        var errorDescription: String? {
            switch self {
            case .agentFailed(let msg): return msg
            }
        }
    }

    // MARK: - Quota Fetching (Stamina)
    @MainActor
    private func fetchStamina() async {
        do {
            var targetWorkspace: String? = nil
            if !lastActiveTranscriptPath.isEmpty {
                if let path = extractWorkspacePath(from: lastActiveTranscriptPath) {
                    targetWorkspace = "file" + path.replacingOccurrences(of: "/", with: "_")
                }
            }

            let snapshot = try await AntigravityUsageProbe.shared.probe(
                workspaceId: targetWorkspace)

            var activeModel = snapshot.activeModelName

            // Fallback: check transcript for user settings override
            var debugInfo = "Debug Info:\n"
            debugInfo += "Transcript Path: \(lastActiveTranscriptPath)\n"

            if !lastActiveTranscriptPath.isEmpty {
                if let transcriptOverride = extractActiveModelName(from: lastActiveTranscriptPath) {
                    activeModel = transcriptOverride
                    debugInfo += "Extracted Model: \(transcriptOverride)\n"
                } else {
                    debugInfo += "Extracted Model: nil\n"
                }
            }

            try? debugInfo.write(
                toFile:
                    "/Users/fong/.gemini/antigravity-ide/brain/c1bb66e9-f31d-4e79-835a-2fb527883b7a/scratch/troubleshoot.md",
                atomically: true, encoding: .utf8)

            guard let finalModel = activeModel else {
                print("[\(self.name)] No active model found in probe")
                return
            }

            self.activeModelName = finalModel

            // Find the quota matching the active model
            let modelQuotas = snapshot.quotas.filter { $0.label == finalModel }
            guard !modelQuotas.isEmpty else {
                // If the model is Mystery Model, we might not have a quota.
                self.currentStamina = 1.0
                self.staminaLastUpdated = Date()
                return
            }

            var daily: Double? = nil
            var weekly: Double? = nil

            if modelQuotas.count >= 2 {
                // Heuristic: If we have multiple quotas, the weekly one usually resets later, but we can just use the values
                // Based on user prompt: daily is 87%, weekly is 5%. Usually weekly limit percent is lower or drops faster.
                // We will just assume the smaller one is weekly for safety, or just apply the logic to both.
                // Actually, if we just scale the smallest one, we don't need to strictly differentiate.
                let sorted = modelQuotas.map { $0.percentRemaining / 100.0 }.sorted()
                weekly = sorted.first
                daily = sorted.last
            } else if let only = modelQuotas.first {
                daily = only.percentRemaining / 100.0
                weekly = daily
            }

            self.dailyStamina = daily
            self.weeklyStamina = weekly

            let d = daily ?? 1.0
            let w = weekly ?? 1.0

            // 20% threshold scaling for weekly
            // effective_weekly = min(1.0, w / 0.2)
            let effectiveWeekly = min(1.0, w / 0.20)

            self.currentStamina = min(d, effectiveWeekly)
            self.staminaLastUpdated = Date()

            print(
                "[\(self.name)] Fetched quota: daily \(Int(d * 100))%, weekly \(Int(w * 100))% -> effective stamina: \(Int((self.currentStamina ?? 0) * 100))% for \(self.activeModelName ?? "")"
            )
        } catch {
            print("[\(self.name)] Failed to fetch stamina: \(error)")
        }
    }

    private func extractWorkspacePath(from transcriptPath: String) -> String? {
        guard let data = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else {
            return nil
        }

        let regex = try? NSRegularExpression(pattern: "\"Cwd\"\\s*:\\s*\"(?:\\\\\")?(/[^\\\\\"]+)")
        let range = NSRange(data.startIndex..<data.endIndex, in: data)
        if let match = regex?.firstMatch(in: data, options: [], range: range) {
            if let r = Range(match.range(at: 1), in: data) {
                return String(data[r])
            }
        }

        let regex2 = try? NSRegularExpression(
            pattern: "\"SearchPath\"\\s*:\\s*\"(?:\\\\\")?(/[^\\\\\"]+)")
        if let match2 = regex2?.firstMatch(in: data, options: [], range: range) {
            if let r = Range(match2.range(at: 1), in: data) {
                return String(data[r])
            }
        }

        return nil
    }

    private func extractActiveModelName(from transcriptPath: String) -> String? {
        guard let data = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else {
            return nil
        }

        // Parse JSON strings: the regex can safely use .dotMatchesLineSeparators on the unescaped content
        let regex = try? NSRegularExpression(
            pattern:
                "<USER_SETTINGS_CHANGE>.*?setting `Model Selection` from .*? to (.*?)\\. No need",
            options: [.dotMatchesLineSeparators])

        var lastModel: String? = nil
        let lines = data.split(whereSeparator: \.isNewline)
        for line in lines {
            guard let jsonData = String(line).data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                let type = json["type"] as? String,
                type == "USER_INPUT" || type == "SYSTEM_MESSAGE",
                let content = json["content"] as? String
            else {
                continue
            }

            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            if let match = regex?.firstMatch(in: content, options: [], range: range) {
                if let r = Range(match.range(at: 1), in: content) {
                    lastModel = String(content[r])
                }
            }
        }
        return lastModel
    }
}
