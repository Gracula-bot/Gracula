import Foundation

public struct TelegramIntentParser: Sendable {
    public let minimumConfidence: Double

    public init(minimumConfidence: Double = 0.62) {
        self.minimumConfidence = minimumConfidence
    }

    public func parse(text: String, confidence: Double? = nil) -> TelegramIntent {
        if let confidence, confidence < minimumConfidence {
            return .lowConfidence
        }

        let cleaned = stripWakeWord(from: text)
        let normalized = normalize(cleaned)

        if isConfirm(normalized) {
            return .confirmSend
        }

        if isCancel(normalized) {
            return .cancel
        }

        if isReadLatest(normalized) {
            return .readLatest
        }

        if let code = parseAuthValue(normalized: normalized, original: cleaned, kind: .code) {
            return .submitCode(code)
        }

        if let password = parseAuthValue(normalized: normalized, original: cleaned, kind: .password) {
            return .submitPassword(password)
        }

        if let draft = parseDraft(cleaned: cleaned, normalized: normalized) {
            return draft
        }

        if hasTelegramMention(normalized) {
            return .readLatest
        }

        return .unknown
    }

    private func parseDraft(cleaned: String, normalized: String) -> TelegramIntent? {
        guard normalized.contains("telegram") || normalized.contains("телеграм") else {
            return nil
        }
        guard normalized.contains("ответь") || normalized.contains("напиши") || normalized.contains("отправь") else {
            return nil
        }

        let split = splitCommandAndMessage(cleaned)
        let prefix = normalize(split.prefix)
        let messageText = split.messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: TelegramReplyTarget

        if prefix.contains("последнем чате") || prefix.contains("последний чат") {
            target = .latestChat
        } else if let recipient = recipientName(from: split.prefix) {
            target = .chatName(recipient)
        } else {
            target = .latestChat
        }

        return .draftReply(target: target, messageText: messageText)
    }

    private func splitCommandAndMessage(_ text: String) -> (prefix: String, messageText: String) {
        if let range = text.range(of: ":") {
            return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
        }

        let markers = [
            "ответь в Telegram",
            "ответь в телеграм",
            "напиши в Telegram",
            "напиши в телеграм",
            "отправь в Telegram",
            "отправь в телеграм",
            "ответь",
            "напиши",
            "отправь"
        ]

        for marker in markers {
            if let range = text.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) {
                let suffix = String(text[range.upperBound...])
                return (String(text[..<range.upperBound]), suffix)
            }
        }

        return (text, "")
    }

    private func recipientName(from prefix: String) -> String? {
        let tokens = prefix
            .replacingOccurrences(of: ":", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return nil
        }

        if let username = tokens.first(where: { $0.hasPrefix("@") }) {
            return username
        }

        let lowerTokens = tokens.map { normalize($0) }
        if let telegramIndex = lowerTokens.firstIndex(where: { $0 == "telegram" || $0 == "телеграм" }) {
            let candidate = tokens.dropFirst(telegramIndex + 1)
                .filter { token in
                    let normalized = normalize(token)
                    return normalized != "в" && normalized != "чате" && normalized != "последнем" && normalized != "последний"
                }
                .joined(separator: " ")
            return normalizedRecipient(candidate)
        }

        if let replyIndex = lowerTokens.firstIndex(where: { $0 == "ответь" || $0 == "напиши" || $0 == "отправь" }) {
            let candidate = tokens.dropFirst(replyIndex + 1)
                .prefix { token in
                    let normalized = normalize(token)
                    return normalized != "в" && normalized != "telegram" && normalized != "телеграм"
                }
                .joined(separator: " ")
            return normalizedRecipient(candidate)
        }

        return nil
    }

    private func normalizedRecipient(_ value: String) -> String? {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.count > 3, trimmed.lowercased().hasSuffix("у"), !trimmed.hasPrefix("@") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func isReadLatest(_ normalized: String) -> Bool {
        let phrases = [
            "прочитай последнее сообщение в telegram",
            "прочитай последнее сообщение в телеграм",
            "что мне написали в telegram",
            "что мне написали в телеграм",
            "прочитай последний чат"
        ]
        if phrases.contains(where: { normalized.contains($0) }) {
            return true
        }

        guard normalized.contains("telegram") || normalized.contains("телеграм") else {
            return false
        }

        let hasReadCue = [
            "прочитай",
            "покажи",
            "какие",
            "какое",
            "какой",
            "что",
            "видишь"
        ].contains(where: { normalized.contains($0) })
        let hasLatestCue = normalized.contains("последн") || normalized.contains("нов")
        let hasMessageCue = [
            "сообщени",
            "написал",
            "написали"
        ].contains(where: { normalized.contains($0) })

        return hasReadCue && hasLatestCue && hasMessageCue
    }

    private func hasTelegramMention(_ normalized: String) -> Bool {
        normalized.contains("telegram") || normalized.contains("телеграм")
    }

    private func isConfirm(_ normalized: String) -> Bool {
        ["отправь", "да отправь", "подтверждаю", "отправляй"].contains(normalized)
    }

    private func isCancel(_ normalized: String) -> Bool {
        ["отмени", "не отправляй", "удали черновик", "стоп"].contains(normalized)
    }

    private func parseAuthValue(normalized: String, original: String, kind: AuthValueKind) -> String? {
        guard hasTelegramMention(normalized) else {
            return nil
        }

        let markers = kind.markers
        for marker in markers {
            guard let range = original.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            let suffix = original[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !suffix.isEmpty {
                return suffix
            }
        }

        return nil
    }

    private func stripWakeWord(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wakeWords = ["OpenClaw", "Опенкло", "Опенклав", "Gracula"]
        for wakeWord in wakeWords {
            if cleaned.range(of: wakeWord, options: [.caseInsensitive, .diacriticInsensitive], range: cleaned.startIndex..<cleaned.endIndex) == cleaned.startIndex..<cleaned.index(cleaned.startIndex, offsetBy: min(wakeWord.count, cleaned.count)) {
                cleaned.removeFirst(min(wakeWord.count, cleaned.count))
                cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                break
            }
        }
        return cleaned
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

public enum TelegramIntent: Sendable, Equatable {
    case readLatest
    case draftReply(target: TelegramReplyTarget, messageText: String)
    case submitCode(String)
    case submitPassword(String)
    case confirmSend
    case cancel
    case lowConfidence
    case unknown
}

public enum TelegramReplyTarget: Sendable, Equatable {
    case latestChat
    case chatName(String)
}

public struct VoiceCommandParser: Sendable {
    private let telegramParser: TelegramIntentParser

    public init(telegramParser: TelegramIntentParser = TelegramIntentParser()) {
        self.telegramParser = telegramParser
    }

    public func parseTelegramIntent(text: String, confidence: Double? = nil) -> TelegramIntent {
        telegramParser.parse(text: text, confidence: confidence)
    }
}

private enum AuthValueKind {
    case code
    case password

    var markers: [String] {
        switch self {
        case .code:
            [
                "код telegram",
                "код телеграм",
                "код для telegram",
                "код для телеграм",
                "введи код telegram",
                "введи код телеграм"
            ]
        case .password:
            [
                "пароль telegram",
                "пароль телеграм",
                "введи пароль telegram",
                "введи пароль телеграм"
            ]
        }
    }
}
