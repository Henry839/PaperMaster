import Darwin
import Foundation
import AppKit
import Observation
import SwiftTerm

struct AgentWorkspacePaths: Equatable, Sendable {
    let rootDirectoryURL: URL
    let sessionsDirectoryURL: URL
    let exportsDirectoryURL: URL
    let logsDirectoryURL: URL
    let attachmentsDirectoryURL: URL
    let skillsDirectoryURL: URL

    static func `default`(fileManager: FileManager = .default) -> AgentWorkspacePaths {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let rootDirectoryURL = applicationSupportURL
            .appendingPathComponent("PaperMaster", isDirectory: true)
            .appendingPathComponent("AgentWorkspace", isDirectory: true)
        return AgentWorkspacePaths(
            rootDirectoryURL: rootDirectoryURL,
            sessionsDirectoryURL: rootDirectoryURL.appendingPathComponent("sessions", isDirectory: true),
            exportsDirectoryURL: rootDirectoryURL.appendingPathComponent("exports", isDirectory: true),
            logsDirectoryURL: rootDirectoryURL.appendingPathComponent("logs", isDirectory: true),
            attachmentsDirectoryURL: rootDirectoryURL.appendingPathComponent("attachments", isDirectory: true),
            skillsDirectoryURL: rootDirectoryURL.appendingPathComponent("skills", isDirectory: true)
        )
    }

    var allDirectories: [URL] {
        [
            rootDirectoryURL,
            sessionsDirectoryURL,
            exportsDirectoryURL,
            logsDirectoryURL,
            attachmentsDirectoryURL,
            skillsDirectoryURL
        ]
    }
}

private enum AgentWorkspaceBootstrapFiles {
    static let directOpsSkillName = "papermaster-agent-ops"

    static func write(to paths: AgentWorkspacePaths, fileManager: FileManager) throws {
        try write(
            contents: agentsFileContents(skillPath: paths.skillsDirectoryURL.appendingPathComponent(directOpsSkillName, isDirectory: true).appendingPathComponent("SKILL.md")),
            to: paths.rootDirectoryURL.appendingPathComponent("AGENTS.md"),
            fileManager: fileManager
        )

        let skillDirectoryURL = paths.skillsDirectoryURL.appendingPathComponent(directOpsSkillName, isDirectory: true)
        try fileManager.createDirectory(at: skillDirectoryURL, withIntermediateDirectories: true)
        try write(
            contents: skillContents,
            to: skillDirectoryURL.appendingPathComponent("SKILL.md"),
            fileManager: fileManager
        )
    }

    private static func write(contents: String, to url: URL, fileManager: FileManager) throws {
        let existingContents = try? String(contentsOf: url, encoding: .utf8)
        guard existingContents != contents else { return }

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func agentsFileContents(skillPath: URL) -> String {
        """
        # PaperMaster Agent Workspace

        This workspace is created by PaperMaster for in-app terminal agents.

        ## Direct Operation Rules

        - Prefer deterministic local actions over long planning when the request is concrete.
        - Keep pre-action commentary to one short sentence.
        - If the user gives a paper URL or PDF path, act immediately instead of brainstorming.
        - Use `PAPERMASTER_AGENT_IMPORT_DIR` as the fast-path drop folder for PDF imports when local paper storage is enabled.

        ## Environment

        - `PAPERMASTER_AGENT_WORKSPACE`: workspace root.
        - `PAPERMASTER_AGENT_SESSION_DIR`: current terminal session directory.
        - `PAPERMASTER_AGENT_IMPORT_DIR`: PaperMaster agent import inbox watched by the app.
        - `PAPERMASTER_AGENT_EXPORTS_DIR`: place generated artifacts here if needed.

        ## Available Skills

        - `papermaster-agent-ops`: Direct, low-friction PaperMaster operations for import and other routine agent tasks. (file: \(skillPath.path))

        ## Skill Trigger Rules

        - Use `papermaster-agent-ops` when the user asks to import, add, download, collect, or hand off a paper into PaperMaster.
        - Also use it when the user explicitly names `papermaster-agent-ops`.
        """
    }

    private static let skillContents = """
    ---
    name: papermaster-agent-ops
    description: Use inside the PaperMaster terminal when the user wants direct manipulation of the PaperMaster workflow, especially fast paper import with minimal deliberation. Trigger for requests to import, add, download, collect, or hand off a paper into PaperMaster.
    ---

    # PaperMaster Agent Ops

    Use this skill when working inside PaperMaster's integrated terminal.

    ## Core Behavior

    - Prefer the fastest deterministic path over extended reasoning.
    - If the request already contains a URL, arXiv link, or local PDF path, start acting immediately.
    - Keep status updates short and operational.
    - Only stop to ask a question when the source paper is genuinely ambiguous.

    ## Fast Import Path

    For local paper storage setups, PaperMaster watches `PAPERMASTER_AGENT_IMPORT_DIR` and auto-imports PDFs dropped there.

    1. If the user gives a direct PDF URL, download it straight into `PAPERMASTER_AGENT_IMPORT_DIR`.
    2. If the user gives an arXiv abstract URL, rewrite it to the PDF URL and download that PDF.
    3. If the user gives a local PDF path, copy it into `PAPERMASTER_AGENT_IMPORT_DIR`.
    4. After the file exists, stop. PaperMaster will ingest it.
    5. Report the saved file path briefly.

    Example commands:

    ```bash
    curl -L "https://arxiv.org/pdf/2501.01234.pdf" -o "$PAPERMASTER_AGENT_IMPORT_DIR/2501.01234.pdf"
    cp "/path/to/paper.pdf" "$PAPERMASTER_AGENT_IMPORT_DIR/"
    ```

    ## Guardrails

    - Do not spend time pre-checking duplicates unless it is nearly free.
    - Do not explain PaperMaster internals unless the user asks.
    - If local import shortcuts are not appropriate, fall back to the normal requested workflow.
    """
}

enum AgentToolPermissionLevel: String, CaseIterable, Identifiable, Sendable {
    case readOnly
    case libraryWrite
    case sensitiveConfirm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readOnly:
            "Read Only"
        case .libraryWrite:
            "Library Write"
        case .sensitiveConfirm:
            "Confirm Required"
        }
    }

    var summary: String {
        switch self {
        case .readOnly:
            "Inspect the library, queue, and paper details without changing data."
        case .libraryWrite:
            "Create imports, update notes, tags, and reading status."
        case .sensitiveConfirm:
            "High-impact actions such as bulk rewrites or destructive changes."
        }
    }
}

struct AgentToolDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let summary: String
    let permissionLevel: AgentToolPermissionLevel
    let inputSchemaSummary: String
}

enum AgentToolCatalog {
    static let defaultTools: [AgentToolDefinition] = [
        AgentToolDefinition(
            id: "paper.search",
            displayName: "Search Papers",
            summary: "Search titles, authors, abstracts, venues, DOI, and tags in the local library.",
            permissionLevel: .readOnly,
            inputSchemaSummary: #"{"query":"transformer interpretability"}"#
        ),
        AgentToolDefinition(
            id: "paper.list_today",
            displayName: "List Today",
            summary: "Return papers that are due today or overdue in the active queue.",
            permissionLevel: .readOnly,
            inputSchemaSummary: #"{}"#
        ),
        AgentToolDefinition(
            id: "paper.get_detail",
            displayName: "Get Detail",
            summary: "Inspect a paper's metadata, notes, tags, queue status, and local file pointers.",
            permissionLevel: .readOnly,
            inputSchemaSummary: #"{"paperID":"UUID"}"#
        ),
        AgentToolDefinition(
            id: "paper.import",
            displayName: "Import Paper",
            summary: "Import from a URL or local PDF and place it into the PaperMaster library.",
            permissionLevel: .libraryWrite,
            inputSchemaSummary: #"{"sourceText":"https://arxiv.org/abs/...", "tagNames":["llm", "agents"]}"#
        ),
        AgentToolDefinition(
            id: "paper.update_notes",
            displayName: "Update Notes",
            summary: "Write or append structured notes and summaries to a paper record.",
            permissionLevel: .libraryWrite,
            inputSchemaSummary: #"{"paperID":"UUID","mode":"append","content":"..."}"#
        ),
        AgentToolDefinition(
            id: "paper.update_tags",
            displayName: "Update Tags",
            summary: "Replace or refine paper tags using the app's normalized tag model.",
            permissionLevel: .libraryWrite,
            inputSchemaSummary: #"{"paperID":"UUID","tags":["rag","retrieval"]}"#
        ),
        AgentToolDefinition(
            id: "paper.plan_queue",
            displayName: "Plan Queue",
            summary: "Propose or apply a reading order using the scheduler and queue positions.",
            permissionLevel: .libraryWrite,
            inputSchemaSummary: #"{"paperIDs":["UUID"],"papersPerDay":2}"#
        ),
        AgentToolDefinition(
            id: "paper.move_queue_item",
            displayName: "Move Queue Item",
            summary: "Reposition a paper inside the active queue.",
            permissionLevel: .libraryWrite,
            inputSchemaSummary: #"{"paperID":"UUID","destinationIndex":0}"#
        ),
        AgentToolDefinition(
            id: "paper.bulk_apply",
            displayName: "Bulk Apply",
            summary: "Batch-write tags, notes, or queue changes across multiple papers.",
            permissionLevel: .sensitiveConfirm,
            inputSchemaSummary: #"{"operations":[...]}"#
        )
    ]
}

enum AgentTerminalSessionState: String, Sendable {
    case launching
    case running
    case exited
    case failed
}

enum AgentTerminalError: LocalizedError {
    case ptyCreationFailed
    case forkFailed
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .ptyCreationFailed:
            "Couldn't create a terminal pseudo-terminal."
        case .forkFailed:
            "Couldn't spawn the terminal process."
        case let .launchFailed(message):
            "Couldn't launch the terminal process: \(message)"
        }
    }
}

@MainActor
@Observable
final class AgentTerminalSession: Identifiable {
    let id: UUID
    let index: Int
    let workingDirectoryURL: URL
    let shellPath: String
    let shellArguments: [String]

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private var masterFileHandle: FileHandle?
    @ObservationIgnored private var processMonitor: DispatchSourceProcess?
    @ObservationIgnored private var childPID: pid_t = 0

    var title: String
    var transcript: String
    var state: AgentTerminalSessionState
    var launchedAt: Date
    var exitStatus: Int32?
    var lastErrorMessage: String?

    init(
        index: Int,
        workingDirectoryURL: URL,
        shellPath: String = "/bin/zsh",
        shellArguments: [String] = ["-l"],
        fileManager: FileManager = .default
    ) {
        self.id = UUID()
        self.index = index
        self.workingDirectoryURL = workingDirectoryURL
        self.shellPath = shellPath
        self.shellArguments = shellArguments
        self.fileManager = fileManager
        self.title = "Terminal \(index)"
        self.transcript = ""
        self.state = .launching
        self.launchedAt = .now
    }
    func start(environment: [String: String]) throws {
        try fileManager.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true)

        var masterFD: Int32 = 0
        var slaveFD: Int32 = 0
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw AgentTerminalError.ptyCreationFailed
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, masterFD)
        posix_spawn_file_actions_addclose(&fileActions, slaveFD)
        _ = workingDirectoryURL.path.withCString {
            posix_spawn_file_actions_addchdir_np(&fileActions, $0)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)

        var pid = pid_t()
        let mergedEnvironment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in newValue }
        let spawnResult = makeSpawnArguments(for: shellPath, arguments: shellArguments) { argv in
            makeSpawnEnvironment(from: mergedEnvironment) { envp in
                shellPath.withCString { executablePath in
                    posix_spawn(&pid, executablePath, &fileActions, &attributes, argv, envp)
                }
            }
        }

        posix_spawn_file_actions_destroy(&fileActions)
        posix_spawnattr_destroy(&attributes)

        guard spawnResult == 0 else {
            close(masterFD)
            close(slaveFD)
            throw AgentTerminalError.launchFailed(String(cString: strerror(spawnResult)))
        }

        close(slaveFD)
        childPID = pid
        let fileHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        masterFileHandle = fileHandle
        state = .running
        transcript = "Launching \(shellPath) \(shellArguments.joined(separator: " "))\n"

        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            let output = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.appendToTranscript(output)
            }
        }

        let monitor = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        monitor.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
            self.exitStatus = status
            self.state = .exited
            self.masterFileHandle?.readabilityHandler = nil
            self.processMonitor?.cancel()
            self.processMonitor = nil
        }
        monitor.setCancelHandler {
            // Nothing else to release here; FileHandle owns the master descriptor.
        }
        processMonitor = monitor
        monitor.resume()
    }

    func send(_ input: String) {
        guard let masterFileHandle else { return }
        let payload = Data(input.utf8)
        do {
            try masterFileHandle.write(contentsOf: payload)
        } catch {
            lastErrorMessage = error.localizedDescription
            state = .failed
        }
    }

    func stop() {
        guard childPID > 0 else { return }
        kill(childPID, SIGHUP)
    }

    private func appendToTranscript(_ output: String) {
        transcript.append(output)
        let maximumCharacters = 120_000
        if transcript.count > maximumCharacters {
            transcript = String(transcript.suffix(maximumCharacters))
        }
    }
}

@MainActor
@Observable
final class AgentRuntimeService {
    let workspacePaths: AgentWorkspacePaths
    let toolCatalog: [AgentToolDefinition]

    @ObservationIgnored private let fileManager: FileManager

    var sessions: [AgentTerminalSession] = []
    var selectedSessionID: UUID?
    var preferredPermissionLevel: AgentToolPermissionLevel = .libraryWrite
    var lastBootstrapErrorMessage: String?
    var isPanelVisible = false
    var panelHeight: CGFloat = 260
    let minimumPanelHeight: CGFloat = 180
    let maximumPanelHeight: CGFloat = 620
    var embeddedSessions: [EmbeddedTerminalSession] = []
    var selectedEmbeddedSessionID: UUID?

    init(
        workspacePaths: AgentWorkspacePaths = .default(),
        toolCatalog: [AgentToolDefinition] = AgentToolCatalog.defaultTools,
        fileManager: FileManager = .default
    ) {
        self.workspacePaths = workspacePaths
        self.toolCatalog = toolCatalog
        self.fileManager = fileManager
    }

    var selectedSession: AgentTerminalSession? {
        sessions.first(where: { $0.id == selectedSessionID })
    }

    var selectedEmbeddedSession: EmbeddedTerminalSession? {
        embeddedSessions.first(where: { $0.id == selectedEmbeddedSessionID })
    }

    func bootstrapWorkspace() {
        do {
            for directoryURL in workspacePaths.allDirectories {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            try AgentWorkspaceBootstrapFiles.write(to: workspacePaths, fileManager: fileManager)
            lastBootstrapErrorMessage = nil
        } catch {
            lastBootstrapErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createSession() -> AgentTerminalSession? {
        bootstrapWorkspace()
        guard lastBootstrapErrorMessage == nil else { return nil }

        let sessionIndex = sessions.count + 1
        let sessionDirectoryURL = workspacePaths.sessionsDirectoryURL
            .appendingPathComponent("session-\(sessionIndex)", isDirectory: true)
        let session = AgentTerminalSession(index: sessionIndex, workingDirectoryURL: sessionDirectoryURL)
        do {
            try session.start(environment: shellEnvironment(for: session))
            sessions.append(session)
            selectedSessionID = session.id
            return session
        } catch {
            session.state = .failed
            session.lastErrorMessage = error.localizedDescription
            lastBootstrapErrorMessage = error.localizedDescription
            sessions.append(session)
            selectedSessionID = session.id
            return session
        }
    }

    func removeSession(_ session: AgentTerminalSession) {
        session.stop()
        sessions.removeAll { $0.id == session.id }
        if selectedSessionID == session.id {
            selectedSessionID = sessions.last?.id
        }
    }

    @discardableResult
    func createEmbeddedSession() -> EmbeddedTerminalSession? {
        bootstrapWorkspace()
        guard lastBootstrapErrorMessage == nil else { return nil }

        let index = embeddedSessions.count + 1
        let sessionDirectoryURL = workspacePaths.sessionsDirectoryURL
            .appendingPathComponent("session-\(index)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: sessionDirectoryURL, withIntermediateDirectories: true)
        } catch {
            lastBootstrapErrorMessage = error.localizedDescription
            return nil
        }

        let session = EmbeddedTerminalSession(
            index: index,
            workingDirectoryURL: sessionDirectoryURL,
            environment: shellEnvironment(workingDirectoryURL: sessionDirectoryURL)
        )
        embeddedSessions.append(session)
        selectedEmbeddedSessionID = session.id
        isPanelVisible = true
        return session
    }

    func removeEmbeddedSession(_ session: EmbeddedTerminalSession) {
        session.terminate()
        embeddedSessions.removeAll { $0.id == session.id }
        if selectedEmbeddedSessionID == session.id {
            selectedEmbeddedSessionID = embeddedSessions.last?.id
        }
        if embeddedSessions.isEmpty {
            isPanelVisible = false
        }
    }

    func setPanelHeight(_ proposedHeight: CGFloat) {
        panelHeight = min(maximumPanelHeight, max(minimumPanelHeight, proposedHeight))
    }

    func openSystemTerminal() {
        bootstrapWorkspace()
        guard lastBootstrapErrorMessage == nil else { return }

        let startupCommand = [
            "cd \(shellQuoted(workspacePaths.rootDirectoryURL.path))",
            "clear",
            "printf '\\nPaperMaster Agent Workspace\\n'",
            "printf 'Path: %s\\n\\n' \(shellQuoted(workspacePaths.rootDirectoryURL.path))"
        ].joined(separator: "; ")

        let script = """
        tell application "Terminal"
            activate
            do script \(appleScriptQuoted(startupCommand))
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
        } catch {
            lastBootstrapErrorMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    private func shellEnvironment(for session: AgentTerminalSession) -> [String: String] {
        shellEnvironment(workingDirectoryURL: session.workingDirectoryURL)
    }

    private func shellEnvironment(workingDirectoryURL: URL) -> [String: String] {
        [
            "TERM": "xterm-256color",
            "PAPERMASTER_AGENT_WORKSPACE": workspacePaths.rootDirectoryURL.path,
            "PAPERMASTER_AGENT_SESSION_DIR": workingDirectoryURL.path,
            "PAPERMASTER_AGENT_EXPORTS_DIR": workspacePaths.exportsDirectoryURL.path,
            "PAPERMASTER_AGENT_ATTACHMENTS_DIR": workspacePaths.attachmentsDirectoryURL.path,
            "PAPERMASTER_AGENT_IMPORT_DIR": workspacePaths.attachmentsDirectoryURL.path,
            "PAPERMASTER_AGENT_LOGS_DIR": workspacePaths.logsDirectoryURL.path,
            "PAPERMASTER_AGENT_SKILLS_DIR": workspacePaths.skillsDirectoryURL.path,
            "PAPERMASTER_AGENT_PERMISSION_LEVEL": preferredPermissionLevel.rawValue
        ]
    }
}

@MainActor
@Observable
final class EmbeddedTerminalSession: Identifiable {
    let id = UUID()
    let index: Int
    let workingDirectoryURL: URL
    let environment: [String: String]

    @ObservationIgnored var terminalView: LocalProcessTerminalView?
    @ObservationIgnored private var processDelegateProxy: EmbeddedTerminalProcessDelegate?

    var title: String
    var currentDirectoryPath: String?
    var didStart = false

    init(index: Int, workingDirectoryURL: URL, environment: [String: String]) {
        self.index = index
        self.workingDirectoryURL = workingDirectoryURL
        self.environment = environment
        self.title = "Terminal \(index)"
    }

    func configure(_ terminalView: LocalProcessTerminalView) {
        guard self.terminalView !== terminalView else { return }

        self.terminalView = terminalView
        let delegate = EmbeddedTerminalProcessDelegate(session: self)
        processDelegateProxy = delegate
        terminalView.processDelegate = delegate
        terminalView.nativeForegroundColor = NSColor(
            calibratedRed: CGFloat(0xcc) / 255.0,
            green: CGFloat(0xcc) / 255.0,
            blue: CGFloat(0xcc) / 255.0,
            alpha: 1.0
        )
        terminalView.nativeBackgroundColor = NSColor(
            calibratedRed: CGFloat(0x1f) / 255.0,
            green: CGFloat(0x23) / 255.0,
            blue: CGFloat(0x2b) / 255.0,
            alpha: 1.0
        )
        terminalView.layer?.backgroundColor = terminalView.nativeBackgroundColor.cgColor
        terminalView.caretColor = .white
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.optionAsMetaKey = true
        terminalView.getTerminal().setCursorStyle(.steadyBlock)
    }

    func startIfNeeded() {
        guard didStart == false, let terminalView else { return }
        let shell = userShell()
        let shellIdiom = "-" + NSString(string: shell).lastPathComponent
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: environment.map { "\($0.key)=\($0.value)" },
            execName: shellIdiom,
            currentDirectory: workingDirectoryURL.path
        )
        didStart = true
    }

    func terminate() {
        terminalView?.terminate()
    }

    private func userShell() -> String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }
}

private final class EmbeddedTerminalProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
    unowned let session: EmbeddedTerminalSession

    init(session: EmbeddedTerminalSession) {
        self.session = session
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { [session] in
            session.title = title.isEmpty ? "Terminal \(session.index)" : title
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        DispatchQueue.main.async { [session] in
            session.currentDirectoryPath = directory
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [session] in
            session.didStart = false
        }
    }
}

private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

private func appleScriptQuoted(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

private func makeSpawnArguments<Result>(
    for executablePath: String,
    arguments: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
) -> Result {
    var argv = ([executablePath] + arguments).map { strdup($0) }
    argv.append(nil)
    defer {
        for case let pointer? in argv {
            free(pointer)
        }
    }

    return argv.withUnsafeMutableBufferPointer { buffer in
        body(buffer.baseAddress!)
    }
}

private func makeSpawnEnvironment<Result>(
    from environment: [String: String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
) -> Result {
    let entries = environment
        .map { "\($0.key)=\($0.value)" }
        .sorted()
    var envp: [UnsafeMutablePointer<CChar>?] = entries.map { strdup($0) }
    envp.append(nil)
    defer {
        for case let pointer? in envp {
            free(pointer)
        }
    }

    return envp.withUnsafeMutableBufferPointer { buffer in
        body(buffer.baseAddress!)
    }
}
