import Domain
import Foundation
import Testing

@Test
func highestRiskLevelIsSafeForEmptyPlan() {
    let plan = AgentPlan(userText: "hello", summary: "No tool calls", toolCalls: [])

    #expect(plan.highestRiskLevel == .safe)
}

@Test
func highestRiskLevelReturnsMaximumToolRisk() {
    let plan = AgentPlan(
        userText: "send and pay",
        summary: "Mixed risk plan",
        toolCalls: [
            ToolCall(name: "open_url", arguments: [:], riskLevel: .safe),
            ToolCall(name: "send_message", arguments: [:], riskLevel: .externalCommunication),
            ToolCall(name: "prepare_payment", arguments: [:], riskLevel: .financialOrCritical),
            ToolCall(name: "write_note", arguments: [:], riskLevel: .reversible)
        ]
    )

    #expect(plan.highestRiskLevel == .financialOrCritical)
}

@Test
func agentPlanCodableRoundTripPreservesValues() throws {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let callID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let plan = AgentPlan(
        id: id,
        userText: "Открой сайт apple.com",
        summary: "Open the requested website",
        toolCalls: [
            ToolCall(
                id: callID,
                name: "open_url",
                arguments: [
                    "url": .string("https://apple.com"),
                    "foreground": .bool(true)
                ],
                riskLevel: .safe
            )
        ]
    )

    let data = try JSONEncoder().encode(plan)
    let decoded = try JSONDecoder().decode(AgentPlan.self, from: data)

    #expect(decoded == plan)
}

