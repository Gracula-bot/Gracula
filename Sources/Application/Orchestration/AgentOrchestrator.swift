import Domain

public actor AgentOrchestrator {
    private let planner: any Planning
    private let policyChecker: any PolicyChecking
    private let toolExecutor: any ToolExecuting
    private let memory: any AgentMemory
    private let auditLog: any AuditLogging

    public init(
        planner: any Planning,
        policyChecker: any PolicyChecking,
        toolExecutor: any ToolExecuting,
        memory: any AgentMemory,
        auditLog: any AuditLogging
    ) {
        self.planner = planner
        self.policyChecker = policyChecker
        self.toolExecutor = toolExecutor
        self.memory = memory
        self.auditLog = auditLog
    }

    public func handleFinalUserText(_ userText: String) async throws -> AgentOrchestratorOutcome {
        try await memory.append(ConversationMessage(role: .user, text: userText))
        let context = try await memory.currentContext()
        let plan = try await planner.makePlan(userText: userText, context: context)

        try await auditLog.record(
            AuditEvent(kind: .planCreated, planID: plan.id, summary: plan.summary)
        )

        let decision = try await policyChecker.evaluate(plan)
        switch decision {
        case .allow:
            try await auditLog.record(
                AuditEvent(kind: .policyAllowed, planID: plan.id, summary: "Policy allowed plan")
            )
            let results = try await toolExecutor.execute(plan)
            try await memory.append(
                ConversationMessage(role: .assistant, text: summarize(results))
            )
            return .executed(plan: plan, results: results)

        case .requiresConfirmation(let challenge):
            try await auditLog.record(
                AuditEvent(
                    kind: .confirmationRequired,
                    planID: plan.id,
                    summary: challenge.summary
                )
            )
            return .requiresConfirmation(plan: plan, challenge: challenge)

        case .deny(let reason):
            try await auditLog.record(
                AuditEvent(kind: .policyDenied, planID: plan.id, summary: reason)
            )
            try await memory.append(ConversationMessage(role: .assistant, text: reason))
            return .denied(plan: plan, reason: reason)
        }
    }

    private func summarize(_ results: [ToolResult]) -> String {
        results.map { result in
            switch result {
            case .success(let message):
                message
            case .requiresUserInput(let message):
                message
            case .failed(let message):
                message
            }
        }
        .joined(separator: "\n")
    }
}

public enum AgentOrchestratorOutcome: Sendable, Equatable {
    case executed(plan: AgentPlan, results: [ToolResult])
    case requiresConfirmation(plan: AgentPlan, challenge: ConfirmationChallenge)
    case denied(plan: AgentPlan, reason: String)
}

