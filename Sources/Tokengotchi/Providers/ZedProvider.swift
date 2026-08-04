import Combine
import Foundation

// MARK: - Zed Agent Provider
// Zero-config state tracking: reads Zed's own agent-thread database directly.
// No API key, no plugins, no settings changes. Polls
//   ~/Library/Application Support/<Channel>/threads/threads.db
// (channel = "Zed" / "Zed Preview" / "Zed Dev"), snapshots it to a temp copy,
// and diffs the newest thread's message list to derive the pet's state.
//
// Zed writes whole-thread snapshots at message/tool-call boundaries (never
// per-token), so a cheap metadata poll detects activity and we only
// zstd-decompress the payload when `updated_at` advances. See
// https://github.com/zed-industries/zed `crates/agent/src/db.rs`.
final class ZedProvider: LLMProviderProtocol, ObservableObject, @unchecked Sendable {

    let id = "zed"
    let name = "Zed Agent"

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isInstalledLocally: Bool = false

    // Transcript-derived state — read by the UI
    @Published private(set) var currentTool: String? = nil  // e.g. "read_file", "terminal"
    @Published private(set) var stepCount: Int = 0          // events seen in current thread

    // Zed has no local quota probe — stamina stays nil (UI treats as optional)
    @Published private(set) var currentStamina: Double? = nil
    @Published private(set) var activeModelName: String? = nil

    private let subject = PassthroughSubject<AgentEvent, Never>()
    var eventPublisher: AnyPublisher<AgentEvent, Never> { subject.eraseToAnyPublisher() }

    private var pollingTimer: Timer?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var idleTimeoutWorkItem: DispatchWorkItem?

    // Thread tracking
    private var activeThreadId: String = ""
    private var lastSeenUpdatedAt: String = ""
    private var lastSeenMessageCount: Int = 0
    private var lastSeenStepIndex: Int = -1
    private var lastKnownPhase: TranscriptPhase = .idle

    // Queue for replaying intermediate phases (smooth animation pacing)
    private var pendingPhaseQueue:
        [(phase: TranscriptPhase, tool: String?, stepIndex: Int, stepType: String)] = []
    private var drainTimer: Timer?

    // CSV status-duration logging
    private var currentStatusStartTime: Date = Date()
    private var currentStatusPhase: TranscriptPhase = .idle
    private var currentStatusTool: String? = nil

    // MARK: - Phase Model
    enum TranscriptPhase: Equatable {
        case reading
        case thinking
        case writing
        case searching
        case planning
        case running
        case generic
        case completed
        case error
        case idle
    }

    // MARK: Init
    init() {
        checkLocalInstallation()
    }

    private func checkLocalInstallation() {
        isInstalledLocally = !Self.candidateDBPaths().isEmpty
            || FileManager.default.fileExists(atPath: "/Applications/Zed.app")
    }

    /// Existing threads.db paths across all installed Zed channels.
    private static func candidateDBPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let support = "\(home)/Library/Application Support"
        let fm = FileManager.default
        return ["Zed", "Zed Preview", "Zed Dev"]
            .map { "\(support)/\($0)/threads/threads.db" }
            .filter { fm.fileExists(atPath: $0) }
    }

    // MARK: Connect / Disconnect
    func connect(config: ProviderConfig) async throws {
        isConnected = true
        await MainActor.run { startPolling() }
    }

    func disconnect() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        drainTimer?.invalidate()
        drainTimer = nil
        cancelFileWatcher()
        cancelIdleTimeout()
        isConnected = false
        subject.send(.disconnected)
    }

    // MARK: - Polling Loop
    @MainActor
    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.pollOnce() }
        }
        setupFileWatcher()
        pollOnce()
    }

    // MARK: - File watcher (wake hint; polling is the source of truth)
    private func setupFileWatcher() {
        guard let path = Self.candidateDBPaths().first else { return }
        cancelFileWatcher()
        let fd = open(path, O_EVTONLY)
        guard fd != -1 else { return }
        self.fileDescriptor = fd
        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main)
        fileWatcher?.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.pollOnce() }
        }
        fileWatcher?.setCancelHandler { close(fd) }
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

    // MARK: - Poll once: find newest thread across channels, diff, emit
    @MainActor
    private func pollOnce() {
        guard let newest = findNewestThread() else { return }

        // Thread switch → close out previous thread's state.
        if newest.id != activeThreadId {
            if !activeThreadId.isEmpty { handleThreadSwitch() }
            activeThreadId = newest.id
            lastSeenUpdatedAt = ""
            lastSeenMessageCount = 0
            lastSeenStepIndex = -1
        }

        // Cheap gate: nothing new if updated_at hasn't advanced.
        guard newest.updatedAt != lastSeenUpdatedAt else { return }

        // Load + parse the payload (zstd → JSON).
        guard let thread = loadThread(id: newest.id, dbPath: newest.dbPath) else { return }
        lastSeenUpdatedAt = thread.updatedAt

        if activeModelName == nil, let model = thread.model, !model.isEmpty {
            activeModelName = model
        }

        let newSteps = collectNewSteps(from: thread)
        if !newSteps.isEmpty {
            if lastSeenStepIndex < 0 {
                // First attach: jump straight to current state, no replay.
                if let last = newSteps.last {
                    lastSeenStepIndex = last.stepIndex
                    applyPhase(phase: last.phase, tool: last.tool, stepIndex: last.stepIndex,
                               lastStepType: last.stepType, reason: "initial_attach")
                }
            } else {
                pendingPhaseQueue.append(contentsOf: newSteps)
                ensureDrainTimerRunning()
            }
            scheduleIdleTimeout()
        }
        lastSeenMessageCount = thread.messageCount
    }

    // MARK: - Snapshot + metadata query
    private struct ThreadMeta { let id: String; let updatedAt: String; let dbPath: String }

    /// Snapshot a live db to a temp copy (journal_mode=delete → plain copy is
    /// consistent), returning the copy path. Copies -wal/-shm when present.
    private func snapshotDB(_ srcPath: String) -> String? {
        let tmp = NSTemporaryDirectory()
        let dst = tmp + "tokengotchi_zed_\(UUID().uuidString).db"
        let fm = FileManager.default
        guard fm.createFile(atPath: dst, contents: nil) else { return nil }
        do {
            try fm.removeItem(atPath: dst)
            try fm.copyItem(atPath: srcPath, toPath: dst)
            for suffix in ["-wal", "-shm"] {
                let s = srcPath + suffix, d = dst + suffix
                if fm.fileExists(atPath: s) { try? fm.copyItem(atPath: s, toPath: d) }
            }
            return dst
        } catch {
            return nil
        }
    }

    /// Run a read-only sqlite3 query against a db path, returning stdout.
    private func sqliteQuery(_ dbPath: String, _ sql: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-readonly", dbPath, sql]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The most recently updated thread across all channel databases.
    private func findNewestThread() -> ThreadMeta? {
        var best: ThreadMeta? = nil
        for dbPath in Self.candidateDBPaths() {
            guard let snap = snapshotDB(dbPath) else { continue }
            defer {
                try? FileManager.default.removeItem(atPath: snap)
                try? FileManager.default.removeItem(atPath: snap + "-wal")
                try? FileManager.default.removeItem(atPath: snap + "-shm")
            }
            let sql = "SELECT id, updated_at FROM threads ORDER BY updated_at DESC LIMIT 1;"
            guard let out = sqliteQuery(snap, sql)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !out.isEmpty else { continue }
            let parts = out.components(separatedBy: "|")
            guard parts.count >= 2 else { continue }
            let meta = ThreadMeta(id: parts[0], updatedAt: parts[1], dbPath: dbPath)
            if best == nil || meta.updatedAt > best!.updatedAt { best = meta }
        }
        return best
    }

    // MARK: - Load + parse the active thread payload
    private struct ParsedThread {
        let updatedAt: String
        let model: String?
        let messageCount: Int
        let messages: [Any]  // raw message values (dictionaries or the "Resume" string)
    }

    private func loadThread(id: String, dbPath: String) -> ParsedThread? {
        guard let snap = snapshotDB(dbPath) else { return nil }
        defer {
            try? FileManager.default.removeItem(atPath: snap)
            try? FileManager.default.removeItem(atPath: snap + "-wal")
            try? FileManager.default.removeItem(atPath: snap + "-shm")
        }
        let blobPath = snap + ".blob"
        let sql = "SELECT writefile('\(blobPath)', data) FROM threads WHERE id='\(id)';"
        // Also fetch data_type to know whether to zstd-decompress.
        let typeSQL = "SELECT data_type FROM threads WHERE id='\(id)';"
        guard let dataType = sqliteQuery(snap, typeSQL)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        _ = sqliteQuery(snap, sql)
        defer { try? FileManager.default.removeItem(atPath: blobPath) }

        guard var raw = try? Data(contentsOf: URL(fileURLWithPath: blobPath)) else { return nil }
        if dataType == "zstd" {
            guard let dec = try? Zstd.decompress(raw) else { return nil }
            raw = dec
        }
        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return nil }

        let updatedAt = obj["updated_at"] as? String ?? lastSeenUpdatedAt
        var modelName: String? = nil
        if let model = obj["model"] as? [String: Any] {
            let m = model["model"] as? String ?? ""
            let p = model["provider"] as? String ?? ""
            modelName = m.isEmpty ? (p.isEmpty ? nil : p) : m
        }
        let messages = obj["messages"] as? [Any] ?? []
        return ParsedThread(updatedAt: updatedAt, model: modelName,
                            messageCount: messages.count, messages: messages)
    }

    // MARK: - Diff messages → steps
    /// Emits a step for each newly-added message since the last poll, using the
    /// message structure: {"User":...}, {"Agent":{content,tool_results}}, "Resume".
    private func collectNewSteps(from thread: ParsedThread) -> [(
        phase: TranscriptPhase, tool: String?, stepIndex: Int, stepType: String
    )] {
        let startIdx = max(0, lastSeenMessageCount)
        guard thread.messages.count > startIdx else { return [] }

        var results: [(phase: TranscriptPhase, tool: String?, stepIndex: Int, stepType: String)] = []
        var stepIndex = lastSeenStepIndex

        for i in startIdx..<thread.messages.count {
            let msg = thread.messages[i]
            if let dict = msg as? [String: Any] {
                if let user = dict["User"] as? [String: Any] {
                    // A new user prompt → agent starts thinking (unless it's empty / tool-result-like).
                    let content = user["content"] as? [Any] ?? []
                    let hasText = content.contains { ($0 as? [String: Any])?["Text"] != nil }
                    if hasText {
                        stepIndex += 1
                        results.append((.thinking, nil, stepIndex, "user_prompt"))
                    }
                } else if let agent = dict["Agent"] as? [String: Any] {
                    let steps = analyzeAgentMessage(agent, stepIndex: &stepIndex)
                    results.append(contentsOf: steps)
                }
                // Compaction / other dict shapes → ignore
            }
            // "Resume" string → ignore
        }
        return results
    }

    /// Inspect one Agent message: thinking beats, tool calls (with phases), and
    /// completion detection based on whether the last tool call has a result.
    private func analyzeAgentMessage(_ agent: [String: Any], stepIndex: inout Int) -> [(
        phase: TranscriptPhase, tool: String?, stepIndex: Int, stepType: String
    )] {
        let content = agent["content"] as? [Any] ?? []
        let toolResults = agent["tool_results"] as? [String: Any] ?? [:]

        var sawThinking = false
        var sawText = false
        var toolUses: [(id: String, name: String)] = []

        for item in content {
            guard let block = item as? [String: Any] else { continue }
            if block["Thinking"] != nil { sawThinking = true }
            if block["Text"] != nil { sawText = true }
            if let tu = block["ToolUse"] as? [String: Any] {
                let id = tu["id"] as? String ?? ""
                let name = tu["name"] as? String ?? ""
                toolUses.append((id, name))
            }
        }

        var out: [(phase: TranscriptPhase, tool: String?, stepIndex: Int, stepType: String)] = []

        if toolUses.isEmpty {
            if sawThinking {
                stepIndex += 1
                out.append((.thinking, nil, stepIndex, "assistant_thinking"))
            } else if sawText {
                // Pure text with no tool calls → the turn finished with an answer.
                stepIndex += 1
                out.append((.completed, nil, stepIndex, "assistant_text"))
            }
            return out
        }

        // There are tool calls. Lead with a thinking beat for pacing, then the
        // phase of the *last* tool call; whether it's completed or still running
        // depends on a matching entry in tool_results.
        if sawThinking || sawText {
            stepIndex += 1
            out.append((.thinking, nil, stepIndex, "assistant_pre_tool"))
        }
        if let lastTool = toolUses.last {
            let phase = phase(for: lastTool.name)
            let hasResult = toolResults[lastTool.id] != nil
            stepIndex += 1
            if hasResult {
                // Tool finished → surface its phase briefly; idle timer settles it.
                out.append((phase, lastTool.name, stepIndex, "tool_result"))
            } else {
                // Tool call present but no result yet → actively running.
                out.append((phase, lastTool.name, stepIndex, "tool_use"))
            }
        }
        return out
    }

    // MARK: - Tool → Phase Mapping (native Zed tool names, snake_case)
    private func phase(for toolName: String) -> TranscriptPhase {
        switch toolName {
        case "read_file", "list_directory":
            return .reading
        case "edit_file", "write_file", "apply_code_action", "rename", "delete_path":
            return .writing
        case "grep", "find_path", "web_search", "fetch", "diagnostics",
             "find_references", "go_to_definition", "get_code_actions":
            return .searching
        case "terminal":
            return .running
        case "create_thread", "spawn_agent", "list_agents_and_models":
            return .planning
        default:
            // MCP tools (prefixed server names) and anything unrecognized.
            return .generic
        }
    }

    // MARK: - Idle timeout
    private func scheduleIdleTimeout() {
        cancelIdleTimeout()
        let isIdleState = (lastKnownPhase == .completed || lastKnownPhase == .idle)
        let timeoutSeconds = isIdleState ? 1.5 : 60.0
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                guard self.lastKnownPhase != .idle, self.pendingPhaseQueue.isEmpty else { return }
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

    // MARK: - Drain queue (pacing)
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
        applyPhase(phase: next.phase, tool: next.tool, stepIndex: next.stepIndex,
                   lastStepType: next.stepType, reason: "queue_drained")
    }

    // MARK: - Thread switch
    private func handleThreadSwitch() {
        logStatusTransition(eventType: "END", phase: currentStatusPhase, tool: currentStatusTool,
                            stepIndex: lastSeenStepIndex, conversationId: activeThreadId,
                            startTime: currentStatusStartTime, endTime: Date(),
                            reason: "thread_switched", lastStepType: "")
        if lastKnownPhase != .idle {
            subject.send(.completed(taskId: UUID().uuidString, totalTokens: 0))
            subject.send(.idle)
        }
        lastSeenStepIndex = -1
        cancelIdleTimeout()
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

        let now = Date()
        logStatusTransition(eventType: "END", phase: currentStatusPhase, tool: currentStatusTool,
                            stepIndex: lastSeenStepIndex, conversationId: activeThreadId,
                            startTime: currentStatusStartTime, endTime: now,
                            reason: reason, lastStepType: lastStepType)
        currentStatusStartTime = now
        currentStatusPhase = phase
        currentStatusTool = tool
        lastSeenStepIndex = stepIndex

        logStatusTransition(eventType: "START", phase: phase, tool: tool, stepIndex: stepIndex,
                            conversationId: activeThreadId, startTime: now, endTime: now,
                            reason: reason, lastStepType: lastStepType)

        let previousPhase = lastKnownPhase
        lastKnownPhase = phase

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
        case .writing:
            subject.send(.busy(subMode: .writing))
        case .searching:
            subject.send(.busy(subMode: .searching))
        case .planning:
            subject.send(.busy(subMode: .planning))
        case .running:
            subject.send(.busy(subMode: .running))
        case .generic:
            if previousPhase == .idle || previousPhase == .completed {
                subject.send(.started(taskId: UUID().uuidString))
            }
            subject.send(.busy(subMode: nil))
        case .completed:
            subject.send(.completed(taskId: UUID().uuidString, totalTokens: 0))
        case .error:
            subject.send(.failed(taskId: UUID().uuidString, error: ZedError.agentFailed("Transcript error")))
        case .idle:
            break
        }
    }

    private func transitionToIdle(reason: String) {
        let now = Date()
        logStatusTransition(eventType: "END", phase: currentStatusPhase, tool: currentStatusTool,
                            stepIndex: lastSeenStepIndex, conversationId: activeThreadId,
                            startTime: currentStatusStartTime, endTime: now,
                            reason: reason, lastStepType: "")
        currentStatusStartTime = now
        currentStatusPhase = .idle
        currentStatusTool = nil
        pendingPhaseQueue.removeAll()
        drainTimer?.invalidate()
        drainTimer = nil

        cancelIdleTimeout()
        lastKnownPhase = .idle
        currentTool = nil
        subject.send(.completed(taskId: UUID().uuidString, totalTokens: 0))
        subject.send(.idle)
    }

    // MARK: - CSV Status Transition Logging
    private func phaseLabel(_ phase: TranscriptPhase) -> String {
        switch phase {
        case .reading: return "reading"
        case .thinking: return "thinking"
        case .writing: return "writing"
        case .searching: return "searching"
        case .planning: return "planning"
        case .running: return "running"
        case .generic: return "generic"
        case .completed: return "completed"
        case .error: return "error"
        case .idle: return "idle"
        }
    }

    private var logWriteCount: Int = 0
    private func logStatusTransition(
        eventType: String, phase: TranscriptPhase, tool: String?, stepIndex: Int,
        conversationId: String, startTime: Date, endTime: Date, reason: String, lastStepType: String
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
            if let data = row.data(using: .utf8) { fileHandle.write(data) }
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
    enum ZedError: LocalizedError {
        case agentFailed(String)
        var errorDescription: String? {
            switch self {
            case .agentFailed(let msg): return msg
            }
        }
    }
}
