import Foundation

public struct ConversationContext: Codable, Sendable, Equatable {
    public let messages: [ConversationMessage]

    public init(messages: [ConversationMessage] = []) {
        self.messages = messages
    }
}

public struct ConversationMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let role: ConversationRole
    public let text: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: ConversationRole,
        text: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

public enum ConversationRole: String, Codable, Sendable, Equatable {
    case user
    case assistant
    case system
    case tool
}

