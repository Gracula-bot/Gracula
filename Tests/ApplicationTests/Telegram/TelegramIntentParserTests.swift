import Application
import Testing

@Test
func parsesReplyToNamedTelegramChat() {
    let parser = TelegramIntentParser()

    let intent = parser.parse(text: "OpenClaw, ответь в Telegram Антону: буду через 10 минут")

    #expect(intent == .draftReply(target: .chatName("Антон"), messageText: "буду через 10 минут"))
}

@Test
func parsesSendMessageToNamedTelegramChat() {
    let parser = TelegramIntentParser()

    let intent = parser.parse(text: "отправь в Telegram Антону: буду через 10 минут")

    #expect(intent == .draftReply(target: .chatName("Антон"), messageText: "буду через 10 минут"))
}

@Test
func ignoresPrepareReplyCommand() {
    let parser = TelegramIntentParser()

    let intent = parser.parse(text: "подготовь ответ в Telegram Антону: буду через 10 минут")

    #expect(intent == .unknown)
}

@Test
func parsesReplyToLatestTelegramChat() {
    let parser = TelegramIntentParser()

    let intent = parser.parse(text: "ответь в последнем чате Telegram: сейчас занят")

    #expect(intent == .draftReply(target: .latestChat, messageText: "сейчас занят"))
}

@Test
func parsesSendConfirmation() {
    let parser = TelegramIntentParser()

    #expect(parser.parse(text: "отправь") == .confirmSend)
    #expect(parser.parse(text: "да, отправь") == .confirmSend)
}

@Test
func parsesCancelCommand() {
    let parser = TelegramIntentParser()

    #expect(parser.parse(text: "отмени") == .cancel)
    #expect(parser.parse(text: "не отправляй") == .cancel)
}

@Test
func parsesTelegramAuthorizationCode() {
    let parser = TelegramIntentParser()

    #expect(parser.parse(text: "введи код телеграм 12345") == .submitCode("12345"))
}

@Test
func parsesTelegramAuthorizationPassword() {
    let parser = TelegramIntentParser()

    #expect(parser.parse(text: "пароль telegram my-2fa-pass") == .submitPassword("my-2fa-pass"))
}

@Test
func rejectsLowSpeechConfidence() {
    let parser = TelegramIntentParser(minimumConfidence: 0.7)

    #expect(parser.parse(text: "ответь в Telegram Антону: буду через 10 минут", confidence: 0.4) == .lowConfidence)
}
