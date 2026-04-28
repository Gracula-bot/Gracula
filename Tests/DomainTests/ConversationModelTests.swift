import Domain
import Foundation
import Testing

@Test
func conversationContextCodableRoundTripPreservesMessages() throws {
    let context = ConversationContext(
        messages: [
            ConversationMessage(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                role: .user,
                text: "Open apple.com",
                timestamp: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            ConversationMessage(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                role: .assistant,
                text: "Opening apple.com",
                timestamp: Date(timeIntervalSince1970: 1_800_000_001)
            )
        ]
    )

    let data = try JSONEncoder().encode(context)
    let decoded = try JSONDecoder().decode(ConversationContext.self, from: data)

    #expect(decoded == context)
}

