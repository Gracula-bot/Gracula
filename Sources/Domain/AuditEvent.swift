import Foundation

public struct AuditEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let kind: AuditEventKind
    public let planID: UUID?
    public let toolCallID: UUID?
    public let summary: String
    public let result: ToolResult?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: AuditEventKind,
        planID: UUID? = nil,
        toolCallID: UUID? = nil,
        summary: String,
        result: ToolResult? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.planID = planID
        self.toolCallID = toolCallID
        self.summary = summary
        self.result = result
    }
}

public enum AuditEventKind: String, Codable, Sendable, Equatable {
    case planCreated
    case policyAllowed
    case confirmationRequired
    case confirmationApproved
    case confirmationRejected
    case policyDenied
    case toolStarted
    case toolFinished
    case toolFailed
}

