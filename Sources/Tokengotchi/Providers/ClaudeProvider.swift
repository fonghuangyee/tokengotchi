import Combine
import Foundation

// MARK: - Claude Code Provider
// Zero-config state tracking: reads Claude Code's own session JSONL directly.
// No API key, no hooks, no settings changes. Just tail ~/.claude/projects/*.jsonl.
final class ClaudeProvider: LLMProviderProtocol, ObservableObject, @unchecked Sendable {

    let id = "claude"
    let name = "Claude Code"

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isInstalledLocally: Bool = false

    // Transcript-derived state — read by the UI
    @Published private(set) var currentTool: String? = nil  // e.g. "Read", "Bash", "Edit"
    @Published private(set) var stepCount: Int = 0  // assistant events seen in current session

    // Claude has no local quota probe — stamina stays nil (UI treats as optional)
    @Published private(set) var currentStamina: Double? = nil
    @Published private(set) var activeModelName: String? = nil

    private let subject = PassthroughSubject<AgentEvent, Never>()
    var eventPublisher: AnyPublisher<AgentEvent, Never> { subject.eraseToAnyPublisher() }

    private var directoryPollingTimer: Timer?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var currentFileOffset: UInt64 = 0
    private var idleTimeoutWorkItem: DispatchWorkItem?

    // Session tracking
    private var lastActiveTranscriptPath: String = ""
    private var lastSeenStepIndex: Int = -1
    private var lastKnownPhase: TranscriptPhase = .idle

    // Queue for replaying intermediate phases (smooth animation pacing)
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
        case generic
        case waitingForUser  // AskUserQuestion / ExitPlanMode pending
        case completed
        case error
        case idle
    }

    // MARK: Init
    init() {
        checkLocalInstallation()
    }

    private func checkLocalInstallation() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let pathsToCheck = [
            "\(home)/.claude/projects",
            "\(home)/.claude/settings.json",
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        isInstalledLocally = pathsToCheck.contains { fm.fileExists(atPath: $0) }
    }

    // MARK: Connect / Disconnect
    func connect(config: ProviderConfig) async throws {
        isConnected = true
        await MainActor.run { startPolling() }
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
            Task { @MainActor in self.pollDirectory() }
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
            print("[\(name)] Failed to open transcript for watching: \(path)")
            return
        }
        self.fileDescriptor = fd

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attrs[.size] as? UInt64
        {
            // Initial read of last 16KB to quickly get current state
            let readOffset = size > 16384 ? size - 16384 : 0
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

        // waitingForUser is persistent — the agent is blocked on the user.
        // Do NOT auto-transition to idle; the next user reply moves us out.
        guard lastKnownPhase != .waitingForUser else { return }

        let isIdleState = (lastKnownPhase == .completed || lastKnownPhase == .idle)
        let timeoutSeconds = isIdleState ? 1.5 : 60.0

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
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
        applyPhase(
            phase: next.phase, tool: next.tool, stepIndex: next.stepIndex,
            lastStepType: next.stepType, reason: "queue_drained")
    }

    // MARK: - Conversation Switch
    private func handleConversationSwitch() {
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
        pendingPhaseQueue.removeAll()
        drainTimer?.invalidate()
        drainTimer = nil
        currentTool = nil
        stepCount = 0
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
            stepIndex: lastSeenStepIndex,
            conversationId: convId,
            startTime: currentStatusStartTime,
            endTime: now,
            reason: reason,
            lastStepType: lastStepType
        )
        currentStatusStartTime = now
        currentStatusPhase = phase
        currentStatusTool = tool
        lastSeenStepIndex = stepIndex

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
                .failed(taskId: UUID().uuidString, error: ClaudeError.agentFailed("Transcript error")))
        case .idle:
            break
        }
    }

    private func transitionToIdle(reason: String) {
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
    }

    // MARK: - Waiting Poll Timer
    /// While the agent is blocked waiting for user input, re-read the transcript
    /// every 0.5 s so the pet exits waiting promptly after the user answers.
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
    /// Scans ~/.claude/projects/<cwd-slug>/<session-uuid>.jsonl and returns
    /// the path of the most recently modified one (the live session).
    private func findActiveTranscript() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let projectsDir = "\(homeDir)/.claude/projects"

        guard let projectSlugs = try? FileManager.default.contentsOfDirectory(atPath: projectsDir)
        else {
            return nil
        }

        var candidatePaths: [String] = []
        for slug in projectSlugs {
            let slugPath = "\(projectsDir)/\(slug)"
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: slugPath)
            else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                candidatePaths.append("\(slugPath)/\(file)")
            }
        }

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
    /// Parses Claude Code JSONL incrementally from the last-read offset.
    ///
    /// Event model (verified against live transcripts):
    ///   - type == "user" with string/text content  → user prompt → thinking
    ///   - type == "user" with tool_result content  → tool finished; skip (next assistant drives state)
    ///   - type == "assistant" content[].type == "thinking" → thinking
    ///   - type == "assistant" content[].type == "tool_use" (has .name) → tool phase
    ///   - type == "assistant" content[].type == "text" only → final answer → completed
    private func collectNewStepsFromOffset(path: String) -> [(
        phase: TranscriptPhase, tool: String?, stepIndex: Int, stepType: String
    )] {
        guard let fileHandle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return []
        }
        defer { try? fileHandle.close() }

        let fileSize = (try? fileHandle.seekToEnd()) ?? 0
        guard fileSize >= currentFileOffset else { return [] }  // truncated

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
                let type = obj["type"] as? String
            else { continue }

            let stepIndex = (results.last?.stepIndex ?? lastSeenStepIndex) + 1

            switch type {
            case "user":
                // Real user prompt (not a tool_result) → agent starts thinking
                if let message = obj["message"] as? [String: Any],
                    let content = message["content"]
                {
                    var isToolResult = false
                    if let arr = content as? [[String: Any]], let first = arr.first {
                        isToolResult = (first["type"] as? String) == "tool_result"
                    }
                    if !isToolResult {
                        results.append((.thinking, nil, stepIndex, "user_prompt"))
                    }
                }

            case "assistant":
                guard let message = obj["message"] as? [String: Any],
                    let content = message["content"] as? [[String: Any]]
                else { continue }

                var sawThinking = false
                var sawTool = false
                var sawText = false
                var toolName: String? = nil

                for block in content {
                    switch block["type"] as? String {
                    case "thinking":
                        sawThinking = true
                    case "tool_use":
                        sawTool = true
                        if toolName == nil { toolName = block["name"] as? String }
                    case "text":
                        sawText = true
                    default:
                        break
                    }
                }

                if sawTool {
                    // Insert a brief thinking beat before the tool action for pacing
                    results.append((.thinking, nil, stepIndex, "assistant_pre_tool"))
                    let name = toolName ?? ""
                    results.append((phase(for: name), name, stepIndex + 1, "tool_use"))
                } else if sawThinking {
                    results.append((.thinking, nil, stepIndex, "assistant_thinking"))
                } else if sawText {
                    // Pure text reply with no tool → turn complete
                    results.append((.completed, nil, stepIndex, "assistant_text"))
                }

            default:
                // system / attachment / queue-operation / last-prompt / file-history-* → ignore
                break
            }
        }
        return results
    }

    // MARK: - Tool → Phase Mapping
    private func phase(for toolName: String) -> TranscriptPhase {
        switch toolName {
        case "Read", "View":
            return .reading

        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            return .writing

        case "Grep", "Glob", "WebSearch", "WebFetch", "ToolSearch":
            return .searching

        case "Bash", "BashOutput", "KillBash":
            return .running

        case "TodoWrite", "ExitPlanMode":
            return .planning

        case "AskUserQuestion":
            return .waitingForUser

        default:
            // MCP tools (mcp__*__*) and anything unrecognized
            return .generic
        }
    }

    // MARK: - CSV Status Transition Logging

    /// Session UUID from a transcript path: .../projects/{slug}/{uuid}.jsonl
    private func conversationId(from transcriptPath: String) -> String {
        let last = transcriptPath.components(separatedBy: "/").last ?? "unknown"
        return last.replacingOccurrences(of: ".jsonl", with: "")
    }

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

        logWriteCount += 1
        if logWriteCount % 50 == 0 {
            trimLogIfNeeded(logURL: logURL, header: header, maxRows: 1000)
        }
    }

    private func trimLogIfNeeded(logURL: URL, header: String, maxRows: Int) {
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        var lines = content.components(separatedBy: "\n")
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard lines.count > maxRows + 1 else { return }
        let trimmed = [lines[0]] + lines.suffix(maxRows)
        let newContent = trimmed.joined(separator: "\n") + "\n"
        try? newContent.write(to: logURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Errors
    enum ClaudeError: LocalizedError {
        case agentFailed(String)
        var errorDescription: String? {
            switch self {
            case .agentFailed(let msg): return msg
            }
        }
    }
}
