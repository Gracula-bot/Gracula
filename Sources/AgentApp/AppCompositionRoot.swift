import AppShell
import Application
import Domain

struct AppCompositionRoot {
    @MainActor
    func makeAgentView() -> AgentView {
        let auditLog = InMemoryAuditLog()
        let registry = ToolRegistry(
            tools: [
                DemoTool(name: "open_url", resultPrefix: "Opened URL"),
                DemoTool(name: "write_note", resultPrefix: "Wrote note", riskLevel: .reversible),
                DemoTool(name: "send_message", resultPrefix: "Sent message", riskLevel: .externalCommunication)
            ]
        )
        let executor = ToolExecutor(registry: registry, auditLog: auditLog)
        let orchestrator = AgentOrchestrator(
            planner: DemoPlanner(),
            policyChecker: DefaultPolicyGate(reversibleAllowlistedTools: ["write_note"]),
            toolExecutor: executor,
            memory: ConversationMemory(),
            auditLog: auditLog
        )
        return AgentView(
            viewModel: AgentViewModel(
                orchestrator: orchestrator,
                toolExecutor: executor,
                auditLog: auditLog
            )
        )
    }
}

private struct DemoPlanner: Planning {
    func makePlan(userText: String, context: ConversationContext) async throws -> AgentPlan {
        let lowercasedText = userText.lowercased()

        if lowercasedText.contains("send") || lowercasedText.contains("отправ") {
            return AgentPlan(
                userText: userText,
                summary: "Send prepared message",
                toolCalls: [
                    ToolCall(
                        name: "send_message",
                        arguments: ["body": .string(userText)],
                        riskLevel: .externalCommunication
                    )
                ]
            )
        }

        if lowercasedText.contains("note") || lowercasedText.contains("замет") || lowercasedText.contains("запиш") {
            return AgentPlan(
                userText: userText,
                summary: "Write note",
                toolCalls: [
                    ToolCall(
                        name: "write_note",
                        arguments: ["text": .string(userText)],
                        riskLevel: .reversible
                    )
                ]
            )
        }

        return AgentPlan(
            userText: userText,
            summary: "Open requested URL",
            toolCalls: [
                ToolCall(
                    name: "open_url",
                    arguments: ["url": .string(userText)],
                    riskLevel: .safe
                )
            ]
        )
    }
}

private struct DemoTool: AgentTool {
    let name: String
    let resultPrefix: String
    let riskLevel: ToolRiskLevel

    init(name: String, resultPrefix: String, riskLevel: ToolRiskLevel = .safe) {
        self.name = name
        self.resultPrefix = resultPrefix
        self.riskLevel = riskLevel
    }

    var description: String {
        "Demo \(name) tool"
    }

    func run(_ call: ToolCall) async throws -> ToolResult {
        .success("\(resultPrefix): \(call.arguments)")
    }
}
