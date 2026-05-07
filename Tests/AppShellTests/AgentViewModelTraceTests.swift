import AppShell
import Application
import Domain
import Foundation
import Shared
import Testing

@MainActor
@Test
func agentViewModelEmitsSingleTraceAcrossRequestPipeline() async throws {
    let plan = AgentPlan(
        userText: "Open apple.com",
        summary: "Open website",
        toolCalls: [ToolCall(name: "open_url", arguments: ["url": .string("https://apple.com")], riskLevel: .safe)]
    )
    let traceLogger = TraceLogger(
        configuration: TraceLoggingConfiguration(
            enabled: true,
            includeFullContext: false,
            includeResponseBodies: false,
            redactSensitiveData: true,
            minimumLevel: .info
        ),
        logFileURL: nil
    )
    let auditLog = InMemoryAuditLog()
    let registry = ToolRegistry(tools: [ViewModelTestTool(name: "open_url", result: .success("Opened"))])
    let executor = ToolExecutor(registry: registry, auditLog: auditLog, traceLogger: traceLogger)
    let orchestrator = AgentOrchestrator(
        planner: ViewModelTestPlanner(plan: plan),
        policyChecker: DefaultPolicyGate(),
        toolExecutor: executor,
        memory: ConversationMemory(),
        auditLog: auditLog,
        traceLogger: traceLogger
    )
    let viewModel = AgentViewModel(
        orchestrator: orchestrator,
        toolExecutor: executor,
        auditLog: auditLog,
        traceLogger: traceLogger
    )
    viewModel.inputText = "Open apple.com"

    await viewModel.run()

    let events = await traceLogger.events()
    let traceIDs = Set(events.compactMap(\.traceID))
    #expect(traceIDs.count == 1)
    #expect(viewModel.latestTraceID != nil)
    #expect(viewModel.traceEvents.map(\.event).contains("user_request.received"))
    #expect(viewModel.traceEvents.map(\.event).contains("user_response.sent"))
    #expect(events.map(\.event).contains("user_request.received"))
    #expect(events.map(\.event).contains("plan.created"))
    #expect(events.map(\.event).contains("tool.started"))
    #expect(events.map(\.event).contains("tool.finished"))
    #expect(events.map(\.event).contains("user_response.sent"))

    let finalEvent = try #require(events.last { $0.event == "user_response.sent" })
    #expect(finalEvent.payload["status"] == .string("executed"))
    #expect(finalEvent.payload["tool_call_count"] == .integer(1))
}

private struct ViewModelTestPlanner: Planning {
    let plan: AgentPlan

    func makePlan(userText: String, context: ConversationContext) async throws -> AgentPlan {
        plan
    }
}

private struct ViewModelTestTool: AgentTool {
    let name: String
    let result: ToolResult
    let riskLevel: ToolRiskLevel = .safe

    var description: String { "View model test tool" }

    func run(_ call: ToolCall) async throws -> ToolResult {
        result
    }
}
