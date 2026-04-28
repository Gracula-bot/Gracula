import Domain
import Foundation
import Testing

@Test
func auditEventCodableRoundTripPreservesResult() throws {
    let event = AuditEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
        timestamp: Date(timeIntervalSince1970: 1_800_000_000),
        kind: .toolFinished,
        planID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
        toolCallID: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
        summary: "Opened URL",
        result: .success("Done")
    )

    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(AuditEvent.self, from: data)

    #expect(decoded == event)
}

