import Foundation

public enum AppConfigurationEnvironmentBuilder {
    public static func build(
        configuration: AppConfiguration,
        layout: ProjectRuntimeLayout,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment: [String: String] = [:]

        for key in ["HOME", "TMPDIR", "TEMP", "TMP", "TERM", "__CFBundleIdentifier", "SSH_AUTH_SOCK"] {
            if let value = processEnvironment[key], !value.isEmpty {
                environment[key] = value
            }
        }

        let inheritedPathEntries = (processEnvironment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        var pathEntries = [
            layout.binDirectoryURL.path,
            layout.venvDirectoryURL.appendingPathComponent("bin", isDirectory: true).path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        pathEntries.append(contentsOf: inheritedPathEntries)

        var seenPathEntries = Set<String>()
        environment["PATH"] = pathEntries
            .filter { seenPathEntries.insert($0).inserted }
            .joined(separator: ":")

        environment["GRACULA_PROJECT_DIR"] = configuration.runtimePaths.projectRootPath
        environment["GRACULA_RUNTIME_ROOT"] = configuration.runtimePaths.runtimeRootPath
        environment["GRACULA_CANONICAL_CONFIG_PLIST"] = configuration.runtimePaths.canonicalPlistPath
        environment["OPENAI_API_KEY"] = configuration.apiKeys.openAI
        environment["OPENAI_MODEL"] = configuration.llm.primaryModelRef.replacingOccurrences(of: "openai/", with: "")
        environment["OPENAI_TEMPERATURE"] = String(configuration.llm.openAITemperature)
        environment["GRACULA_LLM_MODEL"] = configuration.llm.primaryModelRef
        environment["GRACULA_LLM_TEMPERATURE"] = String(configuration.llm.openAITemperature)
        environment["GRACULA_QDRANT_URL"] = configuration.qdrant.baseURL
        environment["GRACULA_QDRANT_BIN"] = configuration.qdrant.binaryPath
        environment["GRACULA_QDRANT_STORAGE_DIR"] = configuration.qdrant.storagePath
        environment["GRACULA_QDRANT_API_KEY"] = configuration.qdrant.apiKey
        environment["GRACULA_WHISPER_PYTHON"] = configuration.python.executablePath
        environment["GRACULA_FFMPEG_PATH"] = configuration.python.ffmpegExecutablePath
        environment["OPENCLAW_WORKSPACE_DIR"] = configuration.runtimePaths.workspacePath
        environment["OPENCLAW_CONFIG_DIR"] = layout.runtimeRootURL.path
        environment["OPENCLAW_STATE_DIR"] = layout.runtimeRootURL.path
        environment["OPENCLAW_CONFIG_PATH"] = layout.openClawConfigFileURL.path
        environment["OPENCLAW_GATEWAY_BIND"] = "loopback"
        environment["OPENCLAW_GATEWAY_PORT"] = String(configuration.llm.gatewayPort)
        environment["OPENCLAW_GATEWAY_URL"] = "ws://127.0.0.1:\(configuration.llm.gatewayPort)"
        environment["OPENCLAW_BRIDGE_PORT"] = String(configuration.llm.bridgePort)
        environment["OPENCLAW_STREAM_BRIDGE_PORT"] = String(configuration.llm.streamBridgePort)
        environment["OPENCLAW_STREAM_BRIDGE_HOST"] = "127.0.0.1"
        environment["OPENCLAW_STREAM_BRIDGE_URL"] = "http://127.0.0.1:\(configuration.llm.streamBridgePort)/api/control/speak"
        environment["OPENCLAW_TRACK_BRIDGE_URL"] = "http://127.0.0.1:\(configuration.llm.streamBridgePort)/track"
        environment["OPENCLAW_TRACK_ONLY_GROUPS"] = configuration.toolRuntimeFlags.trackOnlyGroups ? "1" : "0"
        environment["OPENCLAW_TRACK_AUTO_LINKS"] = configuration.toolRuntimeFlags.trackAutoLinks ? "1" : "0"
        environment["GRACULA_TRACE_LOGGING_ENABLED"] = configuration.tracing.enabled ? "1" : "0"
        environment["GRACULA_TRACE_LOG_FULL_CONTEXT"] = configuration.tracing.logFullContext ? "1" : "0"
        environment["GRACULA_TRACE_LOG_RESPONSE_BODY"] = configuration.tracing.logResponseBodies ? "1" : "0"
        environment["GRACULA_TRACE_REDACT_SENSITIVE_DATA"] = configuration.tracing.redactSensitiveData ? "1" : "0"
        environment["GRACULA_TRACE_LOG_LEVEL"] = configuration.tracing.logLevel
        environment["GRACULA_TRACE_LOG_PATH"] = layout.logsDirectoryURL.appendingPathComponent("request-trace.jsonl").path
        environment["BROWSER"] = configuration.toolRuntimeFlags.browserCommand
        environment["GRACULA_TELEGRAM_BOT_TOKEN"] = configuration.telegram.businessBotToken
        environment["GRACULA_TELEGRAM_BUSINESS_CONNECTION_ID"] = configuration.telegram.businessConnectionID
        environment["GRACULA_TELEGRAM_USER_ENABLED"] = configuration.telegram.userEnabled ? "1" : "0"
        environment["GRACULA_TELEGRAM_API_ID"] = configuration.telegram.userAPIID
        environment["GRACULA_TELEGRAM_API_HASH"] = configuration.telegram.userAPIHash
        environment["GRACULA_TELEGRAM_PHONE"] = configuration.telegram.userPhone
        environment["GRACULA_TDLIB_JSON_LIBRARY"] = TDLibLibraryLocator.resolveExistingPath(
            preferredPath: configuration.telegram.userTDLibPath
        ) ?? configuration.telegram.userTDLibPath
        environment["GRACULA_TELEGRAM_USER_DATABASE_DIR"] = configuration.telegram.userDatabaseDirectory
        environment["GRACULA_TELEGRAM_USER_FILES_DIR"] = configuration.telegram.userFilesDirectory
        environment["GRACULA_TELEGRAM_USER_ENCRYPTION_KEY"] = configuration.telegram.userEncryptionKey
        environment["GRACULA_TELEGRAM_USER_CHAT_ALLOWLIST"] = configuration.telegram.userChatAllowlist
        environment["BRAVE_API_KEY"] = configuration.apiKeys.brave
        environment["GEMINI_API_KEY"] = configuration.apiKeys.gemini
        environment["XAI_API_KEY"] = configuration.apiKeys.xAI
        environment["PERPLEXITY_API_KEY"] = configuration.apiKeys.perplexity
        environment["MOONSHOT_API_KEY"] = configuration.apiKeys.moonshot
        environment["KIMI_API_KEY"] = configuration.apiKeys.moonshot
        environment["FIRECRAWL_API_KEY"] = configuration.apiKeys.firecrawl
        return environment
    }
}
