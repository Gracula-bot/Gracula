import Foundation
import Testing
import Voice

@Test
func transcriptEventCodableRoundTripPreservesValues() throws {
    let event = TranscriptEvent(text: "Открой apple.com", kind: .final, confidence: 0.9)

    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(TranscriptEvent.self, from: data)

    #expect(decoded == event)
}
