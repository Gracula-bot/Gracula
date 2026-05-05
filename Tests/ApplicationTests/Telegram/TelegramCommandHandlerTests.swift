import Application
import Foundation
import Testing

@Test
func sendsReplyCommandImmediately() async {
    let service = MockTelegramService()
    await service.setChat(TelegramChat(id: "anton", displayName: "Антон"), forName: "Антон")
    let handler = TelegramCommandHandler(service: service)

    let result = await handler.handle(text: "ответь в Telegram Антону: буду через 10 минут")

    #expect(result == .handled(message: "Отправлено в Антон.", pendingReply: nil))
    #expect(await service.sentReplies.map(\.messageText) == ["буду через 10 минут"])
    #expect(await handler.currentPendingReply() == nil)
}

@Test
func confirmSendWithoutPendingReplyIsRejected() async {
    let service = MockTelegramService()
    await service.setChat(TelegramChat(id: "anton", displayName: "Антон"), forName: "Антон")
    let handler = TelegramCommandHandler(service: service)

    let result = await handler.handle(text: "отправь")

    guard case .handled(let message, nil) = result else {
        Issue.record("Expected handled error for missing pending reply")
        return
    }
    #expect(message.contains("No Telegram reply draft"))
    #expect(await service.sentReplies.isEmpty)
    #expect(await handler.currentPendingReply() == nil)
}

@Test
func cancelsPendingReply() async {
    let service = MockTelegramService()
    await service.setLatestChat(TelegramChat(id: "latest", displayName: "Последний чат"))
    let handler = TelegramCommandHandler(service: service)

    let result = await handler.handle(text: "отмени")

    guard case .handled(let message, nil) = result else {
        Issue.record("Expected handled error for missing pending reply")
        return
    }
    #expect(message.contains("No Telegram reply draft"))
    #expect(await service.sentReplies.isEmpty)
    #expect(await handler.currentPendingReply() == nil)
}

@Test
func pendingReplyExpiresAfterTTL() async throws {
    let now = Date()
    let store = PendingTelegramReplyStore(ttl: 120, clock: { now })
    let reply = PendingTelegramReply(
        chatId: "chat",
        chatName: "Chat",
        messageText: "text",
        createdAt: now.addingTimeInterval(-121)
    )
    await store.save(reply)

    do {
        _ = try await store.requireSendableReply()
        Issue.record("Expected pending reply expiration")
    } catch TelegramCommandError.pendingReplyExpired {
        #expect(await store.current()?.status == nil)
    }
}

@Test
func refusesSendWithoutPendingReply() async {
    let service = MockTelegramService()
    let handler = TelegramCommandHandler(service: service)

    let result = await handler.handle(text: "отправь")

    guard case .handled(let message, nil) = result else {
        Issue.record("Expected handled error for missing pending reply")
        return
    }
    #expect(message.contains("No Telegram reply draft"))
    #expect(await service.sentReplies.isEmpty)
}

@Test
func handlesChatNotFound() async {
    let service = MockTelegramService()
    let handler = TelegramCommandHandler(service: service)

    let result = await handler.handle(text: "ответь в Telegram Антону: буду через 10 минут")

    guard case .handled(let message, nil) = result else {
        Issue.record("Expected handled chat-not-found error")
        return
    }
    #expect(message.contains("Антон"))
    #expect(await service.sentReplies.isEmpty)
}

@Test
func submitsTelegramAuthorizationCodeThroughAuthenticatingBackend() async {
    let service = MockTelegramService()
    let handler = TelegramCommandHandler(service: service)

    let result = await handler.handle(text: "код telegram 24680")

    guard case .handled(let message, nil) = result else {
        Issue.record("Expected handled result for Telegram code submission")
        return
    }
    #expect(message.contains("authorized"))
    #expect(await service.lastSubmittedCode == "24680")
}

private actor MockTelegramService: TelegramService {
    var latestChat = TelegramChat(id: "latest", displayName: "Последний чат")
    var chatsByName: [String: TelegramChat] = [:]
    var sentReplies: [PendingTelegramReply] = []
    var lastSubmittedCode: String?

    func setChat(_ chat: TelegramChat, forName name: String) {
        chatsByName[name] = chat
    }

    func setLatestChat(_ chat: TelegramChat) {
        latestChat = chat
    }

    func getLatestChat() async throws -> TelegramChat {
        latestChat
    }

    func findChat(byName name: String) async throws -> TelegramChat {
        guard let chat = chatsByName[name] else {
            throw TelegramCommandError.chatNotFound(name)
        }
        return chat
    }

    func getLatestMessage(chatId: String) async throws -> TelegramMessage {
        TelegramMessage(
            id: "message",
            chatId: chatId,
            senderName: "Антон",
            text: "Привет",
            date: Date(timeIntervalSince1970: 100)
        )
    }

    func prepareReply(chatId: String, text: String) async throws -> PendingTelegramReply {
        let chatName = chatsByName.values.first(where: { $0.id == chatId })?.displayName ?? latestChat.displayName
        return PendingTelegramReply(
            chatId: chatId,
            chatName: chatName,
            messageText: text,
            createdAt: Date()
        )
    }

    func sendReply(_ reply: PendingTelegramReply) async throws {
        sentReplies.append(reply)
    }
}

extension MockTelegramService: TelegramAuthenticatingService {
    func currentAuthorizationState() async -> TelegramUserAuthorizationState {
        .waitingForCode
    }

    func submitCode(_ code: String) async -> TelegramUserAuthorizationState {
        lastSubmittedCode = code
        return .ready
    }

    func submitPassword(_ password: String) async -> TelegramUserAuthorizationState {
        .ready
    }
}
