import Foundation

public struct TelegramBusinessBotService: Sendable {
    public let botToken: String
    public let urlSession: URLSession

    public init(botToken: String, urlSession: URLSession = .shared) {
        self.botToken = botToken
        self.urlSession = urlSession
    }

    public func getUpdates(offset: Int?) async throws -> [TelegramBusinessIncomingMessage] {
        var body: [String: Any] = [
            "timeout": 20,
            "allowed_updates": ["business_connection", "business_message", "edited_business_message", "deleted_business_messages"]
        ]
        if let offset {
            body["offset"] = offset
        }
        let root = try await post(method: "getUpdates", body: body)
        guard let result = root["result"] as? [[String: Any]] else {
            return []
        }
        return result.compactMap(Self.incomingBusinessMessage)
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

    private static func incomingBusinessMessage(update: [String: Any]) -> TelegramBusinessIncomingMessage? {
        guard let updateId = update["update_id"] as? Int else {
            return nil
        }
        let message = (update["business_message"] as? [String: Any])
            ?? (update["edited_business_message"] as? [String: Any])
        guard let message,
              let businessConnectionId = message["business_connection_id"] as? String,
              let messageId = message["message_id"] as? Int,
              let chatObject = message["chat"] as? [String: Any],
              let chat = businessChat(from: chatObject),
              let text = message["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let sender = message["from"] as? [String: Any]
        return TelegramBusinessIncomingMessage(
            updateId: updateId,
            businessConnectionId: businessConnectionId,
            messageId: messageId,
            chat: chat,
            senderName: displayName(from: sender),
            senderUsername: sender?["username"] as? String,
            text: text,
            date: Date(timeIntervalSince1970: TimeInterval((message["date"] as? Int) ?? 0))
        )
    }

    private static func businessChat(from object: [String: Any]) -> TelegramBusinessChat? {
        guard let id = int64(object["id"]),
              let type = object["type"] as? String else {
            return nil
        }
        return TelegramBusinessChat(
            id: id,
            type: type,
            displayName: displayName(from: object) ?? "\(id)",
            username: object["username"] as? String
        )
    }

    private static func displayName(from object: [String: Any]?) -> String? {
        guard let object else {
            return nil
        }
        if let title = object["title"] as? String, !title.isEmpty {
            return title
        }
        let name = [
            object["first_name"] as? String,
            object["last_name"] as? String
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty {
            return name
        }
        return object["username"] as? String
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        if let value = value as? String {
            return Int64(value)
        }
        return nil
    }
}
