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

    let repositoryDirectory = URL(filePath: "/Users/gg/openclaw", directoryHint: .isDirectory)
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

            gatewayProcess = try launchProcess(
                name: "gateway",
                arguments: [
                    repositoryDirectory.appendingPathComponent("dist/index.js").path,
                    "gateway",
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

            scheduleHealthChecks()
        } catch {
            stop()
            statusText = "Start failed"
            appendLog("Start failed: \(error.localizedDescription)")
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
        async let gateway = checkHealth(url: URL(string: "http://\(gatewayHost):\(gatewayPort)/healthz")!)
        async let bridge = checkHealth(url: URL(string: "http://\(gatewayHost):\(streamBridgePort)/health")!)
        gatewayStatus = await gateway
        streamBridgeStatus = await bridge
        statusText = isRunning ? "Gateway \(gatewayStatus), bridge \(streamBridgeStatus)" : "Stopped"
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

            let response = try await runAgentTurn(message: message)
            let reply = response.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
            let sessionReply = reply.isEmpty ? latestAssistantReplyFromSession() : nil
            let visibleReply = sessionReply ?? reply
            if visibleReply.isEmpty {
                appendChatMessage(.system("OpenClaw returned an empty reply."))
            } else {
                appendChatMessage(.assistant(visibleReply))
            }
            chatStatusText = "Reply received."
            isSendingChat = false
            return visibleReply.isEmpty ? nil : visibleReply
        } catch {
            appendChatMessage(.error(error.localizedDescription))
            chatStatusText = "Chat failed."
            appendLog("Chat failed: \(error.localizedDescription)")
            isSendingChat = false
            return nil
        }
    }

    private func validateRuntime() throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: nodeURL.path) else {
            throw OpenClawLocalControllerError.missingRuntime("Node runtime not found at \(nodeURL.path).")
        }
        guard fileManager.fileExists(atPath: repositoryDirectory.appendingPathComponent("dist/index.js").path) else {
            throw OpenClawLocalControllerError.missingRuntime("OpenClaw dist/index.js not found. Build /Users/gg/openclaw first.")
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

    private func openClawEnvironment() throws -> [String: String] {
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

        environment["OPENCLAW_CONFIG_DIR"] = configDirectory.path
        environment["OPENCLAW_WORKSPACE_DIR"] = workspaceDirectory.path
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

    private func runAgentTurn(message: String) async throws -> OpenClawAgentTurnResponse {
        let result = try await runProcess(
            arguments: [
                repositoryDirectory.appendingPathComponent("dist/index.js").path,
                "agent",
                "--local",
                "--session-id",
                chatSessionID,
                "--message",
                message,
                "--json"
            ],
            environment: try openClawEnvironment()
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
            return latestPublishableAssistantMessage()
        }

        return latestPublishableAssistantMessage()
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

    private func latestPublishableAssistantMessage() -> String? {
        for message in chatMessages.reversed() where message.role == .assistant {
            if isPublishablePostText(message.text) && !looksLikeOnlyFansRefusal(message.text) {
                return message.text
            }
        }
        return nil
    }

    private func isPublishablePostText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
    }

    private func looksLikeOnlyFansRefusal(_ text: String) -> Bool {
        let normalized = normalizedCommandText(text)
        return normalized.contains("ты с ума сошел")
            || normalized.contains("какои onlyfans")
            || normalized.contains("я в другом жанре")
            || normalized.contains("отказыва")
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
