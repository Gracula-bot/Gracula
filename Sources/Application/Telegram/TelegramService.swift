public protocol TelegramService: Sendable {
    func getLatestChat() async throws -> TelegramChat
    func findChat(byName name: String) async throws -> TelegramChat
    func getLatestMessage(chatId: String) async throws -> TelegramMessage
    func prepareReply(chatId: String, text: String) async throws -> PendingTelegramReply
    func sendReply(_ reply: PendingTelegramReply) async throws
}

public protocol TelegramManualHandoffService: TelegramService {
    var requiresManualSendAfterConfirmation: Bool { get }
}

public protocol TelegramAuthenticatingService: Sendable {
    func currentAuthorizationState() async -> TelegramUserAuthorizationState
    func submitCode(_ code: String) async -> TelegramUserAuthorizationState
    func submitPassword(_ password: String) async -> TelegramUserAuthorizationState
}

public protocol TelegramUserClienting: TelegramAuthenticatingService {
    @discardableResult
    func start() async -> TelegramUserAuthorizationState
    func dialogs(limit: Int) async throws -> [TelegramUserDialog]
    func latestMessages(chatId: String, limit: Int) async throws -> [TelegramMessage]
    func latestChat() async throws -> TelegramUserDialog
    func findChat(named name: String) async throws -> TelegramUserDialog
    func sendMessage(chatId: String, text: String) async throws
}
