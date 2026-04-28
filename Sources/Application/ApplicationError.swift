public enum ApplicationError: Error, Sendable, Equatable {
    case planningFailed(String)
    case policyEvaluationFailed(String)
    case toolExecutionFailed(String)
    case memoryFailed(String)
    case auditLoggingFailed(String)
}

