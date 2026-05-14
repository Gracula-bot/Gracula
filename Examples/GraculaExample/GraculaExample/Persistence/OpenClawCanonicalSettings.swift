import Foundation
import Persistence

struct OpenClawCanonicalSettingsBridge {
    private let layout: ProjectRuntimeLayout
    private let store: AppConfigurationStore
    private let fileManager: FileManager

    init(
        layout: ProjectRuntimeLayout = ProjectRuntimeLayout.resolveDefault(),
        store: AppConfigurationStore? = nil,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.store = store ?? AppConfigurationStore(layout: layout)
        self.fileManager = fileManager
    }

    func snapshot() -> OpenClawSettingsSnapshot {
        let configuration = (try? store.loadOrCreate()) ?? AppConfigurationDefaults.make(layout: layout)

        let runtimeRows = [
            row("Project root", layout.projectRootURL.path),
            row("Runtime root", layout.runtimeRootURL.path),
            row("Canonical plist", layout.configurationFileURL.path),
            row("Canonical template", layout.configurationTemplateFileURL.path),
            row("Workspace directory", layout.workspaceDirectoryURL.path),
            row("Venv Python", configuration.python.executablePath),
            row("Gateway entrypoint", configuration.gateway.entrypointPath)
        ]

        let permissionRows = [
            row("Browser command", configuration.toolRuntimeFlags.browserCommand),
            row("Track only groups", configuration.toolRuntimeFlags.trackOnlyGroups ? "1" : "0"),
            row("Track auto links", configuration.toolRuntimeFlags.trackAutoLinks ? "1" : "0"),
            row("Qdrant enabled", configuration.qdrant.enabled ? "1" : "0"),
            row("Gateway enabled", configuration.gateway.enabled ? "1" : "0")
        ]

        let environmentEntries = Self.environmentEntries(from: configuration)
        let environmentRows = environmentEntries.map { entry in
            row(entry.key, entry.isSecret && !entry.value.isEmpty ? "[redacted]" : entry.value)
        }

        let jsonEntries = Self.jsonEntries(from: configuration)
        let toolRows = jsonEntries
            .filter { $0.key.hasPrefix("agents.") || $0.key.hasPrefix("integrations.") || $0.key.hasPrefix("models.") }
            .map { row($0.key, $0.isSecret && !$0.value.isEmpty ? "[redacted]" : $0.value) }

        return OpenClawSettingsSnapshot(
            runtimeRows: runtimeRows,
            permissionRows: permissionRows,
            environmentRows: environmentRows,
            toolRows: toolRows,
            environmentEntries: environmentEntries,
            jsonEntries: jsonEntries,
            workspaceFiles: readWorkspaceFiles()
        )
    }

    func apply(
        environmentEntries: [OpenClawEditableSetting],
        jsonEntries: [OpenClawEditableSetting],
        workspaceFiles: [OpenClawWorkspaceFile]
    ) throws {
        _ = try store.update { configuration in
            apply(environmentEntries: environmentEntries, jsonEntries: jsonEntries, to: &configuration)
        }
        try writeWorkspaceFiles(workspaceFiles)
    }

    private func readWorkspaceFiles() -> [OpenClawWorkspaceFile] {
        let names = [
            "AGENTS.md",
            "BOOTSTRAP.md",
            "HEARTBEAT.md",
            "IDENTITY.md",
            "MEMORY.md",
            "SOUL.md",
            "TOOLS.md",
            "USER.md",
            "Vibe.txt",
            "vibe.txt",
            "style/Vibe.txt",
            "style/vibe.txt",
            "style/vibe1.txt"
        ]

        return names.map { name in
            let url = layout.workspaceDirectoryURL.appendingPathComponent(name)
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let exists = fileManager.fileExists(atPath: url.path)
            let byteCount = (try? Data(contentsOf: url).count) ?? 0
            return OpenClawWorkspaceFile(
                relativePath: name,
                absolutePath: url.path,
                existsOnDisk: exists,
                byteCount: byteCount,
                contents: contents
            )
        }
    }

    private func writeWorkspaceFiles(_ files: [OpenClawWorkspaceFile]) throws {
        try fileManager.createDirectory(at: layout.workspaceDirectoryURL, withIntermediateDirectories: true)
        for file in files {
            let url = layout.workspaceDirectoryURL.appendingPathComponent(file.relativePath)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = Data(file.contents.utf8)
            try data.write(to: url, options: [.atomic])
        }
    }

    private func row(_ name: String, _ value: String) -> OpenClawSettingsRow {
        OpenClawSettingsRow(id: name, name: name, value: value.isEmpty ? "Not set" : value)
    }

    private static func environmentEntries(from configuration: AppConfiguration) -> [OpenClawEditableSetting] {
        [
            secretEnvironment("OPENAI_API_KEY", configuration.apiKeys.openAI),
            secretEnvironment("BRAVE_API_KEY", configuration.apiKeys.brave),
            secretEnvironment("GEMINI_API_KEY", configuration.apiKeys.gemini),
            secretEnvironment("XAI_API_KEY", configuration.apiKeys.xAI),
            secretEnvironment("PERPLEXITY_API_KEY", configuration.apiKeys.perplexity),
            secretEnvironment("MOONSHOT_API_KEY", configuration.apiKeys.moonshot),
            secretEnvironment("FIRECRAWL_API_KEY", configuration.apiKeys.firecrawl),
            environment("GRACULA_QDRANT_URL", configuration.qdrant.baseURL),
            environment("GRACULA_QDRANT_BIN", configuration.qdrant.binaryPath),
            environment("GRACULA_QDRANT_STORAGE_DIR", configuration.qdrant.storagePath),
            environment("GRACULA_TDLIB_JSON_LIBRARY", configuration.telegram.userTDLibPath)
        ]
    }

    private static func jsonEntries(from configuration: AppConfiguration) -> [OpenClawEditableSetting] {
        [
            json("agents.defaults.model.primary", configuration.llm.primaryModelRef),
            secretJSON("models.providers.openai.apiKey", configuration.apiKeys.openAI),
            json("agents.defaults.localPrompt.openAIChat.temperature", String(configuration.llm.openAITemperature), kind: .double),
            json("agents.defaults.localPrompt.openAIChat.topP", String(configuration.llm.openAITopP), kind: .double),
            json("agents.defaults.localPrompt.reasoning", configuration.llm.reasoningMode),
            json("integrations.telegram.business.enabled", configuration.telegram.businessEnabled ? "true" : "false", kind: .bool),
            secretJSON("integrations.telegram.business.botToken", configuration.telegram.businessBotToken),
            json("integrations.telegram.business.businessConnectionId", configuration.telegram.businessConnectionID),
            json("integrations.telegram.business.autoReplyEnabled", configuration.telegram.businessAutoReplyEnabled ? "true" : "false", kind: .bool),
            json("integrations.telegram.business.markReadEnabled", configuration.telegram.businessMarkReadEnabled ? "true" : "false", kind: .bool),
            json("integrations.telegram.business.pollIntervalSeconds", String(configuration.telegram.businessPollIntervalSeconds), kind: .int),
            json("integrations.telegram.user.enabled", configuration.telegram.userEnabled ? "true" : "false", kind: .bool),
            json("integrations.telegram.user.apiId", configuration.telegram.userAPIID),
            secretJSON("integrations.telegram.user.apiHash", configuration.telegram.userAPIHash),
            json("integrations.telegram.user.phone", configuration.telegram.userPhone),
            json("integrations.telegram.user.tdjsonLibraryPath", configuration.telegram.userTDLibPath),
            json("integrations.telegram.user.databaseDirectory", configuration.telegram.userDatabaseDirectory),
            json("integrations.telegram.user.filesDirectory", configuration.telegram.userFilesDirectory),
            secretJSON("integrations.telegram.user.encryptionKey", configuration.telegram.userEncryptionKey),
            json("integrations.telegram.user.chatAllowlist", configuration.telegram.userChatAllowlist)
        ]
    }

    private func apply(
        environmentEntries: [OpenClawEditableSetting],
        jsonEntries: [OpenClawEditableSetting],
        to configuration: inout AppConfiguration
    ) {
        let environmentMap = Dictionary(uniqueKeysWithValues: environmentEntries.map { ($0.key, $0.value) })
        let jsonMap = Dictionary(uniqueKeysWithValues: jsonEntries.map { ($0.key, $0.value) })

        configuration.apiKeys.openAI = environmentMap["OPENAI_API_KEY"] ?? jsonMap["models.providers.openai.apiKey"] ?? configuration.apiKeys.openAI
        configuration.apiKeys.brave = environmentMap["BRAVE_API_KEY"] ?? configuration.apiKeys.brave
        configuration.apiKeys.gemini = environmentMap["GEMINI_API_KEY"] ?? configuration.apiKeys.gemini
        configuration.apiKeys.xAI = environmentMap["XAI_API_KEY"] ?? configuration.apiKeys.xAI
        configuration.apiKeys.perplexity = environmentMap["PERPLEXITY_API_KEY"] ?? configuration.apiKeys.perplexity
        configuration.apiKeys.moonshot = environmentMap["MOONSHOT_API_KEY"] ?? configuration.apiKeys.moonshot
        configuration.apiKeys.firecrawl = environmentMap["FIRECRAWL_API_KEY"] ?? configuration.apiKeys.firecrawl

        configuration.llm.primaryModelRef = jsonMap["agents.defaults.model.primary"] ?? configuration.llm.primaryModelRef
        configuration.llm.openAITemperature = Double(jsonMap["agents.defaults.localPrompt.openAIChat.temperature"] ?? "") ?? configuration.llm.openAITemperature
        configuration.llm.openAITopP = Double(jsonMap["agents.defaults.localPrompt.openAIChat.topP"] ?? "") ?? configuration.llm.openAITopP
        configuration.llm.reasoningMode = jsonMap["agents.defaults.localPrompt.reasoning"] ?? configuration.llm.reasoningMode

        configuration.qdrant.baseURL = environmentMap["GRACULA_QDRANT_URL"] ?? configuration.qdrant.baseURL
        configuration.qdrant.binaryPath = environmentMap["GRACULA_QDRANT_BIN"] ?? configuration.qdrant.binaryPath
        configuration.qdrant.storagePath = environmentMap["GRACULA_QDRANT_STORAGE_DIR"] ?? configuration.qdrant.storagePath

        configuration.telegram.businessEnabled = Self.boolValue(jsonMap["integrations.telegram.business.enabled"], default: configuration.telegram.businessEnabled)
        configuration.telegram.businessBotToken = jsonMap["integrations.telegram.business.botToken"] ?? configuration.telegram.businessBotToken
        configuration.telegram.businessConnectionID = jsonMap["integrations.telegram.business.businessConnectionId"] ?? configuration.telegram.businessConnectionID
        configuration.telegram.businessAutoReplyEnabled = Self.boolValue(jsonMap["integrations.telegram.business.autoReplyEnabled"], default: configuration.telegram.businessAutoReplyEnabled)
        configuration.telegram.businessMarkReadEnabled = Self.boolValue(jsonMap["integrations.telegram.business.markReadEnabled"], default: configuration.telegram.businessMarkReadEnabled)
        configuration.telegram.businessPollIntervalSeconds = Int(jsonMap["integrations.telegram.business.pollIntervalSeconds"] ?? "") ?? configuration.telegram.businessPollIntervalSeconds
        configuration.telegram.userEnabled = Self.boolValue(jsonMap["integrations.telegram.user.enabled"], default: configuration.telegram.userEnabled)
        configuration.telegram.userAPIID = jsonMap["integrations.telegram.user.apiId"] ?? configuration.telegram.userAPIID
        configuration.telegram.userAPIHash = jsonMap["integrations.telegram.user.apiHash"] ?? configuration.telegram.userAPIHash
        configuration.telegram.userPhone = jsonMap["integrations.telegram.user.phone"] ?? configuration.telegram.userPhone
        configuration.telegram.userTDLibPath = environmentMap["GRACULA_TDLIB_JSON_LIBRARY"] ?? jsonMap["integrations.telegram.user.tdjsonLibraryPath"] ?? configuration.telegram.userTDLibPath
        configuration.telegram.userDatabaseDirectory = jsonMap["integrations.telegram.user.databaseDirectory"] ?? configuration.telegram.userDatabaseDirectory
        configuration.telegram.userFilesDirectory = jsonMap["integrations.telegram.user.filesDirectory"] ?? configuration.telegram.userFilesDirectory
        configuration.telegram.userEncryptionKey = jsonMap["integrations.telegram.user.encryptionKey"] ?? configuration.telegram.userEncryptionKey
        configuration.telegram.userChatAllowlist = jsonMap["integrations.telegram.user.chatAllowlist"] ?? configuration.telegram.userChatAllowlist
    }

    private static func boolValue(_ rawValue: String?, default defaultValue: Bool) -> Bool {
        guard let rawValue else {
            return defaultValue
        }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }

    private static func environment(_ key: String, _ value: String, secret: Bool = false) -> OpenClawEditableSetting {
        OpenClawEditableSetting(key: key, source: .environment, kind: .string, isSecret: secret, value: value)
    }

    private static func secretEnvironment(_ key: String, _ value: String) -> OpenClawEditableSetting {
        environment(key, value, secret: true)
    }

    private static func json(_ key: String, _ value: String, kind: OpenClawEditableSetting.ValueKind = .string) -> OpenClawEditableSetting {
        OpenClawEditableSetting(key: key, source: .json, kind: kind, isSecret: false, value: value)
    }

    private static func secretJSON(_ key: String, _ value: String) -> OpenClawEditableSetting {
        OpenClawEditableSetting(key: key, source: .json, kind: .string, isSecret: true, value: value)
    }
}
