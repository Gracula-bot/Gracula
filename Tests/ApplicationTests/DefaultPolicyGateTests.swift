import Application
import Domain
import Testing

@Test
func policyGateAllowsSafePlans() async throws {
    let gate = DefaultPolicyGate()
    let plan = AgentPlan(
        userText: "Open site",
        summary: "Open site",
        toolCalls: [ToolCall(name: "open_url", arguments: [:], riskLevel: .safe)]
    )

    let decision = try await gate.evaluate(plan)

    #expect(decision == .allow)
}

@Test
func policyGateAllowsAllowlistedReversiblePlans() async throws {
    let gate = DefaultPolicyGate(reversibleAllowlistedTools: ["write_note"])
    let plan = AgentPlan(
        userText: "Write note",
        summary: "Write note",
        toolCalls: [ToolCall(name: "write_note", arguments: [:], riskLevel: .reversible)]
    )

    let decision = try await gate.evaluate(plan)

    #expect(decision == .allow)
}

@Test
func policyGateRequiresConfirmationForNonAllowlistedReversiblePlans() async throws {
    let gate = DefaultPolicyGate()
    let plan = AgentPlan(
        userText: "Write note",
        summary: "Write note",
        toolCalls: [ToolCall(name: "write_note", arguments: [:], riskLevel: .reversible)]
    )

    let decision = try await gate.evaluate(plan)

    guard case .requiresConfirmation(let challenge) = decision else {
        Issue.record("Expected confirmation")
        return
    }
    #expect(challenge.requiredPhrase == nil)
}

@Test
func policyGateRequiresConfirmationForExternalCommunication() async throws {
    let gate = DefaultPolicyGate()
    let plan = AgentPlan(
        userText: "Send message",
        summary: "Send message to Anna",
        toolCalls: [ToolCall(name: "send_message", arguments: [:], riskLevel: .externalCommunication)]
    )

    let decision = try await gate.evaluate(plan)

    guard case .requiresConfirmation(let challenge) = decision else {
        Issue.record("Expected confirmation")
        return
    }
    #expect(challenge.requiredPhrase == nil)
    #expect(challenge.summary == "Send message to Anna")
}

@Test
func policyGateRequiresConfirmationForOnlyFansPublishing() async throws {
    let gate = DefaultPolicyGate()
    let plan = AgentPlan(
        userText: "Опубликуй пост в OnlyFans",
        summary: "Publish OnlyFans post",
        toolCalls: [
            ToolCall(
                name: "publish_onlyfans_post",
                arguments: ["text": .string("Test post")],
                riskLevel: .externalCommunication
            )
        ]
    )

    let decision = try await gate.evaluate(plan)

    guard case .requiresConfirmation(let challenge) = decision else {
        Issue.record("Expected confirmation")
        return
    }
    #expect(challenge.requiredPhrase == nil)
    #expect(challenge.summary == "Publish OnlyFans post")
}

@Test
func policyGateRequiresStrongConfirmationForFinancialOrCriticalPlans() async throws {
    let gate = DefaultPolicyGate()
    let plan = AgentPlan(
        userText: "Prepare payment",
        summary: "Prepare payment to vendor",
        toolCalls: [ToolCall(name: "prepare_payment", arguments: [:], riskLevel: .financialOrCritical)]
    )

    let decision = try await gate.evaluate(plan)

    guard case .requiresConfirmation(let challenge) = decision else {
        Issue.record("Expected strong confirmation")
        return
    }
    #expect(challenge.requiredPhrase == "Подтверждаю действие: Prepare payment to vendor")
}
