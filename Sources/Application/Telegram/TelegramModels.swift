import Foundation

public struct TelegramChat: Sendable, Equatable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct TelegramMessage: Sendable, Equatable {
    public let id: String
    public let chatId: String
    public let senderName: String?
    public let text: String
    public let date: Date

    public init(id: String, chatId: String, senderName: String?, text: String, date: Date) {
        self.id = id
        self.chatId = chatId
        self.senderName = senderName
        self.text = text
        self.date = date
    }
}

public struct PendingTelegramReply: Sendable, Equatable {
    public let chatId: String
    public let chatName: String
    public let messageText: String
    public let createdAt: Date
    public var status: PendingReplyStatus

    public init(
        chatId: String,
        chatName: String,
        messageText: String,
        createdAt: Date,
        status: PendingReplyStatus = .pending
    ) {
        self.chatId = chatId
        self.chatName = chatName
        self.messageText = messageText
        self.createdAt = createdAt
        self.status = status
    }
}

public enum PendingReplyStatus: String, Sendable, Equatable {
    case pending
    case sent
    case cancelled
    case expired
}

public enum TelegramIntegrationEvent: String, Sendable, Equatable {
    case telegramReplyDraftCreated = "telegram_reply_draft_created"
    case telegramReplySent = "telegram_reply_sent"
    case telegramReplyCancelled = "telegram_reply_cancelled"
    case telegramChatNotFound = "telegram_chat_not_found"
    case telegramPermissionMissing = "telegram_permission_missing"
}

public enum TelegramCommandResult: Sendable, Equatable {
    case handled(message: String, pendingReply: PendingTelegramReply?)
    case notTelegramCommand
}

