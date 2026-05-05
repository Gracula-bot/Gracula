import Foundation

public enum TelegramCommandError: Error, Sendable, Equatable, LocalizedError {
    case telegramNotInstalled
    case telegramNotRunning
    case telegramNotConnected
    case missingPermission(String)
    case chatNotFound(String)
    case multipleMatchingChats(String)
    case noPendingReply
    case pendingReplyExpired
    case lowSpeechConfidence
    case emptyMessageText
    case unsafeCurrentChat
    case telegramAPIError(String)

    public var errorDescription: String? {
        switch self {
        case .telegramNotInstalled:
            return "Telegram is not installed."
        case .telegramNotRunning:
            return "Telegram is not running."
        case .telegramNotConnected:
            return "Telegram is not connected."
        case .missingPermission(let permission):
            return "Missing macOS permission: \(permission)."
        case .chatNotFound(let name):
            return "Telegram chat was not found: \(name)."
        case .multipleMatchingChats(let name):
            return "Several Telegram chats match \(name). Open the right chat manually or use a more specific name."
        case .noPendingReply:
            return "No Telegram reply draft is waiting for confirmation."
        case .pendingReplyExpired:
            return "Telegram reply draft expired. Dictate the reply again."
        case .lowSpeechConfidence:
            return "Speech recognition confidence is low. Please repeat the command."
        case .emptyMessageText:
            return "Telegram reply text is empty. Dictate the message text."
        case .unsafeCurrentChat:
            return "Cannot safely determine the Telegram chat. Open the right chat manually."
        case .telegramAPIError(let message):
            return "Telegram integration failed: \(message)"
        }
    }
}
