import Domain

public protocol AuditLogging: Sendable {
    func record(_ event: AuditEvent) async throws
}

