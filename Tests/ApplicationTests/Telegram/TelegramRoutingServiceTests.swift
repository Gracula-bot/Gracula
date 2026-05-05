import Application
import Foundation
import Testing

@Test
func routingServicePrefersTDLibForReadingAndSending() async throws {
    let automation = FakeAutomationTelegramService()
    let userService = FakeTelegramUserClient()
    let routingService = TelegramRoutingService(
        automationService: automation,
        userService: userService
    )

    let latestChat = try await routingService.getLatestChat()
    #expect(latestChat.id == "tg-user:101")
    #expect(latestChat.displayName == "Anton")

    let message = try await routingService.getLatestMessage(chatId: latestChat.id)
    #expect(message.text == "Privet")

    let reply = try await routingService.prepareReply(chatId: latestChat.id, text: "Budu cherez 10 minut")
    try await routingService.sendReply(reply)

    let sentMessages = await userService.sentMessages
    #expect(sentMessages.count == 1)
    #expect(sentMessages.first?.0 == "101")
    #expect(sentMessages.first?.1 == "Budu cherez 10 minut")
    #expect(await automation.sentReplies.isEmpty)
}

@Test
func routingServiceFallsBackToAutomationWhenTDLibIsUnavailable() async throws {
    let automation = FakeAutomationTelegramService()
    let routingService = TelegramRoutingService(automationService: automation)

    let chat = try await routingService.findChat(byName: "Anton")
    #expect(chat.id == "automation-anton")

    let reply = try await routingService.prepareReply(chatId: chat.id, text: "Privet")
    try await routingService.sendReply(reply)

    #expect(await automation.sentReplies.map(\.chatId) == ["automation-anton"])
}

private actor FakeAutomationTelegramService: TelegramService {
    var sentReplies: [PendingTelegramReply] = []

    func getLatestChat() async throws -> TelegramChat {
        TelegramChat(id: "automation-latest", displayName: "Automation latest")
    }

    func findChat(byName name: String) async throws -> TelegramChat {
        TelegramChat(id: "automation-\(name.lowercased())", displayName: name)
    }

    func getLatestMessage(chatId: String) async throws -> TelegramMessage {
        TelegramMessage(
            id: "automation-message",
            chatId: chatId,
            senderName: "Automation",
            text: "Fallback",
            date: Date()
        )
    }

    func prepareReply(chatId: String, text: String) async throws -> PendingTelegramReply {
        PendingTelegramReply(
            chatId: chatId,
            chatName: chatId,
            messageText: text,
            createdAt: Date()
        )
    }

    func sendReply(_ reply: PendingTelegramReply) async throws {
        sentReplies.append(reply)
    }
}

private actor FakeTelegramUserClient: TelegramUserClienting {
    private(set) var sentMessages: [(String, String)] = []

    func currentAuthorizationState() async -> TelegramUserAuthorizationState {
        .ready
    }

    func submitCode(_ code: String) async -> TelegramUserAuthorizationState {
        .ready
    }

    func submitPassword(_ password: String) async -> TelegramUserAuthorizationState {
        .ready
    }

    func start() async -> TelegramUserAuthorizationState {
        .ready
    }

    func dialogs(limit: Int) async throws -> [TelegramUserDialog] {
        [TelegramUserDialog(id: "101", title: "Anton", type: "private")]
    }

    func latestMessages(chatId: String, limit: Int) async throws -> [TelegramMessage] {
        [
            TelegramMessage(
                id: "501",
                chatId: chatId,
                senderName: "Anton",
                text: "Privet",
                date: Date(timeIntervalSince1970: 100)
            )
        ]
    }

    func latestChat() async throws -> TelegramUserDialog {
        TelegramUserDialog(id: "101", title: "Anton", type: "private")
    }

    func findChat(named name: String) async throws -> TelegramUserDialog {
        TelegramUserDialog(id: "101", title: name, type: "private")
    }

    func sendMessage(chatId: String, text: String) async throws {
        sentMessages.append((chatId, text))
    }
}
