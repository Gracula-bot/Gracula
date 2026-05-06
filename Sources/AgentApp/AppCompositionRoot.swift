import AgentSecurity
import AppShell
import Application
import Automation
import Domain
import Foundation
import LLM
import Persistence
import Tools
import Voice

struct AppCompositionRoot {
    private let llmMetricsStore = LLMRequestMetricsStore()

    @MainActor
    func makeAgentView() -> AgentView {
        let auditLog = InMemoryAuditLog()
        let workspaceOpening = WorkspaceOpeningClient()
        let fileSystem = LocalFileSystemClient()
        let notesDirectory = Self.notesDirectory()
        let readableDirectory = Self.readableDirectory()
        let pathAllowlist = PathAllowlist(
            approvedDirectories: [
                notesDirectory,
                readableDirectory
            ]
        )
        let tools: [any AgentTool] = [
            OpenURLTool(urlOpening: workspaceOpening),
            OpenAppTool(appOpening: workspaceOpening),
            PublishOnlyFansPostTool(poster: workspaceOpening),
            ReadAllowedFileTool(allowlist: pathAllowlist, fileSystem: fileSystem),
            WriteNoteTool(
                notesDirectory: notesDirectory,
                allowlist: pathAllowlist,
                fileSystem: fileSystem
            )
        ]
        let descriptors = Self.descriptors(for: tools)
        let reversibleAllowlistedTools: Set<String> = ["read_allowed_file", "write_note"]
        let botSettings = Self.botSettings(
            descriptors: descriptors,
            reversibleAllowlistedTools: reversibleAllowlistedTools,
            approvedDirectories: [
                notesDirectory,
                readableDirectory
            ]
        )
        let registry = ToolRegistry(tools: tools)
        let executor = ToolExecutor(registry: registry, auditLog: auditLog)
        let telegramService = Self.makeTelegramService()
        let telegramHandler = TelegramCommandHandler(
            service: telegramService,
            eventSink: { event in
                try? await auditLog.record(
                    AuditEvent(kind: .toolStarted, summary: event.rawValue)
                )
            }
        )
        let voiceCommandRouter = OpenClawVoiceCommandRouter(telegramHandler: telegramHandler)
        let orchestrator = AgentOrchestrator(
            planner: makePlanner(availableTools: descriptors),
            policyChecker: DefaultPolicyGate(reversibleAllowlistedTools: reversibleAllowlistedTools),
            toolExecutor: executor,
            memory: ConversationMemory(),
            auditLog: auditLog
        )
        return AgentView(
            viewModel: AgentViewModel(
                orchestrator: orchestrator,
                voiceCommandRouter: voiceCommandRouter,
                toolExecutor: executor,
                auditLog: auditLog,
                speechSynthesizer: AppleSpeechSynthesizer(),
                botSettings: botSettings,
                llmMetricsStore: llmMetricsStore
            )
        )
    }

    private func makePlanner(availableTools: [ToolDescriptor]) -> any Planning {
        let environment = Self.resolvedConfigurationEnvironment()
        let openAIKey = Self.preferredOpenAIAPIKey(from: environment)
        let openAIModel = Self.preferredOpenAIModel(from: environment)
        let temperature = Self.preferredLLMTemperature(from: environment)

        if !openAIKey.isEmpty {
            return LLMPlanningAdapter(
                client: OpenAIChatCompletionsLLMClient(
                    apiKey: openAIKey,
                    defaultModel: openAIModel,
                    requestStore: llmMetricsStore
                ),
                promptCompiler: PromptCompiler(
                    availableTools: availableTools,
                    model: openAIModel,
                    temperature: temperature
                ),
                parser: AgentPlanParser(availableTools: availableTools),
                metricsStore: llmMetricsStore
            )
        }

        guard let endpointString = environment["GRACULA_LLM_ENDPOINT"],
              let endpoint = URL(string: endpointString) else {
            return DemoPlanner()
        }

        return LLMPlanningAdapter(
            client: LocalHTTPLLMClient(endpoint: endpoint, requestStore: llmMetricsStore),
            promptCompiler: PromptCompiler(
                availableTools: availableTools,
                model: environment["GRACULA_LLM_MODEL"],
                temperature: temperature
            ),
            parser: AgentPlanParser(availableTools: availableTools),
            metricsStore: llmMetricsStore
        )
    }

    private static func descriptors(for tools: [any AgentTool]) -> [ToolDescriptor] {
        tools
            .map {
                ToolDescriptor(
                    name: $0.name,
                    description: $0.description,
                    riskLevel: $0.riskLevel
                )
            }
            .sorted { $0.name < $1.name }
    }

    private static func makeTelegramService() -> any TelegramService {
        let environment = resolvedConfigurationEnvironment()
        let automationService = TelegramMacAppAutomationService()
        let userSettings = TelegramUserSettings.make(
            environment: environment,
            configDirectory: applicationSupportDirectory()
        )
        let userService: (any TelegramUserClienting)? = userSettings.enabled ? TelegramUserTDLibClient(settings: userSettings) : nil

        let businessToken = environment["GRACULA_TELEGRAM_BOT_TOKEN"] ?? environment["TELEGRAM_BOT_TOKEN"] ?? ""
        let trimmedBusinessToken = businessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let businessService = trimmedBusinessToken.isEmpty ? nil : TelegramBusinessBotService(botToken: trimmedBusinessToken)
        let businessConnectionId = environment["GRACULA_TELEGRAM_BUSINESS_CONNECTION_ID"]
            ?? environment["TELEGRAM_BUSINESS_CONNECTION_ID"]

        return TelegramRoutingService(
            automationService: automationService,
            userService: userService,
            businessService: businessService,
            businessConnectionId: businessConnectionId
        )
    }

    private static func botSettings(
        descriptors: [ToolDescriptor],
        reversibleAllowlistedTools: Set<String>,
        approvedDirectories: [URL]
    ) -> BotSettingsSnapshot {
        let environment = resolvedConfigurationEnvironment()
        let openAIKey = preferredOpenAIAPIKey(from: environment)
        let openAIModel = preferredOpenAIModel(from: environment)
        let temperature = preferredLLMTemperature(from: environment)
        let endpoint = environment["GRACULA_LLM_ENDPOINT"]
        let model = environment["GRACULA_LLM_MODEL"]

        if !openAIKey.isEmpty {
            return BotSettingsSnapshot(
                plannerMode: "OpenAI Chat Completions",
                llmEndpoint: "Configured",
                llmModel: openAIModel,
                llmEndpointEnvironmentKey: "OPENAI_API_KEY",
                llmModelEnvironmentKey: "OPENAI_MODEL",
                llmTemperature: temperature,
                reversibleAllowlistedTools: Array(reversibleAllowlistedTools),
                approvedDirectories: approvedDirectories,
                tools: descriptors
            )
        }

        return BotSettingsSnapshot(
            plannerMode: endpoint.flatMap(URL.init(string:)) == nil ? "Demo planner" : "OpenAI-compatible local HTTP planner",
            llmEndpoint: endpoint ?? "Not set",
            llmModel: model ?? "Not set",
            llmTemperature: temperature,
            reversibleAllowlistedTools: Array(reversibleAllowlistedTools),
            approvedDirectories: approvedDirectories,
            tools: descriptors
        )
    }

    private static func notesDirectory() -> URL {
        applicationSupportDirectory()
            .appendingPathComponent("Notes", isDirectory: true)
    }

    private static func readableDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("GraculaExample", isDirectory: true)
    }

    private static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GraculaExample", isDirectory: true)
    }

    private static func preferredOpenAIModel(from environment: [String: String]) -> String {
        if let configuredModel = configuredOpenAIModelFromJSONSettings() {
            return configuredModel
        }

        let candidates = [
            environment["OPENAI_MODEL"],
            environment["GRACULA_LLM_MODEL"]
        ]

        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return "gpt-5.4-mini"
    }

    private static func preferredOpenAIAPIKey(from environment: [String: String]) -> String {
        if let value = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return configuredOpenAIAPIKeyFromJSONSettings() ?? ""
    }

    private static func preferredLLMTemperature(from environment: [String: String]) -> Double {
        if let value = configuredLLMTemperatureFromJSONSettings() {
            return value
        }

        let candidates = [
            environment["OPENAI_TEMPERATURE"],
            environment["GRACULA_LLM_TEMPERATURE"]
        ]

        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                continue
            }
            if let value = Double(trimmed) {
                return value
            }
        }

        return 0.0
    }

    private static func configuredLLMTemperatureFromJSONSettings() -> Double? {
        let settingPath = "agents.defaults.localPrompt.openAIChat.temperature"
        var resolvedValue: Double?
        if let rawValue = mergedOpenClawJSONObject().flatMap({ jsonValue(forPath: settingPath, in: $0) }) {
            if let stringValue = rawValue as? String,
               let value = Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                resolvedValue = value
            } else if let numberValue = rawValue as? NSNumber {
                resolvedValue = numberValue.doubleValue
            }
        }

        return resolvedValue.map { min(max($0, 0.0), 2.0) }
    }

    private static func configuredOpenAIModelFromJSONSettings() -> String? {
        guard let rawValue = mergedOpenClawJSONObject().flatMap({
            jsonValue(forPath: "agents.defaults.model.primary", in: $0)
                ?? jsonValue(forPath: "agents.defaults.model", in: $0)
        }) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("openai/") else {
            return nil
        }
        return String(trimmed.dropFirst("openai/".count))
    }

    private static func configuredOpenAIAPIKeyFromJSONSettings() -> String? {
        guard let rawValue = mergedOpenClawJSONObject().flatMap({
            jsonValue(forPath: "models.providers.openai.apiKey", in: $0)
        }) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func resolvedConfigurationEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        mergeEnvFile(projectRootDirectory().appendingPathComponent(".env"), into: &environment)
        mergeEnvFile(openClawConfigDirectory().appendingPathComponent(".env"), into: &environment)
        if let jsonObject = mergedOpenClawJSONObject() {
            mergeEnvironmentVariables(from: jsonObject, into: &environment)
        }
        return environment
    }

    private static func mergedOpenClawJSONObject() -> [String: Any]? {
        let configDirectory = openClawConfigDirectory()
        let baseObject = jsonObject(at: configDirectory.appendingPathComponent("openclaw.json"))
        let overrideObject = jsonObject(at: configDirectory.appendingPathComponent("gracula-example.json"))

        switch (baseObject, overrideObject) {
        case let (base?, override?):
            var merged = base
            deepMergeJSONObject(override, into: &merged)
            return merged
        case let (base?, nil):
            return base
        case let (nil, override?):
            return override
        case (nil, nil):
            return nil
        }
    }

    private static func openClawConfigDirectory() -> URL {
        projectRootDirectory().appendingPathComponent(".openclaw", isDirectory: true)
    }

    private static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func jsonValue(forPath path: String, in object: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        guard !components.isEmpty else {
            return nil
        }

        var current: Any = object
        for component in components {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[component] else {
                return nil
            }
            current = next
        }

        return current
    }

    private static func projectRootDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func mergeEnvFile(_ url: URL, into environment: inout [String: String]) {
        guard let contents = try? String(contentsOf: url) else {
            return
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"),
                  let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                continue
            }

            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }

            environment[key] = value
        }
    }

    private static func mergeEnvironmentVariables(from rootObject: [String: Any], into environment: inout [String: String]) {
        guard let envObject = rootObject["env"] as? [String: Any],
              let vars = envObject["vars"] as? [String: Any] else {
            return
        }

        for (key, rawValue) in vars {
            if let value = rawValue as? String {
                environment[key] = value
            } else if let value = rawValue as? NSNumber {
                environment[key] = value.stringValue
            }
        }
    }

    private static func deepMergeJSONObject(_ override: [String: Any], into base: inout [String: Any]) {
        for (key, overrideValue) in override {
            if let overrideDictionary = overrideValue as? [String: Any],
               let baseDictionary = base[key] as? [String: Any] {
                var mergedChild = baseDictionary
                deepMergeJSONObject(overrideDictionary, into: &mergedChild)
                base[key] = mergedChild
            } else {
                base[key] = overrideValue
            }
        }
    }
}

private struct DemoPlanner: Planning {
    func makePlan(userText: String, context: ConversationContext) async throws -> AgentPlan {
        let lowercasedText = userText.lowercased()

        if lowercasedText.contains("read") || lowercasedText.contains("прочит") {
            return AgentPlan(
                userText: userText,
                summary: "Read allowed file",
                toolCalls: [
                    ToolCall(
                        name: "read_allowed_file",
                        arguments: ["path": .string(extractLastToken(from: userText))],
                        riskLevel: .reversible
                    )
                ]
            )
        }

        if lowercasedText.contains("app") || lowercasedText.contains("прилож") {
            return AgentPlan(
                userText: userText,
                summary: "Open app",
                toolCalls: [
                    ToolCall(
                        name: "open_app",
                        arguments: ["appName": .string(extractAppName(from: userText))],
                        riskLevel: .safe
                    )
                ]
            )
        }

        if let url = extractURL(from: userText) {
            return AgentPlan(
                userText: userText,
                summary: "Open URL",
                toolCalls: [
                    ToolCall(
                        name: "open_url",
                        arguments: ["url": .string(url)],
                        riskLevel: .safe
                    )
                ]
            )
        }

        return AgentPlan(
            userText: userText,
            summary: "Write note",
            toolCalls: [
                ToolCall(
                    name: "write_note",
                    arguments: [
                        "text": .string(userText),
                        "filename": .string("note.txt")
                    ],
                    riskLevel: .reversible
                )
            ]
        )
    }

    private func extractURL(from text: String) -> String? {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first { token in
                token.hasPrefix("http://") || token.hasPrefix("https://")
            }
    }

    private func extractAppName(from text: String) -> String {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let markerIndex = tokens.firstIndex(where: { $0.lowercased() == "app" || $0.lowercased() == "приложение" }),
              tokens.indices.contains(markerIndex + 1) else {
            return "Notes"
        }
        return tokens[(markerIndex + 1)...].joined(separator: " ")
    }

    private func extractLastToken(from text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
    }
}
