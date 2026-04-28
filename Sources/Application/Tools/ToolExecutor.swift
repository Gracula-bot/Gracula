import Domain

public actor ToolExecutor: ToolExecuting {
    private let registry: ToolRegistry
    private let auditLog: any AuditLogging

    public init(registry: ToolRegistry, auditLog: any AuditLogging) {
        self.registry = registry
        self.auditLog = auditLog
    }

    public func execute(_ plan: AgentPlan) async throws -> [ToolResult] {
        var results: [ToolResult] = []
        for call in plan.toolCalls {
            let tool = try await registry.resolve(name: call.name)
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

