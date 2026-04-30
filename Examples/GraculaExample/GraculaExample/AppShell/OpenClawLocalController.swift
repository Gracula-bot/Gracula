import AppKit
import Automation
import Foundation

@MainActor
final class OpenClawLocalController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Stopped"
    @Published private(set) var gatewayStatus = "not checked"
    @Published private(set) var streamBridgeStatus = "not checked"
    @Published private(set) var logLines: [String] = []
    @Published private(set) var chatMessages: [OpenClawChatMessage] = []
    @Published private(set) var chatStatusText = "Ready to chat."
    @Published private(set) var isSendingChat = false
    @Published private(set) var settingsSnapshot: OpenClawSettingsSnapshot
    @Published private(set) var settingsStatusText = "Settings loaded."

    let repositoryDirectory = resolveOpenClawRepositoryDirectory()
    let configDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".openclaw", isDirectory: true)
    let workspaceDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".openclaw", isDirectory: true)
        .appendingPathComponent("workspace", isDirectory: true)

    private let nodeURL = URL(filePath: "/opt/homebrew/bin/node")
    private let gatewayHost = "127.0.0.1"
    private let fallbackGatewayPort = "18789"
    private let streamBridgePort = "7071"
    private let onlyFansPoster = WorkspaceOpeningClient()
    private var chatSessionID = "gracula-local-chat"
    private var gatewayProcess: Process?
    private var streamBridgeProcess: Process?
    private var healthTask: Task<Void, Never>?

    init() {
        self.settingsSnapshot = Self.makeSettingsSnapshot()
        if shouldResetCurrentSessionOnLaunch() {
            resetChat()
        }
    }

    var chatSessionLabel: String {
        let prefix = "gracula-local-chat-"
        if chatSessionID.hasPrefix(prefix) {
            let suffix = chatSessionID.dropFirst(prefix.count)
            return "gracula-local-chat • \(suffix.prefix(8))"
        }
        return chatSessionID
    }

    deinit {
        gatewayProcess?.terminate()
        streamBridgeProcess?.terminate()
        healthTask?.cancel()
    }

    func start() {
        guard !isRunning else {
            appendLog("OpenClaw is already running.")
            return
        }

        do {
            try validateRuntime()
            try prepareDirectories()
            let environment = try openClawEnvironment()
            settingsSnapshot = Self.makeSettingsSnapshot(environment: environment)

            do {
                gatewayProcess = try launchProcess(
                    name: "gateway",
                    arguments: [
                        repositoryDirectory.appendingPathComponent("dist/index.js").path,
                        "gateway",
                        "run",
                        "--allow-unconfigured",
                        "--bind",
                        environment["OPENCLAW_GATEWAY_BIND"] ?? "loopback",
                        "--port",
                        environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort
                    ],
                    environment: environment
                )
                isRunning = true
                statusText = "Starting local OpenClaw..."
                appendLog("Started OpenClaw gateway locally without Docker.")
                appendLog("Gateway: http://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)/")
            } catch {
                let launchErrorMessage = error.localizedDescription
                let normalizedLaunchError = launchErrorMessage.lowercased()
                let gatewayAlreadyRunning = normalizedLaunchError.contains("already running")
                    || normalizedLaunchError.contains("port 18789 is already in use")
                    || normalizedLaunchError.contains("lock timeout")

                if gatewayAlreadyRunning {
                    gatewayProcess = nil
                    isRunning = true
                    statusText = "Using existing OpenClaw gateway..."
                    gatewayStatus = "existing"
                    appendLog("OpenClaw gateway is already running outside the app; attaching to http://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)/")
                } else {
                    throw error
                }
            }

            if isEnabled(environment["OPENCLAW_ENABLE_STREAM_BRIDGE"]) {
                do {
                    streamBridgeProcess = try launchProcess(
                        name: "stream-bridge",
                        arguments: [
                            repositoryDirectory.appendingPathComponent("dist/telegram-stream/docker-stream-bridge.js").path
                        ],
                        environment: environment,
                        updateRunningStateOnExit: false
                    )
                    appendLog("Stream bridge: http://\(gatewayHost):\(streamBridgePort)/health")
                } catch {
                    streamBridgeProcess = nil
                    streamBridgeStatus = "unavailable"
                    appendLog("Stream bridge unavailable: \(error.localizedDescription)")
                }
            } else {
                streamBridgeProcess = nil
                streamBridgeStatus = "disabled"
                appendLog("Stream bridge disabled. Set OPENCLAW_ENABLE_STREAM_BRIDGE=1 to start Telegram/OBS streaming support.")
            }

            scheduleHealthChecks()
        } catch {
            stop()
            statusText = "Start failed"
            appendLog("Start failed: \(error.localizedDescription)")
            appendChatMessage(.error(error.localizedDescription))
        }
    }

    func stop() {
        healthTask?.cancel()
        healthTask = nil
        terminate(process: gatewayProcess, name: "gateway")
        terminate(process: streamBridgeProcess, name: "stream-bridge")
        gatewayProcess = nil
        streamBridgeProcess = nil
        isRunning = false
        statusText = "Stopped"
        gatewayStatus = "stopped"
        streamBridgeStatus = "stopped"
    }

    func openDashboard() {
        NSWorkspace.shared.open(URL(string: "http://\(gatewayHost):\(gatewayPort)/")!)
    }

    func refreshHealth() async {
        reloadSettings()
        gatewayStatus = await checkHealth(url: URL(string: "http://\(gatewayHost):\(gatewayPort)/healthz")!)
        if streamBridgeProcess?.isRunning == true {
            streamBridgeStatus = await checkHealth(url: URL(string: "http://\(gatewayHost):\(streamBridgePort)/health")!)
        } else if streamBridgeStatus != "disabled" {
            streamBridgeStatus = streamBridgeProcess == nil ? "disabled" : "stopped"
        }
        statusText = isRunning ? "Running" : "Stopped"
    }

    func reportError(_ message: String) {
        appendChatMessage(.error(message))
    }

    func reloadSettings() {
        settingsSnapshot = Self.makeSettingsSnapshot()
        settingsStatusText = "Settings reloaded."
    }

    func testSelectedModel(
        environmentEntries: [OpenClawEditableSetting],
        jsonEntries: [OpenClawEditableSetting],
        workspaceFiles: [OpenClawWorkspaceFile]
    ) async {
        do {
            settingsStatusText = "Testing selected model..."
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("gracula-model-test-\(UUID().uuidString)", isDirectory: true)
            let tempConfigDirectory = tempDirectory.appendingPathComponent(".openclaw", isDirectory: true)
            let tempWorkspaceDirectory = tempConfigDirectory.appendingPathComponent("workspace", isDirectory: true)
            let tempConfigURL = tempConfigDirectory.appendingPathComponent("openclaw.json")
            try prepareTestDirectories(
                configDirectory: tempConfigDirectory,
                workspaceDirectory: tempWorkspaceDirectory
            )
            try OpenClawSettingsReader.writeEnvironment(
                entries: environmentEntries,
                to: tempConfigDirectory.appendingPathComponent(".env")
            )
            try OpenClawSettingsReader.writeJSON(
                entries: jsonEntries,
                to: tempConfigURL
            )
            try OpenClawSettingsReader.writeWorkspaceFiles(workspaceFiles, to: tempWorkspaceDirectory)
            try copyAuthStoreIntoTestSandbox(
                sandboxDirectory: tempDirectory
            )

            let environment = try openClawEnvironment(
                configDirectory: tempConfigDirectory,
                workspaceDirectory: tempWorkspaceDirectory,
                configPath: tempConfigURL,
                stateDirectory: tempDirectory
            )
            let testSessionID = "gracula-model-test-\(UUID().uuidString)"
            let response = try await runAgentTurn(
                message: "Reply with exactly: model test ok",
                sessionID: testSessionID,
                environment: environment
            )
            if let status = response.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               status == "error" {
                throw OpenClawLocalControllerError.agentFailed(
                    response.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "Selected model returned an error status."
                )
            }
            let reply = response.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else {
                throw OpenClawLocalControllerError.agentFailed("Selected model returned an empty reply.")
            }
            if reply.hasPrefix("LLM error:") {
                throw OpenClawLocalControllerError.agentFailed(reply)
            }
            settingsStatusText = "Model test passed."
            appendChatMessage(.system("Model test passed: \(reply)"))
            appendLog("Selected model test passed with reply: \(reply)")
        } catch {
            let message = "Model test failed: \(error.localizedDescription)"
            settingsStatusText = message
            appendChatMessage(.error(message))
            appendLog(message)
        }
    }

    private func copyAuthStoreIntoTestSandbox(sandboxDirectory: URL) throws {
        let fileManager = FileManager.default
        let sourceAuthStore = configDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("auth-profiles.json")
        guard fileManager.fileExists(atPath: sourceAuthStore.path) else {
            return
        }

        let destinationAuthStore = sandboxDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("auth-profiles.json")
        try fileManager.createDirectory(
            at: destinationAuthStore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationAuthStore.path) {
            try fileManager.removeItem(at: destinationAuthStore)
        }
        try fileManager.copyItem(at: sourceAuthStore, to: destinationAuthStore)
        appendLog("Copied auth-profiles.json into the model test sandbox.")
    }

    func applySettings(
        environmentEntries: [OpenClawEditableSetting],
        jsonEntries: [OpenClawEditableSetting],
        workspaceFiles: [OpenClawWorkspaceFile]
    ) {
        do {
            try OpenClawSettingsReader.writeEnvironment(entries: environmentEntries)
            try OpenClawSettingsReader.writeJSON(entries: jsonEntries)
            try OpenClawSettingsReader.writeWorkspaceFiles(workspaceFiles)
            reloadSettings()
            settingsStatusText = isRunning
                ? "Settings applied. Restart OpenClaw to apply process environment changes."
                : "Settings applied."
            appendLog(settingsStatusText)
        } catch {
            settingsStatusText = "Settings apply failed: \(error.localizedDescription)"
            appendLog(settingsStatusText)
        }
    }

    func resetChat() {
        chatMessages.removeAll(keepingCapacity: true)
        chatStatusText = "Ready to chat."
        chatSessionID = "gracula-local-chat-\(UUID().uuidString)"
        appendChatMessage(.system("Started a new local OpenClaw conversation."))
    }

    @discardableResult
    func sendChatMessage(_ text: String) async -> String? {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return nil
        }

        do {
            if shouldResetChatSessionBeforeSending(message) {
                appendLog("Resetting stale chat session before send.")
                resetChat()
            }
            isSendingChat = true
            chatStatusText = "Sending to OpenClaw..."
            appendChatMessage(.user(message))

            if isExplicitOnlyFansPublishRequest(message) {
                let reply = try await publishOnlyFansPostFromChatCommand(message)
                appendChatMessage(.assistant(reply))
                chatStatusText = "OnlyFans post published."
                isSendingChat = false
                return reply
            }
            let response = try await runAgentTurn(message: message, sessionID: chatSessionID)
            let reply = response.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeStaleAssistantReply(reply) {
                appendLog("OpenClaw returned a stale reply; resetting chat and retrying once.")
                resetChat()
                appendChatMessage(.user(message))
                let retryResponse = try await runAgentTurn(message: message, sessionID: chatSessionID)
                let retryReply = retryResponse.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !retryReply.isEmpty, !looksLikeStaleAssistantReply(retryReply) else {
                    let failure = "OpenClaw returned a stale reply for this turn."
                    appendChatMessage(.error(failure))
                    chatStatusText = "Chat failed."
                    appendLog(failure)
                    isSendingChat = false
                    return nil
                }
                appendChatMessage(.assistant(retryReply))
                chatStatusText = "Reply received."
                isSendingChat = false
                return retryReply
            }
            if reply.isEmpty {
                let failure = "OpenClaw returned an empty reply for this turn."
                appendChatMessage(.error(failure))
                chatStatusText = "Chat failed."
                appendLog(failure)
                isSendingChat = false
                return nil
            }
            appendChatMessage(.assistant(reply))
            chatStatusText = "Reply received."
            isSendingChat = false
            return reply
        } catch {
            appendChatMessage(.error(error.localizedDescription))
            chatStatusText = "Chat failed."
            appendLog("Chat failed: \(error.localizedDescription)")
            isSendingChat = false
            return nil
        }
    }

    private func shouldResetChatSessionBeforeSending(_ message: String) -> Bool {
        guard let lastReply = latestAssistantReplyFromSession() else {
            return false
        }

        let normalizedReply = normalizedCommandText(lastReply)
        let staleReplyMarkers = [
            "Жду инструкций",
            "Waiting for your instructions",
            "Continue where I left off",
            "Continue where you left off",
            "fill SOUL.md",
            "SOUL.md",
            "What rules should I apply",
            "Can you clarify",
        ]
        return staleReplyMarkers
            .map(normalizedCommandText)
            .contains(where: { normalizedReply.contains($0) })
    }

    private func shouldResetCurrentSessionOnLaunch() -> Bool {
        guard let lastReply = latestAssistantReplyFromSession() else {
            return false
        }

        return looksLikeStaleAssistantReply(lastReply)
    }

    private func looksLikeStaleAssistantReply(_ reply: String) -> Bool {
        let normalizedReply = normalizedCommandText(reply)
        let staleReplyMarkers = [
            "Жду инструкций",
            "Waiting for your instructions",
            "Continue where I left off",
            "Continue where you left off",
            "fill SOUL.md",
            "SOUL.md",
            "What rules should I apply",
            "Can you clarify",
        ]
        return staleReplyMarkers
            .map(normalizedCommandText)
            .contains(where: { normalizedReply.contains($0) })
    }

    private func validateRuntime() throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: nodeURL.path) else {
            throw OpenClawLocalControllerError.missingRuntime("Node runtime not found at \(nodeURL.path).")
        }
        guard fileManager.fileExists(atPath: repositoryDirectory.appendingPathComponent("dist/index.js").path) else {
            throw OpenClawLocalControllerError.missingRuntime("OpenClaw dist/index.js not found. Build the OpenClaw checkout referenced by the app first.")
        }
    }

    private func prepareDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: configDirectory.appendingPathComponent("canvas", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: configDirectory.appendingPathComponent("cron", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func openClawEnvironment(
        configDirectory: URL? = nil,
        workspaceDirectory: URL? = nil,
        configPath: URL? = nil,
        stateDirectory: URL? = nil
    ) throws -> [String: String] {
        let configDirectory = configDirectory ?? self.configDirectory
        let workspaceDirectory = workspaceDirectory ?? self.workspaceDirectory
        let stateDirectory = stateDirectory ?? configDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")

        mergeEnvFile(repositoryDirectory.appendingPathComponent(".env"), into: &environment)
        mergeEnvFile(configDirectory.appendingPathComponent(".env"), into: &environment)
        if (environment["KILOCODE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty,
           let token = resolveKiloCLIAccessToken() {
            environment["KILOCODE_API_KEY"] = token
        }

        environment["OPENCLAW_CONFIG_DIR"] = configDirectory.path
        environment["OPENCLAW_WORKSPACE_DIR"] = workspaceDirectory.path
        environment["OPENCLAW_STATE_DIR"] = stateDirectory.path
        if let configPath {
            environment["OPENCLAW_CONFIG_PATH"] = configPath.path
        } else {
            environment["OPENCLAW_CONFIG_PATH"] = configDirectory.appendingPathComponent("openclaw.json").path
        }
        environment["OPENCLAW_GATEWAY_BIND"] = "loopback"
        environment["OPENCLAW_GATEWAY_PORT"] = environment["OPENCLAW_GATEWAY_PORT"] ?? configuredGatewayPort(from: environment)
        environment["OPENCLAW_GATEWAY_URL"] = "ws://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)"
        environment["OPENCLAW_BRIDGE_PORT"] = environment["OPENCLAW_BRIDGE_PORT"] ?? "18790"
        environment["OPENCLAW_STREAM_BRIDGE_HOST"] = gatewayHost
        environment["OPENCLAW_STREAM_BRIDGE_PORT"] = streamBridgePort
        environment["OPENCLAW_STREAM_BRIDGE_URL"] = "http://\(gatewayHost):\(streamBridgePort)/api/control/speak"
        environment["OPENCLAW_TRACK_BRIDGE_URL"] = "http://\(gatewayHost):\(streamBridgePort)/track"
        environment["OPENCLAW_TRACK_ONLY_GROUPS"] = environment["OPENCLAW_TRACK_ONLY_GROUPS"] ?? "1"
        environment["OPENCLAW_TRACK_AUTO_LINKS"] = environment["OPENCLAW_TRACK_AUTO_LINKS"] ?? "1"
        environment["BROWSER"] = environment["BROWSER"] ?? "echo"
        return environment
    }

    private static func makeSettingsSnapshot(environment: [String: String]? = nil) -> OpenClawSettingsSnapshot {
        let controller = OpenClawSettingsReader(environment: environment)
        return controller.snapshot()
    }

    private var gatewayPort: String {
        configuredGatewayPort(from: ProcessInfo.processInfo.environment)
    }

    private func configuredGatewayPort(from environment: [String: String]) -> String {
        if let port = normalizedPort(environment["OPENCLAW_GATEWAY_PORT"]) {
            return port
        }
        if let port = configuredGatewayPortFromOpenClawJSON() {
            return port
        }
        return fallbackGatewayPort
    }

    private func configuredGatewayPortFromOpenClawJSON() -> String? {
        let configURL = configDirectory.appendingPathComponent("openclaw.json")
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gateway = object["gateway"] as? [String: Any] else {
            return nil
        }

        if let stringPort = gateway["port"] as? String {
            return normalizedPort(stringPort)
        }
        if let numericPort = gateway["port"] as? NSNumber {
            return normalizedPort(numericPort.stringValue)
        }
        return nil
    }

    private func normalizedPort(_ rawPort: String?) -> String? {
        guard let rawPort else {
            return nil
        }
        let trimmed = rawPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed), (1...65535).contains(port) else {
            return nil
        }
        return String(port)
    }

    private func isEnabled(_ rawValue: String?) -> Bool {
        guard let rawValue else {
            return false
        }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private func mergeEnvFile(_ url: URL, into environment: inout [String: String]) {
        guard let contents = try? String(contentsOf: url) else {
            return
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                continue
            }

            var value = String(line[line.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            environment[key] = value
        }
    }

    private func launchProcess(
        name: String,
        arguments: [String],
        environment: [String: String],
        updateRunningStateOnExit: Bool = true
    ) throws -> Process {
        let process = Process()
        process.executableURL = nodeURL
        process.arguments = arguments
        process.currentDirectoryURL = repositoryDirectory
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            Task { @MainActor in
                self?.appendLog(text, prefix: name)
            }
        }

        process.terminationHandler = { [weak self, weak process] finishedProcess in
            Task { @MainActor in
                self?.appendLog("\(name) exited with code \(finishedProcess.terminationStatus).")
                if updateRunningStateOnExit && process === self?.gatewayProcess {
                    self?.isRunning = false
                    self?.statusText = "Stopped"
                } else if process === self?.streamBridgeProcess {
                    self?.streamBridgeStatus = "stopped"
                    if self?.gatewayProcess?.isRunning == true {
                        self?.statusText = "Gateway running, stream bridge stopped"
                    }
                }
            }
        }

        try process.run()
        appendLog("Launched \(name) pid=\(process.processIdentifier).")
        return process
    }

    private func terminate(process: Process?, name: String) {
        guard let process, process.isRunning else {
            return
        }
        appendLog("Stopping \(name) pid=\(process.processIdentifier).")
        process.terminate()
    }

    private func scheduleHealthChecks() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            while !Task.isCancelled {
                await self?.refreshHealth()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func waitForGatewayReady(timeoutSeconds: Int = 15) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let status = await checkHealth(url: URL(string: "http://\(gatewayHost):\(gatewayPort)/healthz")!)
            gatewayStatus = status
            if status == "healthy" {
                if streamBridgeStatus == "not checked" {
                    streamBridgeStatus = "unknown"
                }
                return
            }
            try await Task.sleep(for: .milliseconds(400))
        }
        throw OpenClawLocalControllerError.gatewayUnavailable("OpenClaw gateway did not become healthy at http://\(gatewayHost):\(gatewayPort)/healthz")
    }

    private func runAgentTurn(
        message: String,
        sessionID: String,
        environment: [String: String]? = nil
    ) async throws -> OpenClawAgentTurnResponse {
        let result = try await runProcess(
            arguments: [
                repositoryDirectory.appendingPathComponent("dist/index.js").path,
                "agent",
                "--local",
                "--session-id",
                sessionID,
                "--message",
                message,
                "--json"
            ],
            environment: environment ?? (try openClawEnvironment())
        )

        guard result.exitCode == 0 else {
            throw OpenClawLocalControllerError.agentFailed(
                result.stderr.isEmpty ? "OpenClaw agent exited with code \(result.exitCode)." : result.stderr
            )
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stdout.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("OpenClaw agent returned no output.")
        }

        if let decoded = try? decodeAgentResponse(from: stdout) {
            return decoded
        }

        if let recovered = try recoverJSONObject(from: stdout),
           let decoded = try? decodeAgentResponse(from: recovered) {
            return decoded
        }

        throw OpenClawLocalControllerError.agentFailed("Could not parse OpenClaw JSON response.")
    }

    private func prepareTestDirectories(configDirectory: URL, workspaceDirectory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: configDirectory.appendingPathComponent("canvas", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: configDirectory.appendingPathComponent("cron", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func runProcess(arguments: [String], environment: [String: String]) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = nodeURL
            process.arguments = arguments
            process.currentDirectoryURL = repositoryDirectory
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let buffer = ProcessOutputBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    buffer.appendStdout(data)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    buffer.appendStderr(data)
                }
            }

            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { finished in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let snapshot = buffer.snapshot()
                let output = ProcessOutput(
                    stdout: snapshot.stdout,
                    stderr: snapshot.stderr,
                    exitCode: finished.terminationStatus
                )
                continuation.resume(returning: output)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func decodeAgentResponse(from text: String) throws -> OpenClawAgentTurnResponse {
        guard let data = text.data(using: .utf8) else {
            throw OpenClawLocalControllerError.agentFailed("OpenClaw response was not valid UTF-8.")
        }
        return try JSONDecoder().decode(OpenClawAgentTurnResponse.self, from: data)
    }

    private func latestAssistantReplyFromSession() -> String? {
        let sessionURL = configDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(chatSessionID).jsonl")

        guard let contents = try? String(contentsOf: sessionURL) else {
            appendLog("No OpenClaw session transcript found at \(sessionURL.path).")
            return nil
        }

        for line in contents.components(separatedBy: .newlines).reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "message",
                  let message = object["message"] as? [String: Any],
                  message["role"] as? String == "assistant" else {
                continue
            }

            let contentText = assistantContentText(from: message)
            if !contentText.isEmpty {
                appendLog("Recovered OpenClaw reply from session transcript.")
                return contentText
            }

            if let errorMessage = message["errorMessage"] as? String,
               !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        appendLog("OpenClaw session transcript did not contain an assistant reply.")
        return nil
    }

    private func publishOnlyFansPostFromChatCommand(_ message: String) async throws -> String {
        guard let postText = onlyFansPostText(from: message) else {
            return [
                "Я понял команду публикации в OnlyFans, но не нашел текст поста.",
                "Напиши так: `опубликуй пост в OnlyFans: текст поста`.",
                "Если хочешь опубликовать уже написанный пост, сначала попроси меня написать текст, потом отправь `опубликуй этот пост в OnlyFans`."
            ].joined(separator: "\n")
        }

        let trimmedPostText = postText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPostText.isEmpty else {
            return "Я понял команду публикации в OnlyFans, но текст поста пустой. Добавь текст после двоеточия."
        }

        try await onlyFansPoster.publishPost(text: trimmedPostText)
        appendLog("Published OnlyFans post from explicit chat command. characters=\(trimmedPostText.count)")
        return "Опубликовал пост в OnlyFans."
    }

    private func isExplicitOnlyFansPublishRequest(_ message: String) -> Bool {
        let normalized = normalizedCommandText(message)
        let mentionsOnlyFans = [
            "onlyfans",
            "only fans",
            "онлифанс",
            "онли фанс",
            "онли фан",
            "он ли фанс",
            "он ли фан"
        ].contains { normalized.contains($0) }

        let asksToPublish = [
            "опублику",
            "запост",
            "запубли",
            "вылож",
            "размест",
            "отправ",
            "публику",
            "publish",
            "post "
        ].contains { normalized.contains($0) }

        return mentionsOnlyFans && asksToPublish
    }

    private func onlyFansPostText(from message: String) -> String? {
        if let inlineText = inlineOnlyFansPostText(from: message) {
            return inlineText
        }

        if normalizedCommandText(message).contains("этот пост") || normalizedCommandText(message).contains("предыдущии пост") {
            return nil
        }

        return nil
    }

    private func inlineOnlyFansPostText(from message: String) -> String? {
        let separators = [":", ":\n", "\n\n"]
        for separator in separators {
            guard let range = message.range(of: separator) else {
                continue
            }
            let candidate = String(message[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isPublishablePostText(candidate) {
                return candidate
            }
        }

        if let textAfterOnlyFans = textAfterOnlyFansMention(in: message),
           isPublishablePostText(textAfterOnlyFans) {
            return textAfterOnlyFans
        }

        let markerCandidates = [
            "текст поста",
            "пост:",
            "post:"
        ]
        let lowercasedMessage = message.lowercased()
        for marker in markerCandidates {
            guard let range = lowercasedMessage.range(of: marker) else {
                continue
            }
            let candidate = String(message[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":—-")))
            if isPublishablePostText(candidate) {
                return candidate
            }
        }

        return nil
    }

    private func textAfterOnlyFansMention(in message: String) -> String? {
        let normalizedMessage = normalizedCommandText(message)
        let markers = [
            "onlyfans",
            "only fans",
            "онлифанс",
            "онли фанс",
            "онли фан",
            "он ли фанс",
            "он ли фан"
        ]

        for marker in markers {
            guard let range = normalizedMessage.range(of: marker) else {
                continue
            }

            let candidateStartOffset = normalizedMessage.distance(from: normalizedMessage.startIndex, to: range.upperBound)
            guard candidateStartOffset <= message.count,
                  let candidateStart = message.index(message.startIndex, offsetBy: candidateStartOffset, limitedBy: message.endIndex) else {
                continue
            }

            let candidate = String(message[candidateStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":—-.,;")))
            if isPublishablePostText(candidate) {
                return candidate
            }
        }

        return nil
    }

    private func isPublishablePostText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
    }

    private func normalizedCommandText(_ text: String) -> String {
        text
            .precomposedStringWithCanonicalMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "й", with: "и")
    }

    private func assistantContentText(from message: [String: Any]) -> String {
        guard let content = message["content"] as? [[String: Any]] else {
            return ""
        }

        return content.compactMap { entry -> String? in
            guard entry["type"] as? String == "text",
                  let text = entry["text"] as? String else {
                return nil
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n\n")
    }

    private func recoverJSONObject(from text: String) throws -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    private func appendChatMessage(_ message: OpenClawChatMessage) {
        chatMessages.append(message)
        if chatMessages.count > 100 {
            chatMessages.removeFirst(chatMessages.count - 100)
        }
    }

    private nonisolated func checkHealth(url: URL) async -> String {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return "bad response"
            }
            return httpResponse.statusCode == 200 ? "healthy" : "HTTP \(httpResponse.statusCode)"
        } catch {
            return "offline"
        }
    }

    private func appendLog(_ text: String, prefix: String? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }
            let label = prefix.map { "[\($0)] " } ?? ""
            logLines.append("[\(timestamp)] \(label)\(redacted(line))")
        }
        if logLines.count > 180 {
            logLines.removeFirst(logLines.count - 180)
        }
    }

    private func redacted(_ line: String) -> String {
        var output = line
        output = output.replacingOccurrences(
            of: #"rtmps?://[^\s"']+"#,
            with: "[redacted-url]",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?i)(api[_-]?key|token|secret|cookie|authorization)=([^,\s"']+)"#,
            with: "$1=[redacted]",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?i)(api[_-]?key|token|secret|cookie|authorization)["']?\s*:\s*["'][^"']+["']"#,
            with: "$1: \"[redacted]\"",
            options: .regularExpression
        )
        return output
    }
}

struct OpenClawSettingsSnapshot: Equatable {
    let runtimeRows: [OpenClawSettingsRow]
    let permissionRows: [OpenClawSettingsRow]
    let environmentRows: [OpenClawSettingsRow]
    let toolRows: [OpenClawSettingsRow]
    let environmentEntries: [OpenClawEditableSetting]
    let jsonEntries: [OpenClawEditableSetting]
    let workspaceFiles: [OpenClawWorkspaceFile]
}

struct OpenClawSettingsRow: Identifiable, Equatable {
    let id: String
    let name: String
    let value: String
}

struct OpenClawEditableSetting: Identifiable, Equatable {
    enum Source: String, Equatable {
        case environment
        case json
    }

    enum ValueKind: String, Equatable {
        case string
        case bool
        case int
        case double
        case array
        case object
        case null
    }

    let id: String
    let key: String
    let source: Source
    let kind: ValueKind
    let isSecret: Bool
    var value: String

    init(key: String, source: Source, kind: ValueKind, isSecret: Bool, value: String) {
        self.id = "\(source.rawValue):\(key)"
        self.key = key
        self.source = source
        self.kind = kind
        self.isSecret = isSecret
        self.value = value
    }
}

struct OpenClawWorkspaceFile: Identifiable, Equatable {
    let id: String
    let relativePath: String
    var contents: String

    init(relativePath: String, contents: String) {
        self.id = relativePath
        self.relativePath = relativePath
        self.contents = contents
    }
}

enum OpenClawSettingsApplyError: LocalizedError {
    case invalidJSONValue(String)
    case invalidJSONObject

    var errorDescription: String? {
        switch self {
        case let .invalidJSONValue(key):
            return "Invalid JSON value for \(key)."
        case .invalidJSONObject:
            return "openclaw.json must contain a JSON object."
        }
    }
}

struct OpenClawSettingsReader {
    private let repositoryDirectory = resolveOpenClawRepositoryDirectory()
    private let configDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".openclaw", isDirectory: true)
    private let workspaceDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".openclaw", isDirectory: true)
        .appendingPathComponent("workspace", isDirectory: true)
    private let nodeURL = URL(filePath: "/opt/homebrew/bin/node")
    private let gatewayHost = "127.0.0.1"
    private let fallbackGatewayPort = "18789"
    private let streamBridgePort = "7071"
    private let environment: [String: String]

    init(environment: [String: String]? = nil) {
        var mergedEnvironment = ProcessInfo.processInfo.environment
        Self.mergeEnvFile(repositoryDirectory.appendingPathComponent(".env"), into: &mergedEnvironment)
        Self.mergeEnvFile(configDirectory.appendingPathComponent(".env"), into: &mergedEnvironment)
        if let environment {
            mergedEnvironment.merge(environment) { _, newValue in newValue }
        }
        if (mergedEnvironment["KILOCODE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty,
           let token = resolveKiloCLIAccessToken() {
            mergedEnvironment["KILOCODE_API_KEY"] = token
        }
        self.environment = mergedEnvironment
    }

    func snapshot() -> OpenClawSettingsSnapshot {
        let gatewayPort = configuredGatewayPort(from: environment)
        let runtimeRows = [
            row("Repository", repositoryDirectory.path),
            row("Node runtime", nodeURL.path),
            row("Gateway script", repositoryDirectory.appendingPathComponent("dist/index.js").path),
            row("Gateway URL", "http://\(gatewayHost):\(gatewayPort)/"),
            row("Gateway health", "http://\(gatewayHost):\(gatewayPort)/healthz"),
            row("Stream bridge health", "http://\(gatewayHost):\(streamBridgePort)/health"),
            row("Config file", configDirectory.appendingPathComponent("openclaw.json").path),
            row("Repo .env", repositoryDirectory.appendingPathComponent(".env").path),
            row("User .env", configDirectory.appendingPathComponent(".env").path)
        ]

        let permissionRows = [
            row("Gateway bind", environment["OPENCLAW_GATEWAY_BIND"] ?? "loopback"),
            row("Config directory", configDirectory.path),
            row("Workspace directory", workspaceDirectory.path),
            row("Canvas directory", configDirectory.appendingPathComponent("canvas", isDirectory: true).path),
            row("Cron directory", configDirectory.appendingPathComponent("cron", isDirectory: true).path),
            row("Browser launch", environment["BROWSER"] ?? "echo"),
            row("Track only groups", environment["OPENCLAW_TRACK_ONLY_GROUPS"] ?? "1"),
            row("Track auto links", environment["OPENCLAW_TRACK_AUTO_LINKS"] ?? "1")
        ]

        let environmentKeys = environment.keys
            .filter { key in
                key.hasPrefix("OPENCLAW_")
                    || key.hasPrefix("OPENAI_")
                    || key.hasPrefix("ANTHROPIC_")
                    || key.hasPrefix("GOOGLE_")
                    || key.hasPrefix("GEMINI_")
                    || key.hasPrefix("OPENROUTER_")
                    || key.hasPrefix("KILOCODE_")
                    || key.hasPrefix("TELEGRAM_")
                    || key.hasPrefix("ONLYFANS_")
                    || key == "BROWSER"
            }
            .sorted()
        let environmentRows = environmentKeys.map { key in
            row(key, redacted(environment[key] ?? "", forKey: key))
        }
        let environmentEntries = environmentKeys.map { key in
            OpenClawEditableSetting(
                key: key,
                source: .environment,
                kind: .string,
                isSecret: isSecretKey(key),
                value: environment[key] ?? ""
            )
        }
        let jsonEntries = flattenJSONSettings()
        let workspaceFiles = readWorkspaceFiles()
        let toolRows = jsonEntries
            .filter { entry in
                entry.key.hasPrefix("tools.")
                    || entry.key.hasPrefix("plugins.")
                    || entry.key.hasPrefix("hooks.")
                    || entry.key.hasPrefix("skills.")
            }
            .map { entry in
                row(entry.key, entry.isSecret ? "[redacted]" : entry.value)
            }

        return OpenClawSettingsSnapshot(
            runtimeRows: runtimeRows,
            permissionRows: permissionRows,
            environmentRows: environmentRows,
            toolRows: toolRows,
            environmentEntries: environmentEntries,
            jsonEntries: jsonEntries,
            workspaceFiles: workspaceFiles
        )
    }

    static func writeEnvironment(entries: [OpenClawEditableSetting]) throws {
        let url = resolveOpenClawRepositoryDirectory().appendingPathComponent(".env")
        try writeEnvironment(entries: entries, to: url)
    }

    static func writeEnvironment(entries: [OpenClawEditableSetting], to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent(".env.bak.\(backupTimestamp())")
            try? fileManager.copyItem(at: url, to: backupURL)
        }

        let lines = entries
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(escapedEnvValue($0.value))" }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeJSON(entries: [OpenClawEditableSetting]) throws {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("openclaw.json")
        try writeJSON(entries: entries, to: url)
    }

    static func writeJSON(entries: [OpenClawEditableSetting], to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent("openclaw.json.bak.\(backupTimestamp())")
            try? fileManager.copyItem(at: url, to: backupURL)
        }

        let rootObject: NSMutableDictionary
        if let data = try? Data(contentsOf: url),
           !data.isEmpty,
           let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            rootObject = NSMutableDictionary(dictionary: object)
        } else {
            rootObject = NSMutableDictionary()
        }

        for entry in entries {
            guard let value = try jsonValue(from: entry) else {
                continue
            }
            setJSONValue(value, forPath: entry.key, in: rootObject)
        }

        guard JSONSerialization.isValidJSONObject(rootObject) else {
            throw OpenClawSettingsApplyError.invalidJSONObject
        }
        let data = try JSONSerialization.data(withJSONObject: rootObject, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
    }

    static func writeWorkspaceFiles(_ files: [OpenClawWorkspaceFile]) throws {
        let workspaceDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
        try writeWorkspaceFiles(files, to: workspaceDirectory)
    }

    static func writeWorkspaceFiles(_ files: [OpenClawWorkspaceFile], to workspaceDirectory: URL) throws {
        let fileManager = FileManager.default
        for file in files {
            guard isEditableWorkspaceFile(file.relativePath) else {
                continue
            }
            let url = workspaceDirectory.appendingPathComponent(file.relativePath)
            if fileManager.fileExists(atPath: url.path) {
                let backupURL = url.deletingLastPathComponent()
                    .appendingPathComponent("\(url.lastPathComponent).bak.\(backupTimestamp())")
                try? fileManager.copyItem(at: url, to: backupURL)
            }
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func row(_ name: String, _ value: String) -> OpenClawSettingsRow {
        OpenClawSettingsRow(id: name, name: name, value: value.isEmpty ? "Not set" : value)
    }

    private func flattenJSONSettings() -> [OpenClawEditableSetting] {
        let configURL = configDirectory.appendingPathComponent("openclaw.json")
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var entries: [OpenClawEditableSetting] = []
        flattenJSONValue(object, prefix: "", into: &entries)
        return entries.sorted { $0.key < $1.key }
    }

    private func readWorkspaceFiles() -> [OpenClawWorkspaceFile] {
        let workspaceURL = workspaceDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: workspaceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { Self.isEditableWorkspaceFile($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let contents = try? String(contentsOf: url) else {
                    return nil
                }
                return OpenClawWorkspaceFile(relativePath: url.lastPathComponent, contents: contents)
            }
    }

    private func flattenJSONValue(_ value: Any, prefix: String, into entries: inout [OpenClawEditableSetting]) {
        if let dictionary = value as? [String: Any], !dictionary.isEmpty {
            for key in dictionary.keys.sorted() {
                let nextPrefix = prefix.isEmpty ? key : "\(prefix).\(key)"
                flattenJSONValue(dictionary[key] as Any, prefix: nextPrefix, into: &entries)
            }
            return
        }

        let kind = valueKind(for: value)
        entries.append(
            OpenClawEditableSetting(
                key: prefix,
                source: .json,
                kind: kind,
                isSecret: isSecretKey(prefix),
                value: editableString(for: value, kind: kind)
            )
        )
    }

    private func valueKind(for value: Any) -> OpenClawEditableSetting.ValueKind {
        switch value {
        case is NSNull:
            return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool
            }
            return floor(number.doubleValue) == number.doubleValue ? .int : .double
        case is String:
            return .string
        case is [Any]:
            return .array
        case is [String: Any]:
            return .object
        default:
            return .string
        }
    }

    private func editableString(for value: Any, kind: OpenClawEditableSetting.ValueKind) -> String {
        switch kind {
        case .null:
            return "null"
        case .bool, .int, .double:
            return "\(value)"
        case .string:
            return value as? String ?? "\(value)"
        case .array, .object:
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                  let string = String(data: data, encoding: .utf8) else {
                return "\(value)"
            }
            return string
        }
    }

    private func configuredGatewayPort(from environment: [String: String]) -> String {
        if let port = normalizedPort(environment["OPENCLAW_GATEWAY_PORT"]) {
            return port
        }
        if let port = configuredGatewayPortFromOpenClawJSON() {
            return port
        }
        return fallbackGatewayPort
    }

    private func configuredGatewayPortFromOpenClawJSON() -> String? {
        let configURL = configDirectory.appendingPathComponent("openclaw.json")
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gateway = object["gateway"] as? [String: Any] else {
            return nil
        }

        if let stringPort = gateway["port"] as? String {
            return normalizedPort(stringPort)
        }
        if let numericPort = gateway["port"] as? NSNumber {
            return normalizedPort(numericPort.stringValue)
        }
        return nil
    }

    private func normalizedPort(_ rawPort: String?) -> String? {
        guard let rawPort else {
            return nil
        }
        let trimmed = rawPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed), (1...65535).contains(port) else {
            return nil
        }
        return String(port)
    }

    private static func mergeEnvFile(_ url: URL, into environment: inout [String: String]) {
        guard let contents = try? String(contentsOf: url) else {
            return
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                continue
            }

            var value = String(line[line.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            environment[key] = value
        }
    }

    private func applyKiloCLIAuthFallback(to environment: inout [String: String]) {
        guard let token = resolveKiloCLIAccessToken() else {
            return
        }
        let current = environment["KILOCODE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard current.isEmpty else {
            return
        }
        environment["KILOCODE_API_KEY"] = token
    }

    private func redacted(_ value: String, forKey key: String) -> String {
        guard !value.isEmpty else {
            return "Not set"
        }
        if isSecretKey(key) {
            return "[redacted]"
        }
        if value.count > 80 {
            return String(value.prefix(77)) + "..."
        }
        return value
    }

    private func isSecretKey(_ key: String) -> Bool {
        key.range(of: #"(?i)(token|secret|key|cookie|authorization|password|apiKey|api_key)"#, options: .regularExpression) != nil
    }

    private static func isSecretKey(_ key: String) -> Bool {
        key.range(of: #"(?i)(token|secret|key|cookie|authorization|password|apiKey|api_key)"#, options: .regularExpression) != nil
    }

    private static func escapedEnvValue(_ value: String) -> String {
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
           !value.contains("#"),
           !value.contains("\""),
           !value.contains("'") {
            return value
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func jsonValue(from entry: OpenClawEditableSetting) throws -> Any? {
        let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch entry.kind {
        case .string:
            return entry.value
        case .bool:
            guard !trimmed.isEmpty else {
                return nil
            }
            if ["true", "1", "yes"].contains(trimmed.lowercased()) {
                return true
            }
            if ["false", "0", "no"].contains(trimmed.lowercased()) {
                return false
            }
            return nil
        case .int:
            guard !trimmed.isEmpty else {
                return nil
            }
            guard let value = Int(trimmed) else {
                return nil
            }
            return value
        case .double:
            guard !trimmed.isEmpty else {
                return nil
            }
            guard let value = Double(trimmed) else {
                return nil
            }
            return value
        case .null:
            return NSNull()
        case .array, .object:
            guard !trimmed.isEmpty else {
                return nil
            }
            guard let data = trimmed.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            return value
        }
    }

    private static func setJSONValue(_ value: Any, forPath path: String, in root: NSMutableDictionary) {
        let components = path.split(separator: ".").map(String.init)
        guard let last = components.last else {
            return
        }
        var current = root
        for component in components.dropLast() {
            if let existing = current[component] as? NSMutableDictionary {
                current = existing
            } else if let existing = current[component] as? [String: Any] {
                let dictionary = NSMutableDictionary(dictionary: existing)
                current[component] = dictionary
                current = dictionary
            } else {
                let dictionary = NSMutableDictionary()
                current[component] = dictionary
                current = dictionary
            }
        }
        current[last] = value
    }

    private static func isEditableWorkspaceFile(_ relativePath: String) -> Bool {
        guard !relativePath.contains("/"),
              relativePath.hasSuffix(".md") || relativePath.hasSuffix(".txt") else {
            return false
        }
        let allowedNames: Set<String> = [
            "AGENTS.md",
            "BOOTSTRAP.md",
            "HEARTBEAT.md",
            "IDENTITY.md",
            "IDENTITY-female.md",
            "MEMORY.md",
            "SOUL.md",
            "TOOLS.md",
            "USER.md"
        ]
        return allowedNames.contains(relativePath)
            || relativePath.hasPrefix("IDENTITY")
            || relativePath.hasPrefix("SOUL")
            || relativePath.hasPrefix("AGENT")
            || relativePath.hasPrefix("TOOL")
    }
}

fileprivate func resolveKiloCLIAccessToken() -> String? {
    let fileManager = FileManager.default
    let authJSONURL = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("share", isDirectory: true)
        .appendingPathComponent("kilo", isDirectory: true)
        .appendingPathComponent("auth.json")
    if let token = readKiloAuthJSONAccessToken(from: authJSONURL) {
        return token
    }

    let databaseURL = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent(".local", isDirectory: true)
        .appendingPathComponent("share", isDirectory: true)
        .appendingPathComponent("kilo", isDirectory: true)
        .appendingPathComponent("kilo.db")

    guard fileManager.fileExists(atPath: databaseURL.path) else {
        return nil
    }

    let activeAccountQuery = """
    SELECT access_token
    FROM account
    WHERE id = (
      SELECT active_account_id
      FROM account_state
      WHERE active_account_id IS NOT NULL
      LIMIT 1
    )
    LIMIT 1;
    """
    if let token = readSQLiteValue(databaseURL: databaseURL, query: activeAccountQuery) {
        return token
    }

    let fallbackQuery = """
    SELECT access_token
    FROM account
    ORDER BY time_updated DESC
    LIMIT 1;
    """
    return readSQLiteValue(databaseURL: databaseURL, query: fallbackQuery)
}

fileprivate func readKiloAuthJSONAccessToken(from url: URL) -> String? {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    if let access = object["kilo"] as? [String: Any],
       let token = access["access"] as? String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    if let token = object["access"] as? String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    return nil
}

fileprivate func readSQLiteValue(databaseURL: URL, query: String) -> String? {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/sqlite3")
    process.arguments = [databaseURL.path, query]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return output.isEmpty ? nil : output
}

private func resolveOpenClawRepositoryDirectory() -> URL {
    let fileManager = FileManager.default
    let env = ProcessInfo.processInfo.environment

    if let override = env["GRACULA_OPENCLAW_REPOSITORY_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        return URL(filePath: override, directoryHint: .isDirectory)
    }

    let currentDirectory = URL(filePath: fileManager.currentDirectoryPath, directoryHint: .isDirectory)
    let relativeCandidates = [
        currentDirectory
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("openclaw", isDirectory: true)
            .standardizedFileURL,
        currentDirectory
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("Vendor", isDirectory: true)
            .appendingPathComponent("openclaw", isDirectory: true)
            .standardizedFileURL,
    ]
    let absoluteCandidates = [
        URL(filePath: "/Users/jazzblood/Documents/Gracula/openclaw", directoryHint: .isDirectory),
        URL(filePath: "/Users/jazzblood/Documents/Gracula/Vendor/openclaw", directoryHint: .isDirectory),
    ]

    for candidate in relativeCandidates + absoluteCandidates {
        if fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
    }

    return absoluteCandidates.first ?? currentDirectory
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    func appendStdout(_ data: Data) {
        lock.lock()
        stdoutData.append(data)
        lock.unlock()
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        stderrData.append(data)
        lock.unlock()
    }

    func snapshot() -> (stdout: String, stderr: String) {
        lock.lock()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        lock.unlock()
        return (stdout, stderr)
    }
}

enum OpenClawLocalControllerError: LocalizedError {
    case missingRuntime(String)
    case gatewayUnavailable(String)
    case agentFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingRuntime(message):
            return message
        case let .gatewayUnavailable(message):
            return message
        case let .agentFailed(message):
            return message
        }
    }
}

struct OpenClawChatMessage: Identifiable, Equatable {
    enum Role: String {
        case system
        case user
        case assistant
        case error
    }

    let id = UUID()
    let role: Role
    let text: String
    let timestamp = Date()

    static func system(_ text: String) -> OpenClawChatMessage {
        OpenClawChatMessage(role: .system, text: text)
    }

    static func user(_ text: String) -> OpenClawChatMessage {
        OpenClawChatMessage(role: .user, text: text)
    }

    static func assistant(_ text: String) -> OpenClawChatMessage {
        OpenClawChatMessage(role: .assistant, text: text)
    }

    static func error(_ text: String) -> OpenClawChatMessage {
        OpenClawChatMessage(role: .error, text: text)
    }
}

private struct OpenClawAgentTurnResponse: Decodable {
    let runId: String?
    let status: String?
    let summary: String?
    let payloads: [OpenClawAgentTurnPayload]?
    let result: OpenClawAgentTurnResult?
}

private struct OpenClawAgentTurnResult: Decodable {
    let payloads: [OpenClawAgentTurnPayload]?
}

private struct OpenClawAgentTurnPayload: Decodable {
    let text: String?
    let mediaUrl: String?
    let mediaUrls: [String]?
}

private struct ProcessOutput {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private extension OpenClawAgentTurnResponse {
    var replyText: String {
        let allPayloads = (result?.payloads ?? []) + (payloads ?? [])
        let payloadText = allPayloads.compactMap({ $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .joined(separator: "\n\n")
        if !payloadText.isEmpty {
            return payloadText
        }
        return summary ?? ""
    }
}
