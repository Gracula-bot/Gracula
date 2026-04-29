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
        let orchestrator = AgentOrchestrator(
            planner: Self.makePlanner(availableTools: descriptors),
            policyChecker: DefaultPolicyGate(reversibleAllowlistedTools: reversibleAllowlistedTools),
            toolExecutor: executor,
            memory: ConversationMemory(),
            auditLog: auditLog
        )
        return AgentView(
            viewModel: AgentViewModel(
                orchestrator: orchestrator,
                toolExecutor: executor,
                auditLog: auditLog,
                speechSynthesizer: AppleSpeechSynthesizer(),
                botSettings: botSettings
            )
        )
    }

    private static func makePlanner(availableTools: [ToolDescriptor]) -> any Planning {
        let environment = ProcessInfo.processInfo.environment
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
            parser: AgentPlanParser(availableTools: availableTools)
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

    private static func botSettings(
        descriptors: [ToolDescriptor],
        reversibleAllowlistedTools: Set<String>,
        approvedDirectories: [URL]
    ) -> BotSettingsSnapshot {
        let environment = ProcessInfo.processInfo.environment
        let endpoint = environment["GRACULA_LLM_ENDPOINT"]
        let model = environment["GRACULA_LLM_MODEL"]

        return BotSettingsSnapshot(
            plannerMode: endpoint.flatMap(URL.init(string:)) == nil ? "Demo planner" : "OpenAI-compatible local HTTP planner",
            llmEndpoint: endpoint ?? "Not set",
            llmModel: model ?? "Not set",
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
