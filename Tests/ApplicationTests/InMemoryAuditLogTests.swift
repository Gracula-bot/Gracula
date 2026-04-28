import Application
import Domain
import Testing

@Test
func inMemoryAuditLogRecordsEventsInOrder() async throws {
    let auditLog = InMemoryAuditLog()
    let first = AuditEvent(kind: .planCreated, summary: "Plan")
    let second = AuditEvent(kind: .toolStarted, summary: "Tool")

    try await auditLog.record(first)
    try await auditLog.record(second)

    #expect(await auditLog.events == [first, second])
}

