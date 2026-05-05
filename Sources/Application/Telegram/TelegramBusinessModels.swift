import Foundation

public struct TelegramBusinessSettings: Sendable, Equatable {
    public let enabled: Bool
    public let botToken: String
    public let businessConnectionId: String
    public let pollIntervalSeconds: Double
    public let autoReplyEnabled: Bool
    public let markReadEnabled: Bool

    public init(
        enabled: Bool = false,
        botToken: String = "",
        businessConnectionId: String = "",
        pollIntervalSeconds: Double = 2,
        autoReplyEnabled: Bool = true,
        markReadEnabled: Bool = true
    ) {
        self.enabled = enabled
        self.botToken = botToken
        self.businessConnectionId = businessConnectionId
        self.pollIntervalSeconds = pollIntervalSeconds
        self.autoReplyEnabled = autoReplyEnabled
        self.markReadEnabled = markReadEnabled
    }
}

public struct TelegramBusinessChat: Sendable, Equatable {
    public let id: Int64
    public let type: String
    public let displayName: String
    public let username: String?

    public init(id: Int64, type: String, displayName: String, username: String?) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.username = username
    }
}

public struct TelegramBusinessIncomingMessage: Sendable, Equatable {
    public let updateId: Int
    public let businessConnectionId: String
    public let messageId: Int
    public let chat: TelegramBusinessChat
    public let senderName: String?
    public let senderUsername: String?
    public let text: String
    public let date: Date

    public init(
        updateId: Int,
        businessConnectionId: String,
        messageId: Int,
        chat: TelegramBusinessChat,
        senderName: String?,
        senderUsername: String?,
        text: String,
        date: Date
    ) {
        self.updateId = updateId
        self.businessConnectionId = businessConnectionId
        self.messageId = messageId
        self.chat = chat
        self.senderName = senderName
        self.senderUsername = senderUsername
        self.text = text
        self.date = date
    }
}
