import Application
import Domain
import Testing

@Test
func toolExecutorRunsRegisteredToolsAndLogsResults() async throws {
    let auditLog = InMemoryAuditLog()
    let registry = ToolRegistry(tools: [
        FakeTool(name: "open_url", result: .success("Opened"))
    ])
    let executor = ToolExecutor(registry: registry, auditLog: auditLog)
    let plan = AgentPlan(
        userText: "Open apple.com",
        summary: "Open website",
        toolCalls: [ToolCall(name: "open_url", arguments: [:], riskLevel: .safe)]
    )

    let results = try await executor.execute(plan)

    #expect(results == [.success("Opened")])
    #expect(await auditLog.events.map(\.kind) == [.toolStarted, .toolFinished])
}

@Test
func toolExecutorFailsCleanlyForUnknownTool() async throws {
    let auditLog = InMemoryAuditLog()
    let registry = ToolRegistry()
    let executor = ToolExecutor(registry: registry, auditLog: auditLog)
    let plan = AgentPlan(
        userText: "Unknown",
        summary: "Unknown tool",
        toolCalls: [ToolCall(name: "missing", arguments: [:], riskLevel: .safe)]
    )

    do {
        _ = try await executor.execute(plan)
        Issue.record("Expected unknown tool error")
    } catch DomainError.unknownTool(let name) {
        #expect(name == "missing")
    }

    #expect(await auditLog.events.isEmpty)
}

