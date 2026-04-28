import Application
import Domain
import Foundation
import Testing

@Test
func planningPortCanBeExercisedWithFakePlanner() async throws {
    let expectedPlan = AgentPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
        userText: "Open apple.com",
        summary: "Open website",
        toolCalls: [
            ToolCall(name: "open_url", arguments: ["url": .string("https://apple.com")], riskLevel: .safe)
        ]
    )
    let planner = FakePlanner(plan: expectedPlan)

    let plan = try await planner.makePlan(
        userText: expectedPlan.userText,
        context: ConversationContext()
    )

    #expect(plan == expectedPlan)
}

@Test
func policyCheckingPortCanReturnConfirmationDecision() async throws {
    let challenge = ConfirmationChallenge(title: "Confirm", summary: "Send message")
    let policy = FakePolicyChecker(decision: .requiresConfirmation(challenge))
    let plan = AgentPlan(userText: "Send message", summary: "Risky", toolCalls: [])

    let decision = try await policy.evaluate(plan)

    #expect(decision == .requiresConfirmation(challenge))
}

@Test
func agentToolPortCanRunTypedToolCall() async throws {
    let tool = FakeTool(result: .success("Opened"))
    let call = ToolCall(name: tool.name, arguments: ["url": .string("https://apple.com")], riskLevel: .safe)

    let result = try await tool.run(call)

    #expect(tool.name == "fake_tool")
    #expect(tool.description == "Fake test tool")
    #expect(tool.riskLevel == .safe)
    #expect(result == .success("Opened"))
}

@Test
func toolExecutingPortCanReturnToolResults() async throws {
    let executor = FakeToolExecutor(results: [.success("Done")])
    let plan = AgentPlan(userText: "Run", summary: "Run fake tool", toolCalls: [])

    let results = try await executor.execute(plan)

    #expect(results == [.success("Done")])
}

@Test
func memoryPortCanAppendAndReturnContext() async throws {
    let memory = FakeMemory()
    let message = ConversationMessage(role: .user, text: "Hello")

    try await memory.append(message)
    let context = try await memory.currentContext()

    #expect(context.messages == [message])
}

@Test
func auditLoggingPortCanRecordEvents() async throws {
    let auditLog = FakeAuditLog()
    let event = AuditEvent(kind: .planCreated, summary: "Plan created")

    try await auditLog.record(event)

    #expect(await auditLog.events == [event])
}

private struct FakePlanner: Planning {
    let plan: AgentPlan

    func makePlan(userText: String, context: ConversationContext) async throws -> AgentPlan {
        plan
    }
}

private struct FakePolicyChecker: PolicyChecking {
    let decision: PolicyDecision

    func evaluate(_ plan: AgentPlan) async throws -> PolicyDecision {
        decision
    }
}

private struct FakeTool: AgentTool {
    let result: ToolResult

    var name: String {
        "fake_tool"
    }

    var description: String {
        "Fake test tool"
    }

    var riskLevel: ToolRiskLevel {
        .safe
    }

    func run(_ call: ToolCall) async throws -> ToolResult {
        result
    }
}

private struct FakeToolExecutor: ToolExecuting {
    let results: [ToolResult]

    func execute(_ plan: AgentPlan) async throws -> [ToolResult] {
        results
    }
}

private actor FakeMemory: AgentMemory {
    private var storedMessages: [ConversationMessage] = []

    func append(_ message: ConversationMessage) async throws {
        storedMessages.append(message)
    }

    func currentContext() async throws -> ConversationContext {
        ConversationContext(messages: storedMessages)
    }
}

private actor FakeAuditLog: AuditLogging {
    private var recordedEvents: [AuditEvent] = []

    var events: [AuditEvent] {
        recordedEvents
    }

    func record(_ event: AuditEvent) async throws {
        recordedEvents.append(event)
    }
}

