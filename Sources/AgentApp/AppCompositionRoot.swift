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
        let environment = ProcessInfo.processInfo.environment
        let openAIKey = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let openAIModel = Self.preferredOpenAIModel(from: environment)

        if !openAIKey.isEmpty {
            return LLMPlanningAdapter(
                client: OpenAIChatCompletionsLLMClient(
                    apiKey: openAIKey,
                    defaultModel: openAIModel
                ),
                promptCompiler: PromptCompiler(
                    availableTools: availableTools,
                    model: openAIModel
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
            client: LocalHTTPLLMClient(endpoint: endpoint),
            promptCompiler: PromptCompiler(
                availableTools: availableTools,
                model: environment["GRACULA_LLM_MODEL"]
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
        let environment = ProcessInfo.processInfo.environment
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
        let environment = ProcessInfo.processInfo.environment
        let openAIKey = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let openAIModel = preferredOpenAIModel(from: environment)
        let endpoint = environment["GRACULA_LLM_ENDPOINT"]
        let model = environment["GRACULA_LLM_MODEL"]

        if !openAIKey.isEmpty {
            return BotSettingsSnapshot(
                plannerMode: "OpenAI Chat Completions",
                llmEndpoint: "Configured",
                llmModel: openAIModel,
                llmEndpointEnvironmentKey: "OPENAI_API_KEY",
                llmModelEnvironmentKey: "OPENAI_MODEL",
                llmTemperature: 0.0,
                reversibleAllowlistedTools: Array(reversibleAllowlistedTools),
                approvedDirectories: approvedDirectories,
                tools: descriptors
            )
        }

        return BotSettingsSnapshot(
            plannerMode: endpoint.flatMap(URL.init(string:)) == nil ? "Demo planner" : "OpenAI-compatible local HTTP planner",
            llmEndpoint: endpoint ?? "Not set",
            llmModel: model ?? "Not set",
            llmTemperature: 0.0,
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
            .appendingPathComponent("Gracula", isDirectory: true)
    }

    private static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gracula", isDirectory: true)
    }

    private static func preferredOpenAIModel(from environment: [String: String]) -> String {
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
