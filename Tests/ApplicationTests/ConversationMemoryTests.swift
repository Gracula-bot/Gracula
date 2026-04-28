import Application
import Domain
import Testing

@Test
func conversationMemoryKeepsOnlyLastMessagesWithinLimit() async throws {
    let memory = ConversationMemory(limit: 2)
    let first = ConversationMessage(role: .user, text: "one")
    let second = ConversationMessage(role: .assistant, text: "two")
    let third = ConversationMessage(role: .user, text: "three")

    try await memory.append(first)
    try await memory.append(second)
    try await memory.append(third)

    let context = try await memory.currentContext()

    #expect(context.messages == [second, third])
}

