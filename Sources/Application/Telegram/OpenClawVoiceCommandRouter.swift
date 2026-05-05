public actor OpenClawVoiceCommandRouter {
    private let telegramHandler: TelegramCommandHandler

    public init(telegramHandler: TelegramCommandHandler) {
        self.telegramHandler = telegramHandler
    }

    public func route(text: String, confidence: Double? = nil) async -> TelegramCommandResult {
        await telegramHandler.handle(text: text, confidence: confidence)
    }
}

