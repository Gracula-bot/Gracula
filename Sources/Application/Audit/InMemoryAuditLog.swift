import Domain

public actor InMemoryAuditLog: AuditLogging {
    private var recordedEvents: [AuditEvent] = []

    public init() {}

    public var events: [AuditEvent] {
        recordedEvents
    }

    public func record(_ event: AuditEvent) async throws {
        recordedEvents.append(event)
    }
}

