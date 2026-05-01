import AppKit
import Automation
import Darwin
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

    private let nodeURL = resolveNodeExecutableURL()
    private let gatewayHost = "127.0.0.1"
    private let fallbackGatewayPort = "18789"
    private let streamBridgePort = "7071"
    private let agentTurnTimeoutSeconds: TimeInterval = 180
    private let directModelTimeoutSeconds: TimeInterval = 120
    private let directMLXTimeoutSeconds: TimeInterval = 240
    private let directVoiceTinyMaxTokens = 64
    private let directVoiceShortMaxTokens = 256
    private let directVoiceNormalMaxTokens = 700
    private let directMemoryFileLimit = 2
    private let mlxRuntimeDirectory = resolveMLXRuntimeDirectory()
    private let mlxModelsDirectory = resolveMLXModelsDirectory()
    private let onlyFansPoster = WorkspaceOpeningClient()
    private var chatSessionID = "gracula-local-chat"
    private var gatewayProcess: Process?
    private var streamBridgeProcess: Process?
    private var healthTask: Task<Void, Never>?
    private var directModelPrewarmTask: Task<Void, Never>?
    private var consecutiveHealthFailures = 0
    private var startupTask: Task<Void, Never>?
    private var directPersonaContextCache: String?
    private var directCompactPersonaContextCache: String?

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
        directModelPrewarmTask?.cancel()
        gatewayProcess?.terminate()
        streamBridgeProcess?.terminate()
        healthTask?.cancel()
    }

    func start() {
        guard !isRunning else {
            appendLog("OpenClaw is already running.")
            return
        }
        guard startupTask == nil else {
            appendLog("OpenClaw is already starting.")
            return
        }

        startupTask = Task { [weak self] in
            await self?.startWorkflow()
        }
    }

    private func startWorkflow() async {
        defer { startupTask = nil }

        do {
            try validateRuntime()
            try prepareDirectories()
            let environment = try openClawEnvironment()
            settingsSnapshot = Self.makeSettingsSnapshot(environment: environment)
            let primaryModelRef = currentPrimaryModelRef()
            if shouldUseDirectCompletion(for: primaryModelRef) {
                try validateDirectModelRuntime(for: primaryModelRef)
                gatewayProcess = nil
                streamBridgeProcess = nil
                isRunning = true
                statusText = "Direct model ready"
                gatewayStatus = "direct mode"
                streamBridgeStatus = "disabled"
                appendLog("Direct model mode active; skipping OpenClaw gateway startup.")
                appendLog("Selected model uses direct completion: \(primaryModelRef)")
                scheduleDirectModelPrewarm(modelRef: primaryModelRef)
                return
            }

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
                    let existingGatewayURL = URL(
                        string: "http://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)/healthz"
                    )!
                    let existingGatewayStatus = await checkHealth(url: existingGatewayURL)
                    guard existingGatewayStatus == "healthy" else {
                        gatewayProcess = nil
                        isRunning = false
                        gatewayStatus = existingGatewayStatus
                        throw OpenClawLocalControllerError.gatewayUnavailable(
                            "An existing OpenClaw gateway is occupying http://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)/, but /healthz is \(existingGatewayStatus). Stop that stale process and start OpenClaw again."
                        )
                    }

                    gatewayProcess = nil
                    isRunning = true
                    statusText = "Using existing OpenClaw gateway..."
                    gatewayStatus = "healthy"
                    appendLog("OpenClaw gateway is already running outside the app and passed health check; attaching to http://\(gatewayHost):\(environment["OPENCLAW_GATEWAY_PORT"] ?? gatewayPort)/")
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
        directModelPrewarmTask?.cancel()
        directModelPrewarmTask = nil
        healthTask?.cancel()
        healthTask = nil
        startupTask?.cancel()
        startupTask = nil
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
        updateHealthFailureCount(for: gatewayStatus)
        if streamBridgeProcess?.isRunning == true {
            streamBridgeStatus = await checkHealth(url: URL(string: "http://\(gatewayHost):\(streamBridgePort)/health")!)
        } else if streamBridgeStatus != "disabled" {
            streamBridgeStatus = streamBridgeProcess == nil ? "disabled" : "stopped"
        }
        statusText = isRunning ? "Running" : "Stopped"
    }

    private func updateHealthFailureCount(for status: String) {
        if status == "healthy" {
            consecutiveHealthFailures = 0
        } else {
            consecutiveHealthFailures = min(consecutiveHealthFailures + 1, 8)
        }
    }

    func reportError(_ message: String) {
        appendChatMessage(.error(message))
    }

    func reloadSettings() {
        settingsSnapshot = Self.makeSettingsSnapshot()
        directPersonaContextCache = nil
        directCompactPersonaContextCache = nil
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
            let primaryModelRef = currentPrimaryModelRef(in: jsonEntries)
            let reply: String
            let metrics: DirectModelMetrics?
            if shouldUseDirectModelSmokeTest(for: primaryModelRef) {
                appendLog("Selected model uses a tool-free probe; running direct completion smoke test.")
                let result = try await runDirectModelSmokeTest(
                    modelRef: primaryModelRef,
                    environment: environment
                )
                reply = result.text
                metrics = result.metrics
            } else {
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
                let agentReply = response.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !agentReply.isEmpty else {
                    throw OpenClawLocalControllerError.agentFailed("Selected model returned an empty reply.")
                }
                if agentReply.hasPrefix("LLM error:") {
                    throw OpenClawLocalControllerError.agentFailed(agentReply)
                }
                reply = agentReply
                metrics = nil
            }
            let metricSummary = metrics?.statusSummary
            settingsStatusText = metricSummary.map { "Model test passed. \($0)" } ?? "Model test passed."
            let transcriptSummary = metricSummary.map { "Model test passed: \(reply) [\($0)]" } ?? "Model test passed: \(reply)"
            appendChatMessage(.system(transcriptSummary))
            appendLog("Selected model test passed with reply: \(reply)")
            if let metrics {
                appendLog("Selected model performance: \(metrics.logSummary)")
            }
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

    private func scheduleDirectModelPrewarm(modelRef: String) {
        directModelPrewarmTask?.cancel()
        directModelPrewarmTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.prewarmDirectModelIfNeeded(modelRef: modelRef)
        }
    }

    private func prewarmDirectModelIfNeeded(modelRef: String) async {
        let trimmedRef = modelRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRef.isEmpty, shouldUseDirectCompletion(for: trimmedRef) else {
            return
        }

        appendLog("Prewarming selected direct model on launch: \(trimmedRef)")
        let startedAt = PerformanceLog.checkpoint()
        do {
            let result = try await runDirectModelSmokeTest(
                modelRef: trimmedRef,
                environment: try openClawEnvironment()
            )
            let metricSummary = result.metrics?.statusSummary ?? "no metrics"
            appendLog("[latency] Direct model prewarm completed in \(PerformanceLog.elapsedDescription(since: startedAt)); model=\(trimmedRef); \(metricSummary)")
        } catch is CancellationError {
            appendLog("Direct model prewarm cancelled.")
        } catch {
            appendLog("Direct model prewarm failed: \(error.localizedDescription)")
        }
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
        let turnStartedAt = PerformanceLog.checkpoint()
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return nil
        }

        do {
            let primaryModelRef = currentPrimaryModelRef()
            if !shouldUseDirectCompletion(for: primaryModelRef),
               shouldResetChatSessionBeforeSending(message) {
                appendLog("Resetting stale chat session before send.")
                resetChat()
            }
            isSendingChat = true
            chatStatusText = "Sending to OpenClaw..."
            appendChatMessage(.user(message))
            appendLog("[latency] Chat turn started; inputCharacters=\(message.count)")

            if isExplicitOnlyFansPublishRequest(message) {
                let reply = try await publishOnlyFansPostFromChatCommand(message)
                appendChatMessage(.assistant(reply))
                appendLog("[latency] Assistant reply appended to UI after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(reply.count)")
                chatStatusText = "OnlyFans post published."
                isSendingChat = false
                return reply
            }
            if shouldUseDirectCompletion(for: primaryModelRef) {
                appendLog("Selected model uses a tool-free chat path; running direct completion.")
                appendLog("[latency] Direct model request starting; model=\(primaryModelRef)")
                let assistantMessageID = appendChatMessage(.assistant("…"))
                chatStatusText = "Waiting for local model..."
                let result = try await runDirectModelChat(
                    modelRef: primaryModelRef,
                    prompt: directChatPrompt(for: message),
                    maxTokens: directMaxTokens(for: message),
                    assistantMessageID: assistantMessageID
                )
                let reply = result.text
                guard !reply.isEmpty else {
                    throw OpenClawLocalControllerError.agentFailed("Selected model returned an empty reply.")
                }
                updateChatMessage(id: assistantMessageID, text: reply)
                appendLog("[latency] Direct model answer returned after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(reply.count)")
                appendLog("[latency] Assistant reply appended to UI after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(reply.count)")
                chatStatusText = "Reply received."
                appendLog("Direct model reply received. characters=\(reply.count)")
                if let metrics = result.metrics {
                    appendLog("Direct model performance: \(metrics.logSummary)")
                }
                isSendingChat = false
                return reply
            }

            appendLog("[latency] OpenClaw agent turn starting; session=\(chatSessionID)")
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
                appendLog("[latency] Assistant retry reply appended to UI after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(retryReply.count)")
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
            appendLog("[latency] OpenClaw agent answer returned after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(reply.count)")
            appendChatMessage(.assistant(reply))
            appendLog("[latency] Assistant reply appended to UI after \(PerformanceLog.elapsedDescription(since: turnStartedAt)); replyCharacters=\(reply.count)")
            chatStatusText = "Reply received."
            isSendingChat = false
            return reply
        } catch {
            removePendingAssistantPlaceholder()
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
            throw OpenClawLocalControllerError.missingRuntime("Node runtime not found. Install Node.js 22+ or set GRACULA_NODE_EXECUTABLE.")
        }
        try bootstrapOpenClawCheckoutIfNeeded()
        let distIndexURL = repositoryDirectory.appendingPathComponent("dist/index.js")
        if !fileManager.fileExists(atPath: distIndexURL.path) {
            appendLog("OpenClaw dist/index.js is missing; attempting to build the checkout at \(repositoryDirectory.path).")
            try buildOpenClawCheckout()
            if !fileManager.fileExists(atPath: distIndexURL.path) {
                throw OpenClawLocalControllerError.missingRuntime(
                    "OpenClaw dist/index.js not found after attempting a build. Install dependencies in \(repositoryDirectory.path) and run `pnpm build`, or point GRACULA_OPENCLAW_REPOSITORY_DIR at a built checkout."
                )
            }
        }
    }

    private func bootstrapOpenClawCheckoutIfNeeded() throws {
        let fileManager = FileManager.default
        let packageURL = repositoryDirectory.appendingPathComponent("package.json")
        if fileManager.fileExists(atPath: packageURL.path) {
            return
        }

        let parentDirectory = repositoryDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        appendLog("OpenClaw checkout not found at \(repositoryDirectory.path); cloning it now.")

        let cloneOutput = try runCommand(
            executableURL: URL(filePath: "/usr/bin/git"),
            arguments: [
                "clone",
                "--depth",
                "1",
                "https://github.com/openclaw/openclaw.git",
                repositoryDirectory.path
            ],
            currentDirectoryURL: parentDirectory,
            environment: ProcessInfo.processInfo.environment
        )

        if cloneOutput.exitCode != 0 {
            throw OpenClawLocalControllerError.missingRuntime(
                cloneOutput.stderr.isEmpty ? cloneOutput.stdout : cloneOutput.stderr
            )
        }

        if !cloneOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(cloneOutput.stdout, prefix: "git")
        }
        if !cloneOutput.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(cloneOutput.stderr, prefix: "git")
        }
    }

    private func buildOpenClawCheckout() throws {
        let fileManager = FileManager.default
        let environment = try openClawEnvironment()
        guard let command = resolvePackageManagerCommand() else {
            throw OpenClawLocalControllerError.missingRuntime(
                "Could not find pnpm or corepack to build OpenClaw automatically."
            )
        }

        appendLog("Building OpenClaw checkout with \(command.displayName).")
        let installOutput = try runCommand(
            executableURL: command.executableURL,
            arguments: command.installArguments,
            currentDirectoryURL: repositoryDirectory,
            environment: environment
        )
        if installOutput.exitCode != 0 {
            throw OpenClawLocalControllerError.missingRuntime(
                installOutput.stderr.isEmpty ? installOutput.stdout : installOutput.stderr
            )
        }
        if !installOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(installOutput.stdout, prefix: command.displayName)
        }
        if !installOutput.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(installOutput.stderr, prefix: command.displayName)
        }

        let buildOutput = try runCommand(
            executableURL: command.executableURL,
            arguments: command.buildArguments,
            currentDirectoryURL: repositoryDirectory,
            environment: environment
        )
        if buildOutput.exitCode != 0 {
            throw OpenClawLocalControllerError.missingRuntime(
                buildOutput.stderr.isEmpty ? buildOutput.stdout : buildOutput.stderr
            )
        }
        if !buildOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(buildOutput.stdout, prefix: command.displayName)
        }
        if !buildOutput.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(buildOutput.stderr, prefix: command.displayName)
        }

        guard fileManager.fileExists(atPath: repositoryDirectory.appendingPathComponent("dist/index.js").path) else {
            throw OpenClawLocalControllerError.missingRuntime(
                "OpenClaw build finished but dist/index.js is still missing."
            )
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
        try launchObservedProcess(
            name: name,
            executableURL: nodeURL,
            currentDirectoryURL: repositoryDirectory,
            arguments: arguments,
            environment: environment,
            updateRunningStateOnExit: updateRunningStateOnExit
        )
    }

    private func launchObservedProcess(
        name: String,
        executableURL: URL,
        currentDirectoryURL: URL,
        arguments: [String],
        environment: [String: String],
        updateRunningStateOnExit: Bool = true
    ) throws -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
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
                    let healthURL = URL(string: "http://\(self?.gatewayHost ?? "127.0.0.1"):\(self?.gatewayPort ?? "18789")/healthz")!
                    let status = await self?.checkHealth(url: healthURL) ?? "offline"
                    if status == "healthy" {
                        self?.gatewayProcess = nil
                        self?.isRunning = true
                        self?.gatewayStatus = "healthy"
                        self?.statusText = "Using existing OpenClaw gateway..."
                        self?.appendLog("Gateway process handed off to an existing healthy gateway.")
                    } else {
                        self?.isRunning = false
                        self?.gatewayStatus = status
                        self?.statusText = "Stopped"
                    }
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
        appendLog("Gateway health check scheduled once after startup.")
        healthTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                await self?.refreshHealth()
            }
        }
    }

    private func waitForGatewayReady(timeoutSeconds: Int = 15) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let status = await checkHealth(url: URL(string: "http://\(gatewayHost):\(gatewayPort)/healthz")!)
            gatewayStatus = status
            updateHealthFailureCount(for: status)
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
            environment: environment ?? (try openClawEnvironment()),
            timeoutSeconds: agentTurnTimeoutSeconds
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

    private func runDirectModelSmokeTest(
        modelRef: String,
        environment: [String: String]
    ) async throws -> DirectModelChatResult {
        return try await runDirectModelChat(
            modelRef: modelRef,
            prompt: "Reply with exactly: model test ok",
            environment: environment,
            maxTokens: 32
        )
    }

    private func runDirectModelChat(
        modelRef: String,
        prompt: String,
        environment: [String: String]? = nil,
        maxTokens: Int = 256,
        assistantMessageID: UUID? = nil
    ) async throws -> DirectModelChatResult {
        let startedAt = PerformanceLog.checkpoint()
        let trimmedRef = modelRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRef.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("Selected model is not set.")
        }

        let provider = trimmedRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard provider.count == 2 else {
            throw OpenClawLocalControllerError.agentFailed(
                "Selected model ref must use provider/model format."
            )
        }

        let providerName = String(provider[0]).lowercased()
        let providerModelID = String(provider[1])
        let effectiveMaxTokens = directModelMaxTokens(for: trimmedRef, requestedMaxTokens: maxTokens)
        if providerName == "ollama" {
            return try await runDirectOllamaChat(
                modelID: providerModelID,
                prompt: prompt,
                maxTokens: effectiveMaxTokens,
                startedAt: startedAt,
                assistantMessageID: assistantMessageID
            )
        }
        if providerName == "mlx" {
            return try await runDirectMLXChat(
                modelID: providerModelID,
                prompt: prompt,
                maxTokens: effectiveMaxTokens,
                startedAt: startedAt
            )
        }
        let activeEnvironment: [String: String]
        if let environment {
            activeEnvironment = environment
        } else {
            activeEnvironment = try openClawEnvironment()
        }
        let apiKey = directModelSmokeTestAPIKey(from: activeEnvironment, modelRef: trimmedRef)
        guard !apiKey.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed(
                "No API key is available for the selected model."
            )
        }

        let modelId = trimmedRef
        appendLog(
            "[latency] Direct model process prepared; provider=\(providerName), model=\(modelId), promptCharacters=\(prompt.count), maxTokens=\(effectiveMaxTokens), reasoning=off"
        )
        let promptFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gracula-direct-prompt-\(UUID().uuidString).txt")
        try prompt.write(to: promptFileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: promptFileURL)
        }
        let script = """
        const startedAt = Date.now();
        const { completeSimple, getModel } = await import("@mariozechner/pi-ai");
        const { readFileSync } = await import("node:fs");
        const importedAt = Date.now();

        const provider = process.env.GRACULA_MODEL_PROVIDER ?? "";
        const modelId = process.env.GRACULA_MODEL_ID ?? "";
        const apiKey = process.env.GRACULA_MODEL_API_KEY ?? "";
        const promptFile = process.env.GRACULA_MODEL_PROMPT_FILE ?? "";
        const prompt = promptFile ? readFileSync(promptFile, "utf8") : (process.env.GRACULA_MODEL_PROMPT ?? "");
        const maxTokens = Number(process.env.GRACULA_MODEL_MAX_TOKENS ?? "256");
        const model = getModel(provider, modelId);
        const temperature = Number(process.env.GRACULA_MODEL_TEMPERATURE ?? "0.35");
        const options = {
          apiKey,
          maxTokens,
          temperature
        };
        const requestStartedAt = Date.now();
        const response = await completeSimple(
          model,
          {
            messages: [
              {
                role: "user",
                content: prompt,
                timestamp: Date.now()
              }
            ]
          },
          options
        );
        const responseReceivedAt = Date.now();
        const contentBlocks = Array.isArray(response?.content) ? response.content : [];
        const text = contentBlocks
          .filter((block) => block?.type === "text" && typeof block.text === "string")
          .map((block) => block.text.trim())
          .filter(Boolean)
          .join(" ")
          .trim();
        const thinkingText = contentBlocks
          .filter((block) => block?.type === "thinking" && typeof block.thinking === "string")
          .map((block) => block.thinking.trim())
          .filter(Boolean)
          .join("\\n")
          .trim();
        const fallbackText =
          (typeof response?.text === "string" ? response.text.trim() : "") ||
          (typeof response?.output_text === "string" ? response.output_text.trim() : "");
        const finalText = text || fallbackText;
        if (!finalText) {
          const contentTypes = contentBlocks.map((block) => block?.type ?? "unknown").join(",");
          throw new Error(
            `Selected model returned no visible answer. stopReason=${response?.stopReason ?? "unknown"}, contentTypes=${contentTypes || "none"}, thinkingCharacters=${thinkingText.length}`
          );
        }
        const finishedAt = Date.now();
        console.log(JSON.stringify({
          text: finalText,
          timing: {
            importMs: importedAt - startedAt,
            apiMs: responseReceivedAt - requestStartedAt,
            parseMs: finishedAt - responseReceivedAt,
            totalMs: finishedAt - startedAt
          }
        }));
        """
        var smokeEnvironment = activeEnvironment
        smokeEnvironment["GRACULA_MODEL_PROVIDER"] = providerName
        smokeEnvironment["GRACULA_MODEL_ID"] = modelId
        smokeEnvironment["GRACULA_MODEL_API_KEY"] = apiKey
        smokeEnvironment["GRACULA_MODEL_PROMPT"] = nil
        smokeEnvironment["GRACULA_MODEL_PROMPT_FILE"] = promptFileURL.path
        smokeEnvironment["GRACULA_MODEL_MAX_TOKENS"] = String(effectiveMaxTokens)
        smokeEnvironment["GRACULA_MODEL_TEMPERATURE"] = maxTokens <= 64 ? "0" : "0.35"
        smokeEnvironment["GRACULA_MODEL_REASONING"] = nil

        appendLog("[latency] Direct model process launching.")
        let result = try await runProcess(
            arguments: [
                "--input-type=module",
                "-e",
                script
            ],
            environment: smokeEnvironment,
            timeoutSeconds: directModelTimeoutSeconds
        )
        appendLog(
            "[latency] Direct model process exited in \(PerformanceLog.elapsedDescription(since: startedAt)); exitCode=\(result.exitCode), stdoutCharacters=\(result.stdout.count), stderrCharacters=\(result.stderr.count)"
        )

        guard result.exitCode == 0 else {
            throw OpenClawLocalControllerError.agentFailed(
                result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stdout.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("Selected model returned no output.")
        }

        if let decoded = try? JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any],
           let text = decoded["text"] as? String {
            if let timing = decoded["timing"] as? [String: Any] {
                let importMs = timing["importMs"] ?? "?"
                let apiMs = timing["apiMs"] ?? "?"
                let parseMs = timing["parseMs"] ?? "?"
                let totalMs = timing["totalMs"] ?? "?"
                appendLog("[latency] Direct model JS timing; importMs=\(importMs), apiMs=\(apiMs), parseMs=\(parseMs), totalMs=\(totalMs)")
            }
            let reply = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else {
                throw OpenClawLocalControllerError.agentFailed("Selected model returned an empty reply.")
            }
            appendLog("[latency] Direct model JSON decoded in \(PerformanceLog.elapsedDescription(since: startedAt)); replyCharacters=\(reply.count)")
            return DirectModelChatResult(text: reply, metrics: nil)
        }

        appendLog("[latency] Direct model raw stdout returned in \(PerformanceLog.elapsedDescription(since: startedAt)); characters=\(stdout.count)")
        return DirectModelChatResult(text: stdout, metrics: nil)
    }

    private func runDirectOllamaChat(
        modelID: String,
        prompt: String,
        maxTokens: Int,
        startedAt: UInt64,
        assistantMessageID: UUID?
    ) async throws -> DirectModelChatResult {
        let numCtx = maxTokens <= directVoiceTinyMaxTokens ? 2_048 : 4_096
        appendLog(
            "[latency] Direct Ollama request prepared; model=\(modelID), promptCharacters=\(prompt.count), maxTokens=\(maxTokens), numCtx=\(numCtx), think=false"
        )

        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            throw OpenClawLocalControllerError.agentFailed("Invalid Ollama API URL.")
        }

        let body: [String: Any] = [
            "model": modelID,
            "stream": true,
            "think": false,
            "keep_alive": "30m",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "options": [
                "num_ctx": numCtx,
                "num_predict": maxTokens,
                "temperature": maxTokens <= 64 ? 0 : 0.35,
                "top_p": 0.85,
                "repeat_penalty": 1.08
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = directModelTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let requestStartedAt = PerformanceLog.checkpoint()
        appendLog("[latency] Direct Ollama HTTP request starting.")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        appendLog("[latency] Direct Ollama HTTP response headers received in \(PerformanceLog.elapsedDescription(since: requestStartedAt))")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenClawLocalControllerError.agentFailed("Ollama returned a non-HTTP response.")
        }

        var replyBuffer = ""
        var rawLines: [String] = []
        var sawFirstToken = false
        var receivedDone = false
        var finalMetrics: DirectModelMetrics?

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            rawLines.append(line)
            guard let lineData = line.data(using: .utf8),
                  let decoded = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            if let error = decoded["error"] as? String,
               !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw OpenClawLocalControllerError.agentFailed("Ollama error: \(error)")
            }

            if let message = decoded["message"] as? [String: Any],
               let chunk = message["content"] as? String,
               !chunk.isEmpty {
                replyBuffer.append(chunk)
                if let assistantMessageID {
                    updateChatMessage(id: assistantMessageID, text: replyBuffer)
                }
                if !sawFirstToken {
                    sawFirstToken = true
                    chatStatusText = "Receiving local reply..."
                    appendLog("[latency] Direct Ollama first token received in \(PerformanceLog.elapsedDescription(since: requestStartedAt))")
                }
            }

            if let done = decoded["done"] as? Bool, done {
                finalMetrics = DirectModelMetrics(
                    providerLabel: "ollama",
                    promptTokens: decoded["prompt_eval_count"] as? Int,
                    promptTokensPerSecond: Self.tokensPerSecond(
                        tokens: decoded["prompt_eval_count"] as? Int,
                        durationNanoseconds: decoded["prompt_eval_duration"] as? NSNumber
                    ),
                    generationTokens: decoded["eval_count"] as? Int,
                    generationTokensPerSecond: Self.tokensPerSecond(
                        tokens: decoded["eval_count"] as? Int,
                        durationNanoseconds: decoded["eval_duration"] as? NSNumber
                    ),
                    peakMemoryGB: nil
                )
                receivedDone = true
                break
            }
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyText = rawLines.joined(separator: "\n")
            throw OpenClawLocalControllerError.agentFailed(
                bodyText.isEmpty ? "Ollama HTTP \(httpResponse.statusCode)." : "Ollama HTTP \(httpResponse.statusCode): \(bodyText)"
            )
        }

        let reply = replyBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("Ollama returned an empty reply.")
        }

        if !receivedDone {
            appendLog("[latency] Direct Ollama stream ended without explicit done flag.")
        }
        appendLog("[latency] Direct Ollama answer decoded after \(PerformanceLog.elapsedDescription(since: startedAt)); replyCharacters=\(reply.count)")
        return DirectModelChatResult(text: reply, metrics: finalMetrics)
    }

    private func runDirectMLXChat(
        modelID: String,
        prompt: String,
        maxTokens: Int,
        startedAt: UInt64
    ) async throws -> DirectModelChatResult {
        let pythonURL = try mlxPythonExecutableURL()
        let modelDirectory = try mlxModelDirectory(for: modelID)
        let promptFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gracula-mlx-prompt-\(UUID().uuidString).txt")
        try prompt.write(to: promptFileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: promptFileURL)
        }

        let script = """
        import json
        import os
        from mlx_lm import load, stream_generate
        from mlx_lm.sample_utils import make_sampler

        model_path = os.environ["GRACULA_MLX_MODEL_PATH"]
        prompt_file = os.environ["GRACULA_MLX_PROMPT_FILE"]
        max_tokens = int(os.environ.get("GRACULA_MLX_MAX_TOKENS", "256"))
        temperature = float(os.environ.get("GRACULA_MLX_TEMPERATURE", "0"))
        top_p = float(os.environ.get("GRACULA_MLX_TOP_P", "0"))

        with open(prompt_file, "r", encoding="utf-8") as handle:
            user_prompt = handle.read()

        model, tokenizer = load(model_path)
        if getattr(tokenizer, "chat_template", None) is not None:
            rendered_prompt = tokenizer.apply_chat_template(
                [{"role": "user", "content": user_prompt}],
                add_generation_prompt=True,
                enable_thinking=False,
            )
        else:
            rendered_prompt = user_prompt

        sampler = make_sampler(temp=temperature, top_p=top_p)
        chunks = []
        final_metrics = None
        for response in stream_generate(
            model,
            tokenizer,
            rendered_prompt,
            max_tokens=max_tokens,
            sampler=sampler,
        ):
            if response.text:
                chunks.append(response.text)
            final_metrics = {
                "prompt_tokens": response.prompt_tokens,
                "prompt_tps": response.prompt_tps,
                "generation_tokens": response.generation_tokens,
                "generation_tps": response.generation_tps,
                "peak_memory": response.peak_memory,
                "finish_reason": response.finish_reason,
            }

        text = "".join(chunks).strip()
        if not text:
            raise RuntimeError("MLX returned an empty reply.")

        print(json.dumps({"text": text, "metrics": final_metrics}, ensure_ascii=False))
        """

        var environment = ProcessInfo.processInfo.environment
        environment["GRACULA_MLX_MODEL_PATH"] = modelDirectory.path
        environment["GRACULA_MLX_PROMPT_FILE"] = promptFileURL.path
        environment["GRACULA_MLX_MAX_TOKENS"] = String(maxTokens)
        environment["GRACULA_MLX_TEMPERATURE"] = maxTokens <= 64 ? "0" : "0.35"
        environment["GRACULA_MLX_TOP_P"] = maxTokens <= 64 ? "0" : "0.85"

        appendLog(
            "[latency] Direct MLX request prepared; modelPath=\(modelDirectory.lastPathComponent), promptCharacters=\(prompt.count), maxTokens=\(maxTokens)"
        )
        let result = try await runExternalProcess(
            executableURL: pythonURL,
            arguments: ["-c", script],
            currentDirectoryURL: repositoryDirectory,
            environment: environment,
            timeoutSeconds: directMLXTimeoutSeconds
        )

        guard result.exitCode == 0 else {
            throw OpenClawLocalControllerError.agentFailed(
                result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = try? JSONDecoder().decode(DirectModelScriptResponse.self, from: Data(stdout.utf8)) else {
            throw OpenClawLocalControllerError.agentFailed("MLX returned an invalid JSON response.")
        }

        let reply = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else {
            throw OpenClawLocalControllerError.agentFailed("MLX returned an empty reply.")
        }

        let metrics = decoded.metrics.map {
            DirectModelMetrics(
                providerLabel: "mlx",
                promptTokens: $0.promptTokens,
                promptTokensPerSecond: $0.promptTokensPerSecond,
                generationTokens: $0.generationTokens,
                generationTokensPerSecond: $0.generationTokensPerSecond,
                peakMemoryGB: $0.peakMemoryGB
            )
        }
        appendLog("[latency] Direct MLX answer decoded after \(PerformanceLog.elapsedDescription(since: startedAt)); replyCharacters=\(reply.count)")
        return DirectModelChatResult(text: reply, metrics: metrics)
    }

    private func directModelSmokeTestAPIKey(from environment: [String: String], modelRef: String) -> String {
        let lowercased = modelRef.lowercased()
        if lowercased.hasPrefix("openrouter/") {
            return environment["OPENROUTER_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if lowercased.hasPrefix("google/") {
            return environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? environment["GOOGLE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
        }
        if lowercased.hasPrefix("anthropic/") {
            return environment["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if lowercased.hasPrefix("openai/") || lowercased.hasPrefix("openai-codex/") {
            return environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return ""
    }

    private func currentPrimaryModelRef(in jsonEntries: [OpenClawEditableSetting]) -> String {
        if let value = jsonEntries.first(where: { $0.key == "agents.defaults.model.primary" })?.value
            ?? jsonEntries.first(where: { $0.key == "agents.defaults.model" })?.value {
            return value
        }
        return ""
    }

    private func shouldUseDirectModelSmokeTest(for modelRef: String) -> Bool {
        let normalized = modelRef.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("ollama/")
            || normalized.hasPrefix("mlx/")
            || normalized == "google/gemini-3-flash-preview"
            || normalized == "openrouter/free"
    }

    private func shouldUseDirectCompletion(for modelRef: String) -> Bool {
        shouldUseDirectModelSmokeTest(for: modelRef)
    }

    private func directModelReasoningMode(for modelRef: String) -> String? {
        return nil
    }

    private func directModelMaxTokens(for modelRef: String, requestedMaxTokens: Int) -> Int {
        return requestedMaxTokens
    }

    private func directMaxTokens(for message: String) -> Int {
        let normalizedCount = message.trimmingCharacters(in: .whitespacesAndNewlines).count
        if normalizedCount <= 12 {
            return directVoiceTinyMaxTokens
        }
        return normalizedCount <= 160 ? directVoiceShortMaxTokens : directVoiceNormalMaxTokens
    }

    private func currentPrimaryModelRef() -> String {
        currentPrimaryModelRef(in: settingsSnapshot.jsonEntries)
    }

    private func validateDirectModelRuntime(for modelRef: String) throws {
        let normalized = modelRef.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("mlx/") {
            _ = try mlxPythonExecutableURL()
            _ = try mlxModelDirectory(for: String(modelRef.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).last ?? ""))
        }
    }

    private func mlxPythonExecutableURL() throws -> URL {
        let url = mlxRuntimeDirectory
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw OpenClawLocalControllerError.missingRuntime(
                "MLX runtime not found at \(url.path). Install it into Application Support before selecting the MLX backend."
            )
        }
        return url
    }

    private func mlxModelDirectory(for modelID: String) throws -> URL {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let directoryName: String
        switch normalized {
        case "qwen3-14b-4bit":
            directoryName = "Qwen3-14B-4bit"
        default:
            throw OpenClawLocalControllerError.missingRuntime(
                "Unsupported MLX model id: \(modelID)."
            )
        }

        let url = mlxModelsDirectory.appendingPathComponent(directoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OpenClawLocalControllerError.missingRuntime(
                "MLX model files not found at \(url.path). Download the model before selecting the MLX backend."
            )
        }
        return url
    }

    private func directChatPrompt(for message: String) -> String {
        let isTinyTurn = isTinyDirectChatTurn(message)
        let transcript = chatMessages
            .suffix(isTinyTurn ? 2 : 4)
            .filter { $0.role != .error }
            .map { message in
                "\(message.role.rawValue): \(message.text)"
            }
            .joined(separator: "\n")
        let personaContext = directPersonaContext(compact: isTinyTurn)
        let brevityRule = isTinyTurn
            ? "For very short casual inputs like hi, ok, thanks, or emojis, answer in one short sentence under 16 words."
            : "Keep voice replies compact but complete: normally 1-4 sentences, not one-word unless the user asks for it."

        return """
        Use the workspace setup below as the authoritative bot configuration.
        Follow SOUL.md, IDENTITY.md, AGENTS.md, USER.md, MEMORY.md, and TOOLS.md exactly when shaping identity, tone, behavior, and memory.
        Preserve prior conversation context. If asked who you are, answer from the workspace identity, not as a generic assistant.
        \(brevityRule)
        Start with the final visible answer immediately. Do not spend the answer budget restating or analyzing the setup.
        Do not mention prompts, files, or implementation details.

        Workspace setup:
        \(personaContext)

        Conversation:
        \(transcript)
        """
    }

    private func isTinyDirectChatTurn(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count <= 12
    }

    private func directPersonaContext(compact: Bool) -> String {
        if compact, let directCompactPersonaContextCache {
            return directCompactPersonaContextCache
        }
        if !compact, let directPersonaContextCache {
            return directPersonaContextCache
        }
        let coreFiles: [(relativePath: String, maxCharacters: Int?)] = [
            ("SOUL.md", compact ? 700 : 2_500),
            ("IDENTITY.md", compact ? 500 : 1_200),
            ("AGENTS.md", compact ? 800 : 1_800),
            ("USER.md", compact ? 700 : 1_200),
            ("MEMORY.md", compact ? 500 : 1_500),
            ("TOOLS.md", compact ? 300 : 800)
        ]
        var sections = coreFiles.compactMap { file in
            directWorkspaceFileSection(
                relativePath: file.relativePath,
                maxCharacters: file.maxCharacters
            )
        }

        if !compact, let styleSection = directWorkspaceFileSection(
            relativePath: "style/vibe1.txt",
            maxCharacters: 2_000
        ) {
            sections.append(styleSection)
        }

        if !compact {
            sections.append(contentsOf: directMemoryFileSections())
        }

        let context = sections.isEmpty ? "No workspace setup files found." : sections.joined(separator: "\n\n")
        if compact {
            directCompactPersonaContextCache = context
            appendLog("[latency] Direct compact persona context cached; characters=\(context.count)")
        } else {
            directPersonaContextCache = context
            appendLog("[latency] Direct persona context cached; characters=\(context.count)")
        }
        return context
    }

    private func directWorkspaceFileSection(relativePath: String, maxCharacters: Int? = nil) -> String? {
        let url = workspaceDirectory.appendingPathComponent(relativePath)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let body: String
        if let maxCharacters, trimmed.count > maxCharacters {
            body = String(trimmed.prefix(maxCharacters))
                + "\n\n[truncated for direct voice speed; full file remains in workspace]"
        } else {
            body = trimmed
        }
        return "## \(relativePath)\n\(body)"
    }

    private func directMemoryFileSections() -> [String] {
        let memoryDirectory = workspaceDirectory.appendingPathComponent("memory", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: memoryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(directMemoryFileLimit)
            .compactMap { url in
                directWorkspaceFileSection(
                    relativePath: "memory/\(url.lastPathComponent)",
                    maxCharacters: 1_000
                )
            }
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

    private func runProcess(
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: TimeInterval? = nil
    ) async throws -> ProcessOutput {
        try await runExternalProcess(
            executableURL: nodeURL,
            arguments: arguments,
            currentDirectoryURL: repositoryDirectory,
            environment: environment,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func runExternalProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String],
        timeoutSeconds: TimeInterval? = nil
    ) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let buffer = ProcessOutputBuffer()
            let completion = ProcessCompletionState()

            @Sendable func finish(
                _ result: Result<ProcessOutput, Error>,
                terminateIfRunning: Bool = false
            ) {
                guard completion.claim() else {
                    return
                }

                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                if terminateIfRunning, process.isRunning {
                    let processIdentifier = process.processIdentifier
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                        Darwin.kill(processIdentifier, SIGKILL)
                    }
                }

                switch result {
                case let .success(output):
                    continuation.resume(returning: output)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

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
                let snapshot = buffer.snapshot()
                let output = ProcessOutput(
                    stdout: snapshot.stdout,
                    stderr: snapshot.stderr,
                    exitCode: finished.terminationStatus
                )
                finish(.success(output))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            if let timeoutSeconds {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                    let snapshot = buffer.snapshot()
                    let stderr = snapshot.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let suffix = stderr.isEmpty ? "" : " Last error output: \(String(stderr.suffix(1200)))"
                    finish(
                        .failure(
                            OpenClawLocalControllerError.agentFailed(
                                "OpenClaw command timed out after \(Int(timeoutSeconds)) seconds.\(suffix)"
                            )
                        ),
                        terminateIfRunning: true
                    )
                }
            }
        }
    }

    private func runCommand(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String]
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
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

        try process.run()
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let snapshot = buffer.snapshot()
        return ProcessOutput(
            stdout: snapshot.stdout,
            stderr: snapshot.stderr,
            exitCode: process.terminationStatus
        )
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

    @discardableResult
    private func appendChatMessage(_ message: OpenClawChatMessage) -> UUID {
        chatMessages.append(message)
        if chatMessages.count > 100 {
            chatMessages.removeFirst(chatMessages.count - 100)
        }
        return message.id
    }

    private func updateChatMessage(id: UUID, text: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        var updatedMessages = chatMessages
        updatedMessages[index].text = text
        chatMessages = updatedMessages
    }

    private func removePendingAssistantPlaceholder() {
        guard let index = chatMessages.lastIndex(where: { $0.role == .assistant && $0.text == "…" }) else {
            return
        }
        chatMessages.remove(at: index)
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

    private nonisolated func isTCPPortOpen(host: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let socketDescriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
                guard socketDescriptor >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                defer { Darwin.close(socketDescriptor) }

                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = port.bigEndian

                let result = host.withCString { cString in
                    inet_pton(AF_INET, cString, &address.sin_addr)
                }
                guard result == 1 else {
                    continuation.resume(returning: false)
                    return
                }

                var socketAddress = sockaddr()
                memcpy(&socketAddress, &address, MemoryLayout<sockaddr_in>.size)
                let connectResult = withUnsafePointer(to: &socketAddress) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                        Darwin.connect(
                            socketDescriptor,
                            reboundPointer,
                            socklen_t(MemoryLayout<sockaddr_in>.size)
                        )
                    }
                }
                continuation.resume(returning: connectResult == 0)
            }
        }
    }

    private static func tokensPerSecond(tokens: Int?, durationNanoseconds: NSNumber?) -> Double? {
        guard let tokens,
              let durationNanoseconds,
              durationNanoseconds.doubleValue > 0 else {
            return nil
        }
        return Double(tokens) / (durationNanoseconds.doubleValue / 1_000_000_000)
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
    private let nodeURL = resolveNodeExecutableURL()
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
                    || key.hasPrefix("GRACULA_")
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

        let normalizedEntries = entriesWithProviderDefaults(entries)
        let rootObject: NSMutableDictionary
        if let data = try? Data(contentsOf: url),
           !data.isEmpty,
           let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            rootObject = NSMutableDictionary(dictionary: object)
        } else {
            rootObject = NSMutableDictionary()
        }

        for entry in normalizedEntries {
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

    private static func entriesWithProviderDefaults(_ entries: [OpenClawEditableSetting]) -> [OpenClawEditableSetting] {
        var normalized = entries

        ensureEntry(
            key: "models.providers.ollama.baseUrl",
            value: "http://127.0.0.1:11434",
            in: &normalized
        )
        ensureEntry(
            key: "models.providers.ollama.api",
            value: "ollama",
            in: &normalized
        )
        ensureEntry(
            key: "models.providers.ollama.authHeader",
            value: "false",
            kind: .bool,
            in: &normalized
        )
        ensureEntry(
            key: "models.providers.ollama.models",
            value: """
            [
              {
                "id": "qwen3:14b",
                "name": "Qwen3 14B (local Ollama)",
                "api": "ollama",
                "reasoning": false,
                "input": ["text"],
                "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
                "contextWindow": 65536,
                "maxTokens": 8192,
                "params": {
                  "think": false,
                  "keep_alive": "30m",
                  "num_ctx": 65536
                },
                "compat": {
                  "supportsTools": false
                }
              }
            ]
            """,
            kind: .array,
            in: &normalized
        )

        return normalized
    }

    private static func ensureEntry(
        key: String,
        value: String,
        kind: OpenClawEditableSetting.ValueKind = .string,
        in entries: inout [OpenClawEditableSetting]
    ) {
        guard !entries.contains(where: { $0.key == key }) else {
            return
        }
        entries.append(
            OpenClawEditableSetting(
                key: key,
                source: .json,
                kind: kind,
                isSecret: false,
                value: value
            )
        )
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
    var relativeCandidates: [URL] = []
    if currentDirectory.path != "/" {
        relativeCandidates.append(
            currentDirectory
                .appendingPathComponent("openclaw", isDirectory: true)
                .standardizedFileURL
        )
        relativeCandidates.append(
            currentDirectory
                .appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent("openclaw", isDirectory: true)
                .standardizedFileURL
        )
        relativeCandidates.append(
            currentDirectory
                .appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent("..", isDirectory: true)
                .appendingPathComponent("Vendor", isDirectory: true)
                .appendingPathComponent("openclaw", isDirectory: true)
                .standardizedFileURL
        )
    }

    let userRuntimeCandidate = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("GraculaExample", isDirectory: true)
        .appendingPathComponent("openclaw", isDirectory: true)

    for candidate in relativeCandidates + [userRuntimeCandidate] {
        if fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
    }

    return userRuntimeCandidate
}

private func resolveMLXRuntimeDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("GraculaExample", isDirectory: true)
        .appendingPathComponent("MLXRuntime", isDirectory: true)
}

private func resolveMLXModelsDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("GraculaExample", isDirectory: true)
        .appendingPathComponent("MLXModels", isDirectory: true)
}

private func resolveNodeExecutableURL() -> URL {
    let fileManager = FileManager.default
    let env = ProcessInfo.processInfo.environment
    if let override = env["GRACULA_NODE_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        let url = URL(filePath: override)
        if fileManager.isExecutableFile(atPath: url.path) {
            return url
        }
    }

    let candidates = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        "/usr/bin/node"
    ]
    for candidate in candidates {
        let url = URL(filePath: candidate)
        if fileManager.isExecutableFile(atPath: url.path) {
            return url
        }
    }
    return URL(filePath: candidates.first ?? "/usr/bin/node")
}

private struct PackageManagerCommand {
    let executableURL: URL
    let displayName: String
    let installArguments: [String]
    let buildArguments: [String]
}

private func resolvePackageManagerCommand() -> PackageManagerCommand? {
    let fileManager = FileManager.default
    let env = ProcessInfo.processInfo.environment
    if let override = env["GRACULA_PNPM_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        let url = URL(filePath: override)
        if fileManager.isExecutableFile(atPath: url.path) {
            return PackageManagerCommand(
                executableURL: url,
                displayName: url.lastPathComponent,
                installArguments: ["install", "--frozen-lockfile"],
                buildArguments: ["build"]
            )
        }
    }

    let pnpmCandidates = [
        "/opt/homebrew/bin/pnpm",
        "/usr/local/bin/pnpm",
        "/usr/bin/pnpm"
    ]
    for candidate in pnpmCandidates {
        let url = URL(filePath: candidate)
        if fileManager.isExecutableFile(atPath: url.path) {
            return PackageManagerCommand(
                executableURL: url,
                displayName: "pnpm",
                installArguments: ["install", "--frozen-lockfile"],
                buildArguments: ["build"]
            )
        }
    }

    let corepackCandidates = [
        "/opt/homebrew/bin/corepack",
        "/usr/local/bin/corepack",
        "/usr/bin/corepack"
    ]
    for candidate in corepackCandidates {
        let url = URL(filePath: candidate)
        if fileManager.isExecutableFile(atPath: url.path) {
            return PackageManagerCommand(
                executableURL: url,
                displayName: "corepack pnpm",
                installArguments: ["pnpm", "install", "--frozen-lockfile"],
                buildArguments: ["pnpm", "build"]
            )
        }
    }

    return nil
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

private final class ProcessCompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !didComplete else {
            return false
        }

        didComplete = true
        return true
    }
}

private struct DirectModelChatResult {
    let text: String
    let metrics: DirectModelMetrics?
}

private struct DirectModelMetrics {
    let providerLabel: String
    let promptTokens: Int?
    let promptTokensPerSecond: Double?
    let generationTokens: Int?
    let generationTokensPerSecond: Double?
    let peakMemoryGB: Double?

    var statusSummary: String {
        var parts: [String] = []
        if let generationTokensPerSecond {
            parts.append("\(Self.format(generationTokensPerSecond)) tok/s")
        }
        if let generationTokens {
            parts.append("\(generationTokens) generated")
        }
        if let promptTokensPerSecond {
            parts.append("prompt \(Self.format(promptTokensPerSecond)) tok/s")
        }
        if let peakMemoryGB {
            parts.append("peak \(Self.format(peakMemoryGB)) GB")
        }
        return parts.isEmpty ? "no throughput metrics reported" : parts.joined(separator: ", ")
    }

    var logSummary: String {
        "\(providerLabel): \(statusSummary)"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct DirectModelScriptResponse: Decodable {
    let text: String
    let metrics: DirectModelScriptMetrics?
}

private struct DirectModelScriptMetrics: Decodable {
    let promptTokens: Int?
    let promptTokensPerSecond: Double?
    let generationTokens: Int?
    let generationTokensPerSecond: Double?
    let peakMemoryGB: Double?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case promptTokensPerSecond = "prompt_tps"
        case generationTokens = "generation_tokens"
        case generationTokensPerSecond = "generation_tps"
        case peakMemoryGB = "peak_memory"
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

    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }

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
