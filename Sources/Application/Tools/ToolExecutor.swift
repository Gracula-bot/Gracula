import Domain
import Foundation
import Shared

public actor ToolExecutor: ToolExecuting {
    private let registry: ToolRegistry
    private let auditLog: any AuditLogging
    private let traceLogger: TraceLogger?

    public init(registry: ToolRegistry, auditLog: any AuditLogging, traceLogger: TraceLogger? = nil) {
        self.registry = registry
        self.auditLog = auditLog
        self.traceLogger = traceLogger
    }

    public init(registry: ToolRegistry, auditLog: any AuditLogging) {
        self.init(registry: registry, auditLog: auditLog, traceLogger: nil)
    }

    public func execute(_ plan: AgentPlan) async throws -> [ToolResult] {
        var results: [ToolResult] = []
        for call in plan.toolCalls {
            let tool = try await registry.resolve(name: call.name)
            await traceLogger?.record(
                level: .info,
                event: "tool.started",
                component: "ToolExecutor",
                payload: toolPayload(call, planID: plan.id)
            )
            try await auditLog.record(
                AuditEvent(
                    kind: .toolStarted,
                    planID: plan.id,
                    toolCallID: call.id,
                    summary: "Started \(call.name)"
                )
            )

            do {
                let result = try await tool.run(call)
                results.append(result)
                await traceLogger?.record(
                    level: .info,
                    event: "tool.finished",
                    component: "ToolExecutor",
                    payload: toolResultPayload(call, result: result, planID: plan.id)
                )
                try await auditLog.record(
                    AuditEvent(
                        kind: .toolFinished,
                        planID: plan.id,
                        toolCallID: call.id,
                        summary: "Finished \(call.name)",
                        result: result
                    )
                )
            } catch {
                let result = ToolResult.failed(String(describing: error))
                await traceLogger?.record(
                    level: .error,
                    event: "tool.failed",
                    component: "ToolExecutor",
                    payload: toolResultPayload(call, result: result, planID: plan.id)
                )
                try await auditLog.record(
                    AuditEvent(
                        kind: .toolFailed,
                        planID: plan.id,
                        toolCallID: call.id,
                        summary: "Failed \(call.name)",
                        result: result
                    )
                )
                throw error
            }
        }
        return results
    }
}

private extension ToolExecutor {
    func toolPayload(_ call: ToolCall, planID: UUID) -> [String: TraceLogValue] {
        var payload: [String: TraceLogValue] = [
            "plan_id": .string(planID.uuidString.lowercased()),
            "tool_call_id": .string(call.id.uuidString.lowercased()),
            "tool_name": .string(call.name),
            "risk_level": .string(call.riskLevel.rawValue),
            "argument_names": .array(call.arguments.keys.sorted().map(TraceLogValue.string))
        ]

        if traceLogger?.configuration.includeFullContext == true {
            payload["arguments"] = .object(call.arguments.mapValues(traceArgumentValue))
        }
        return payload
    }

    func toolResultPayload(_ call: ToolCall, result: ToolResult, planID: UUID) -> [String: TraceLogValue] {
        var payload = toolPayload(call, planID: planID)
        payload["result"] = traceResultValue(result)
        return payload
    }

    func traceArgumentValue(_ argument: ToolArgument) -> TraceLogValue {
        switch argument {
        case .string(let value):
            return .string(value)
        case .int(let value):
            return .integer(value)
        case .double(let value):
            return .number(value)
        case .bool(let value):
            return .bool(value)
        case .stringArray(let values):
            return .array(values.map(TraceLogValue.string))
        }
    }

    func traceResultValue(_ result: ToolResult) -> TraceLogValue {
        switch result {
        case .success(let message):
            return .object(["status": .string("success"), "message": .string(message)])
        case .requiresUserInput(let message):
            return .object(["status": .string("requires_user_input"), "message": .string(message)])
        case .failed(let message):
            return .object(["status": .string("failed"), "message": .string(message)])
        }
    }
}
