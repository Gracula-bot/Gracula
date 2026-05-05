import Foundation

public actor TelegramCommandHandler {
    private let service: any TelegramService
    private let store: PendingTelegramReplyStore
    private let parser: TelegramIntentParser
    private let eventSink: (@Sendable (TelegramIntegrationEvent) async -> Void)?

    public init(
        service: any TelegramService,
        store: PendingTelegramReplyStore = PendingTelegramReplyStore(),
        parser: TelegramIntentParser = TelegramIntentParser(),
        eventSink: (@Sendable (TelegramIntegrationEvent) async -> Void)? = nil
    ) {
        self.service = service
        self.store = store
        self.parser = parser
        self.eventSink = eventSink
    }

    public func handle(text: String, confidence: Double? = nil) async -> TelegramCommandResult {
        let intent = parser.parse(text: text, confidence: confidence)
        return await handle(intent)
    }

    public func handle(_ intent: TelegramIntent) async -> TelegramCommandResult {
        do {
            switch intent {
            case .readLatest:
                let chat = try await service.getLatestChat()
                let message = try await service.getLatestMessage(chatId: chat.id)
                let sender = message.senderName.map { "\($0): " } ?? ""
                return .handled(message: "Последнее сообщение в \(chat.displayName): \(sender)\(message.text)", pendingReply: await store.current())

            case .submitCode(let code):
                guard let authenticatingService = service as? any TelegramAuthenticatingService else {
                    throw TelegramCommandError.telegramAPIError("Telegram authorization is not available for the active backend.")
                }
                let state = await authenticatingService.submitCode(code)
                return .handled(message: state.displayText, pendingReply: await store.current())

            case .submitPassword(let password):
                guard let authenticatingService = service as? any TelegramAuthenticatingService else {
                    throw TelegramCommandError.telegramAPIError("Telegram authorization is not available for the active backend.")
                }
                let state = await authenticatingService.submitPassword(password)
                return .handled(message: state.displayText, pendingReply: await store.current())

            case .draftReply(let target, let messageText):
                let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedText.isEmpty else {
                    throw TelegramCommandError.emptyMessageText
                }

                let chat: TelegramChat
                switch target {
                case .latestChat:
                    chat = try await service.getLatestChat()
                case .chatName(let name):
                    chat = try await service.findChat(byName: name)
                }

                let reply = try await service.prepareReply(chatId: chat.id, text: trimmedText)
                try await service.sendReply(reply)
                await store.markSentAndClear()
                await eventSink?(.telegramReplySent)
                return .handled(message: "Отправлено в \(chat.displayName).", pendingReply: nil)

            case .confirmSend:
                var reply = try await store.requireSendableReply()
                reply = PendingTelegramReply(
                    chatId: reply.chatId,
                    chatName: reply.chatName,
                    messageText: reply.messageText,
                    createdAt: reply.createdAt,
                    status: .pending
                )
                try await service.sendReply(reply)
                await store.markSentAndClear()
                await eventSink?(.telegramReplySent)
                return .handled(message: "Отправлено.", pendingReply: nil)

            case .cancel:
                try await store.cancelAndClear()
                await eventSink?(.telegramReplyCancelled)
                return .handled(message: "Черновик удалён. Ничего не отправлено.", pendingReply: nil)

            case .lowConfidence:
                throw TelegramCommandError.lowSpeechConfidence

            case .unknown:
                return .notTelegramCommand
            }
        } catch {
            await recordTechnicalEvent(for: error)
            return .handled(message: error.localizedDescription, pendingReply: await store.current())
        }
    }

    public func currentPendingReply() async -> PendingTelegramReply? {
        await store.current()
    }

    private func recordTechnicalEvent(for error: any Error) async {
        if case TelegramCommandError.chatNotFound = error {
            await eventSink?(.telegramChatNotFound)
        } else if case TelegramCommandError.missingPermission = error {
            await eventSink?(.telegramPermissionMissing)
        }
    }
}
