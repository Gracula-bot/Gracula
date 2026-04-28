import Domain

public actor DefaultPolicyGate: PolicyChecking {
    private let reversibleAllowlistedTools: Set<String>

    public init(reversibleAllowlistedTools: Set<String> = []) {
        self.reversibleAllowlistedTools = reversibleAllowlistedTools
    }

    public func evaluate(_ plan: AgentPlan) async throws -> PolicyDecision {
        switch plan.highestRiskLevel {
        case .safe:
            return .allow

        case .reversible:
            if plan.toolCalls.allSatisfy({ reversibleAllowlistedTools.contains($0.name) }) {
                return .allow
            }
            return .requiresConfirmation(
                ConfirmationChallenge(
                    title: "Confirm reversible action",
                    summary: plan.summary
                )
            )

        case .externalCommunication:
            return .requiresConfirmation(
                ConfirmationChallenge(
                    title: "Confirm external communication",
                    summary: plan.summary
                )
            )

        case .financialOrCritical:
            return .requiresConfirmation(
                ConfirmationChallenge(
                    title: "Strong confirmation required",
                    summary: plan.summary,
                    requiredPhrase: "Подтверждаю действие: \(plan.summary)"
                )
            )
        }
    }
}

