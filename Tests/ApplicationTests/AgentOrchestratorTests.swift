import Application
import Domain
import Testing

@Test
func orchestratorExecutesAllowedPlanAndRecordsAudit() async throws {
    let plan = AgentPlan(
        userText: "Open apple.com",
        summary: "Open website",
        toolCalls: [
            ToolCall(name: "open_url", arguments: [:], riskLevel: .safe)
        ]
    )
    let auditLog = InMemoryAuditLog()
    let registry = ToolRegistry(tools: [FakeTool(name: "open_url", result: .success("Opened"))])
    let executor = ToolExecutor(registry: registry, auditLog: auditLog)
    let orchestrator = AgentOrchestrator(
        planner: FakePlanner(plan: plan),
        policyChecker: DefaultPolicyGate(),
        toolExecutor: executor,
        memory: ConversationMemory(),
        auditLog: auditLog
    )

    let outcome = try await orchestrator.handleFinalUserText(plan.userText)

    #expect(outcome == .executed(plan: plan, results: [.success("Opened")]))
    let eventKinds = await auditLog.events.map(\.kind)
    #expect(eventKinds == [.planCreated, .policyAllowed, .toolStarted, .toolFinished])
}

@Test
func orchestratorReturnsConfirmationForExternalCommunication() async throws {
    let plan = AgentPlan(
        userText: "Send message",
        summary: "Send message to Anna",
        toolCalls: [
            ToolCall(name: "send_message", arguments: [:], riskLevel: .externalCommunication)
        ]
    )
    let auditLog = InMemoryAuditLog()
    let orchestrator = AgentOrchestrator(
        planner: FakePlanner(plan: plan),
        policyChecker: DefaultPolicyGate(),
        toolExecutor: FakeToolExecutor(results: []),
        memory: ConversationMemory(),
        auditLog: auditLog
    )

    let outcome = try await orchestrator.handleFinalUserText(plan.userText)

    guard case .requiresConfirmation(let returnedPlan, let challenge) = outcome else {
        Issue.record("Expected confirmation outcome")
        return
    }
    #expect(returnedPlan == plan)
    #expect(challenge.requiredPhrase == nil)
    #expect(challenge.summary == plan.summary)
    #expect(await auditLog.events.map(\.kind) == [.planCreated, .confirmationRequired])
}

@Test
func orchestratorReturnsDenialWithoutExecutingTools() async throws {
    let plan = AgentPlan(
        userText: "Do blocked action",
        summary: "Blocked action",
        toolCalls: [
            ToolCall(name: "blocked", arguments: [:], riskLevel: .safe)
        ]
    )
    let auditLog = InMemoryAuditLog()
    let executor = FakeToolExecutor(results: [.success("Should not run")])
    let orchestrator = AgentOrchestrator(
        planner: FakePlanner(plan: plan),
        policyChecker: FakePolicyChecker(decision: .deny("Blocked by policy")),
        toolExecutor: executor,
        memory: ConversationMemory(),
        auditLog: auditLog
    )

    let outcome = try await orchestrator.handleFinalUserText(plan.userText)

    #expect(outcome == .denied(plan: plan, reason: "Blocked by policy"))
    #expect(await executor.executionCount == 0)
    #expect(await auditLog.events.map(\.kind) == [.planCreated, .policyDenied])
}

