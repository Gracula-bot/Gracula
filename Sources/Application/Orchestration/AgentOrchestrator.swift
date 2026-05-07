import Domain
import Foundation
import Shared

public actor AgentOrchestrator {
    private let planner: any Planning
    private let policyChecker: any PolicyChecking
    private let toolExecutor: any ToolExecuting
    private let memory: any AgentMemory
    private let auditLog: any AuditLogging
    private let traceLogger: TraceLogger?

    public init(
        planner: any Planning,
        policyChecker: any PolicyChecking,
        toolExecutor: any ToolExecuting,
        memory: any AgentMemory,
        auditLog: any AuditLogging,
        traceLogger: TraceLogger? = nil
    ) {
        self.planner = planner
        self.policyChecker = policyChecker
        self.toolExecutor = toolExecutor
        self.memory = memory
        self.auditLog = auditLog
        self.traceLogger = traceLogger
    }

    public init(
        planner: any Planning,
        policyChecker: any PolicyChecking,
        toolExecutor: any ToolExecuting,
        memory: any AgentMemory,
        auditLog: any AuditLogging
    ) {
        self.init(
            planner: planner,
            policyChecker: policyChecker,
            toolExecutor: toolExecutor,
            memory: memory,
            auditLog: auditLog,
            traceLogger: nil
        )
    }

    public func handleFinalUserText(_ userText: String) async throws -> AgentOrchestratorOutcome {
        try await memory.append(ConversationMessage(role: .user, text: userText))
        let context = try await memory.currentContext()
        await traceLogger?.record(
            level: .debug,
            event: "request.context_built",
            component: "AgentOrchestrator",
            payload: traceContextPayload(context)
        )
        let plan = try await planner.makePlan(userText: userText, context: context)
        await traceLogger?.record(
            level: .info,
            event: "plan.created",
            component: "AgentOrchestrator",
            payload: [
                "plan_id": .string(plan.id.uuidString.lowercased()),
                "summary": .string(plan.summary),
                "tool_call_count": .integer(plan.toolCalls.count),
                "highest_risk_level": .string(plan.highestRiskLevel.rawValue)
            ]
        )

        try await auditLog.record(
            AuditEvent(kind: .planCreated, planID: plan.id, summary: plan.summary)
        )

        let decision = try await policyChecker.evaluate(plan)
        switch decision {
        case .allow:
            await traceLogger?.record(
                level: .info,
                event: "policy.decision",
                component: "AgentOrchestrator",
                payload: [
                    "plan_id": .string(plan.id.uuidString.lowercased()),
                    "decision": .string("allow")
                ]
            )
            try await auditLog.record(
                AuditEvent(kind: .policyAllowed, planID: plan.id, summary: "Policy allowed plan")
            )
            let results = try await toolExecutor.execute(plan)
            try await memory.append(
                ConversationMessage(role: .assistant, text: summarize(results))
            )
            return .executed(plan: plan, results: results)

        case .requiresConfirmation(let challenge):
            await traceLogger?.record(
                level: .info,
                event: "policy.decision",
                component: "AgentOrchestrator",
                payload: [
                    "plan_id": .string(plan.id.uuidString.lowercased()),
                    "decision": .string("require_confirmation"),
                    "challenge_summary": .string(challenge.summary),
                    "required_phrase": challenge.requiredPhrase.map(TraceLogValue.string) ?? .null
                ]
            )
            try await auditLog.record(
                AuditEvent(
                    kind: .confirmationRequired,
                    planID: plan.id,
                    summary: challenge.summary
                )
            )
            return .requiresConfirmation(plan: plan, challenge: challenge)

        case .deny(let reason):
            await traceLogger?.record(
                level: .warn,
                event: "policy.decision",
                component: "AgentOrchestrator",
                payload: [
                    "plan_id": .string(plan.id.uuidString.lowercased()),
                    "decision": .string("deny"),
                    "reason": .string(reason)
                ]
            )
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

private extension AgentOrchestrator {
    func traceContextPayload(_ context: ConversationContext) -> [String: TraceLogValue] {
        var payload: [String: TraceLogValue] = [
            "message_count": .integer(context.messages.count),
            "roles": .array(context.messages.map { .string($0.role.rawValue) })
        ]

        guard traceLogger?.configuration.includeFullContext == true else {
            return payload
        }

        let formatter = ISO8601DateFormatter()
        payload["messages"] = .array(context.messages.map { message in
            .object([
                "id": .string(message.id.uuidString.lowercased()),
                "role": .string(message.role.rawValue),
                "text": .string(message.text),
                "timestamp": .string(formatter.string(from: message.timestamp))
            ])
        })
        return payload
    }
}

public enum AgentOrchestratorOutcome: Sendable, Equatable {
    case executed(plan: AgentPlan, results: [ToolResult])
    case requiresConfirmation(plan: AgentPlan, challenge: ConfirmationChallenge)
    case denied(plan: AgentPlan, reason: String)
}
