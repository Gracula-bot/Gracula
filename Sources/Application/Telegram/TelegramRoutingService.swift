import Foundation

public actor TelegramRoutingService: TelegramService, TelegramAuthenticatingService {
    private let automationService: any TelegramService
    private let userService: (any TelegramUserClienting)?
    private let businessService: TelegramBusinessBotService?
    private let businessConnectionId: String?

    public init(
        automationService: any TelegramService,
        userService: (any TelegramUserClienting)? = nil,
        businessService: TelegramBusinessBotService? = nil,
        businessConnectionId: String? = nil
    ) {
        self.automationService = automationService
        self.userService = userService
        self.businessService = businessService
        let trimmedBusinessConnectionId = businessConnectionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.businessConnectionId = (trimmedBusinessConnectionId?.isEmpty == false) ? trimmedBusinessConnectionId : nil
    }

    public func currentAuthorizationState() async -> TelegramUserAuthorizationState {
        guard let userService else {
            return .disabled
        }
        return await userService.currentAuthorizationState()
    }

    public func submitCode(_ code: String) async -> TelegramUserAuthorizationState {
        guard let userService else {
            return .disabled
        }
        return await userService.submitCode(code)
    }

    public func submitPassword(_ password: String) async -> TelegramUserAuthorizationState {
        guard let userService else {
            return .disabled
        }
        return await userService.submitPassword(password)
    }

    public func getLatestChat() async throws -> TelegramChat {
        if let userChatAndMessage = try await latestUserChatAndMessageIfAvailable() {
            return TelegramChat(
                id: Self.userChatID(userChatAndMessage.chat.id),
                displayName: userChatAndMessage.chat.title
            )
        }
        if let userChat = try await latestUserChatIfAvailable() {
            return TelegramChat(id: Self.userChatID(userChat.id), displayName: userChat.title)
        }
        if let businessMessage = try await latestBusinessMessageIfAvailable() {
            return TelegramChat(
                id: Self.businessChatID(
                    connectionId: businessMessage.businessConnectionId,
                    chatId: businessMessage.chat.id
                ),
                displayName: businessMessage.chat.displayName
            )
        }
        return try await automationService.getLatestChat()
    }

    public func findChat(byName name: String) async throws -> TelegramChat {
        if let userChat = try await findUserChatIfAvailable(name: name) {
            return TelegramChat(id: Self.userChatID(userChat.id), displayName: userChat.title)
        }
        if let businessMessage = try await findBusinessMessageIfAvailable(name: name) {
            return TelegramChat(
                id: Self.businessChatID(
                    connectionId: businessMessage.businessConnectionId,
                    chatId: businessMessage.chat.id
                ),
                displayName: businessMessage.chat.displayName
            )
        }
        return try await automationService.findChat(byName: name)
    }

    public func getLatestMessage(chatId: String) async throws -> TelegramMessage {
        switch Self.route(for: chatId) {
        case .user(let rawChatId):
            guard let userService else {
                throw TelegramCommandError.telegramNotConnected
            }
            try await ensureUserServiceReady(userService)
            guard let latest = try await userService.latestMessages(chatId: rawChatId, limit: 20).first else {
                throw TelegramCommandError.telegramAPIError("No Telegram messages were found in the selected chat.")
            }
            return latest

        case .business(let connectionId, let rawChatId):
            guard let latest = try await latestBusinessMessageIfAvailable(
                connectionId: connectionId,
                chatId: rawChatId
            ) else {
                throw TelegramCommandError.telegramAPIError("No Telegram Business messages were found in the selected chat.")
            }
            return TelegramMessage(
                id: String(latest.messageId),
                chatId: chatId,
                senderName: latest.senderName ?? latest.senderUsername,
                text: latest.text,
                date: latest.date
            )

        case .automation:
            return try await automationService.getLatestMessage(chatId: chatId)
        }
    }

    public func prepareReply(chatId: String, text: String) async throws -> PendingTelegramReply {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TelegramCommandError.emptyMessageText
        }

        switch Self.route(for: chatId) {
        case .user(let rawChatId):
            let chat = try await findUserChat(byID: rawChatId)
            return PendingTelegramReply(
                chatId: chatId,
                chatName: chat.title,
                messageText: trimmedText,
                createdAt: Date()
            )

        case .business(let connectionId, let rawChatId):
            guard let businessMessage = try await latestBusinessMessageIfAvailable(
                connectionId: connectionId,
                chatId: rawChatId
            ) else {
                throw TelegramCommandError.chatNotFound(rawChatId)
            }
            return PendingTelegramReply(
                chatId: chatId,
                chatName: businessMessage.chat.displayName,
                messageText: trimmedText,
                createdAt: Date()
            )

        case .automation:
            return try await automationService.prepareReply(chatId: chatId, text: trimmedText)
        }
    }

    public func sendReply(_ reply: PendingTelegramReply) async throws {
        switch Self.route(for: reply.chatId) {
        case .user(let rawChatId):
            guard let userService else {
                throw TelegramCommandError.telegramNotConnected
            }
            try await ensureUserServiceReady(userService)
            try await userService.sendMessage(chatId: rawChatId, text: reply.messageText)

        case .business(let connectionId, let rawChatId):
            guard let businessService, let numericChatId = Int64(rawChatId) else {
                throw TelegramCommandError.telegramNotConnected
            }
            try await businessService.sendMessage(
                businessConnectionId: connectionId,
                chatId: numericChatId,
                text: reply.messageText
            )

        case .automation:
            try await automationService.sendReply(reply)
        }
    }

    private func latestUserChatIfAvailable() async throws -> TelegramUserDialog? {
        guard let userService else {
            return nil
        }
        try await ensureUserServiceReady(userService)
        return try await userService.latestChat()
    }

    private func latestUserChatAndMessageIfAvailable() async throws -> (chat: TelegramUserDialog, message: TelegramMessage)? {
        guard let userService else {
            return nil
        }
        try await ensureUserServiceReady(userService)
        let dialogs = try await userService.dialogs(limit: 20)
        for dialog in dialogs {
            if let message = try await userService.latestMessages(chatId: dialog.id, limit: 20).first {
                return (dialog, message)
            }
        }
        return nil
    }

    private func findUserChatIfAvailable(name: String) async throws -> TelegramUserDialog? {
        guard let userService else {
            return nil
        }
        try await ensureUserServiceReady(userService)
        return try await userService.findChat(named: name)
    }

    private func findUserChat(byID id: String) async throws -> TelegramUserDialog {
        guard let userService else {
            throw TelegramCommandError.telegramNotConnected
        }
        try await ensureUserServiceReady(userService)
        let dialogs = try await userService.dialogs(limit: 200)
        guard let dialog = dialogs.first(where: { $0.id == id }) else {
            throw TelegramCommandError.chatNotFound(id)
        }
        return dialog
    }

    private func ensureUserServiceReady(_ userService: any TelegramUserClienting) async throws {
        let state = await userService.start()
        switch state {
        case .ready:
            return
        case .waitingForCode, .waitingForPassword, .waitingForPhoneNumber, .notConfigured, .libraryMissing, .failed:
            throw TelegramCommandError.telegramAPIError(state.displayText)
        case .disabled, .closed:
            throw TelegramCommandError.telegramNotConnected
        }
    }

    private func latestBusinessMessageIfAvailable() async throws -> TelegramBusinessIncomingMessage? {
        try await businessMessages().max(by: { $0.date < $1.date })
    }

    private func latestBusinessMessageIfAvailable(connectionId: String, chatId: String) async throws -> TelegramBusinessIncomingMessage? {
        try await businessMessages()
            .filter {
                $0.businessConnectionId == connectionId && String($0.chat.id) == chatId
            }
            .max(by: { $0.date < $1.date })
    }

    private func findBusinessMessageIfAvailable(name: String) async throws -> TelegramBusinessIncomingMessage? {
        let normalizedName = Self.normalize(name)
        return try await businessMessages()
            .filter { message in
                Self.normalize(message.chat.displayName) == normalizedName
                    || Self.normalize(message.chat.username ?? "") == normalizedName
            }
            .max(by: { $0.date < $1.date })
    }

    private func businessMessages() async throws -> [TelegramBusinessIncomingMessage] {
        guard let businessService else {
            return []
        }
        let updates = try await businessService.getUpdates(offset: nil)
        if let businessConnectionId {
            return updates.filter { $0.businessConnectionId == businessConnectionId }
        }
        return updates
    }

    private static func userChatID(_ id: String) -> String {
        "tg-user:\(id)"
    }

    private static func businessChatID(connectionId: String, chatId: Int64) -> String {
        "tg-business:\(connectionId):\(chatId)"
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func route(for chatId: String) -> TelegramRoute {
        if let rawChatId = chatId.split(separator: ":", maxSplits: 1).dropFirst().first,
           chatId.hasPrefix("tg-user:") {
            return .user(String(rawChatId))
        }
        if chatId.hasPrefix("tg-business:") {
            let parts = chatId.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count >= 4 {
                return .business(connectionId: String(parts[2]), chatId: String(parts[3]))
            }
        }
        return .automation
    }
}

private enum TelegramRoute {
    case user(String)
    case business(connectionId: String, chatId: String)
    case automation
}
