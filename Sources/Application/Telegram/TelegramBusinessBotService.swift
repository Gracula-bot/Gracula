import Foundation

public struct TelegramBusinessBotService: Sendable {
    public let botToken: String
    public let urlSession: URLSession

    public init(botToken: String, urlSession: URLSession = .shared) {
        self.botToken = botToken
        self.urlSession = urlSession
    }

    public func probeConnection() async throws {
        _ = try await post(method: "getMe", body: [:])
    }

    public func sendMessage(businessConnectionId: String, chatId: Int64, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TelegramCommandError.emptyMessageText
        }
        _ = try await post(
            method: "sendMessage",
            body: [
                "business_connection_id": businessConnectionId,
                "chat_id": chatId,
                "text": String(trimmed.prefix(4096))
            ]
        )
    }

    public func readBusinessMessage(businessConnectionId: String, chatId: Int64, messageId: Int) async throws {
        _ = try await post(
            method: "readBusinessMessage",
            body: [
                "business_connection_id": businessConnectionId,
                "chat_id": chatId,
                "message_id": messageId
            ]
        )
    }

    private func post(method: String, body: [String: Any]) async throws -> [String: Any] {
        let trimmedToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw TelegramCommandError.telegramAPIError("Telegram bot token is empty.")
        }
        guard let url = URL(string: "https://api.telegram.org/bot\(trimmedToken)/\(method)") else {
            throw TelegramCommandError.telegramAPIError("Invalid Telegram Bot API URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TelegramCommandError.telegramAPIError("Telegram returned a non-HTTP response.")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TelegramCommandError.telegramAPIError("Telegram returned invalid JSON.")
        }
        guard http.statusCode == 200, (root["ok"] as? Bool) == true else {
            let description = root["description"] as? String ?? "HTTP \(http.statusCode)"
            throw TelegramCommandError.telegramAPIError(description)
        }
        return root
    }
}
