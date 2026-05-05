import Foundation

public actor TelegramUserTDLibClient: TelegramUserClienting {
    public private(set) var authorizationState: TelegramUserAuthorizationState = .disabled

    private let settings: TelegramUserSettings
    private let bridgeFactory: @Sendable (String?) throws -> any TDLibJSONBridge
    private var bridge: (any TDLibJSONBridge)?
    private var clientId: Int32?

    public init(
        settings: TelegramUserSettings,
        bridgeFactory: @escaping @Sendable (String?) throws -> any TDLibJSONBridge = { try DynamicTDLibJSONBridge(libraryPath: $0) }
    ) {
        self.settings = settings
        self.bridgeFactory = bridgeFactory
    }

    public func currentAuthorizationState() -> TelegramUserAuthorizationState {
        authorizationState
    }

    @discardableResult
    public func start() async -> TelegramUserAuthorizationState {
        if bridge != nil {
            return authorizationState
        }
        guard settings.enabled else {
            authorizationState = .disabled
            return authorizationState
        }
        guard settings.apiId > 0 else {
            authorizationState = .notConfigured("api_id is missing")
            return authorizationState
        }
        guard !settings.apiHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authorizationState = .notConfigured("api_hash is missing")
            return authorizationState
        }
        guard !settings.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authorizationState = .notConfigured("phone number is missing")
            return authorizationState
        }

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: settings.databaseDirectory, isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: settings.filesDirectory, isDirectory: true),
                withIntermediateDirectories: true
            )
            let bridge = try bridgeFactory(settings.tdjsonLibraryPath)
            self.bridge = bridge
            let clientId = bridge.createClientId()
            self.clientId = clientId
            _ = try bridge.execute([
                "@type": "setLogVerbosityLevel",
                "new_verbosity_level": 1
            ])
            return await pumpAuthorization(timeout: 10)
        } catch TDLibJSONBridgeError.libraryNotFound(let paths) {
            authorizationState = .libraryMissing(paths)
            return authorizationState
        } catch {
            authorizationState = .failed(error.localizedDescription)
            return authorizationState
        }
    }

    @discardableResult
    public func submitCode(_ code: String) async -> TelegramUserAuthorizationState {
        await submitAuthenticationRequest([
            "@type": "checkAuthenticationCode",
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
    }

    @discardableResult
    public func submitPassword(_ password: String) async -> TelegramUserAuthorizationState {
        await submitAuthenticationRequest([
            "@type": "checkAuthenticationPassword",
            "password": password
        ])
    }

    public func dialogs(limit: Int = 50) async throws -> [TelegramUserDialog] {
        try requireReady()
        guard let response = try await sendRequest([
            "@type": "getChats",
            "chat_list": ["@type": "chatListMain"],
            "limit": max(1, min(limit, 100))
        ], timeout: 10),
              let ids = response["chat_ids"] as? [Any] else {
            return []
        }

        var dialogs: [TelegramUserDialog] = []
        for rawId in ids {
            let id = Self.int64Value(rawId) ?? 0
            guard id != 0,
                  let chat = try await sendRequest([
                    "@type": "getChat",
                    "chat_id": id
                  ], timeout: 5) else {
                continue
            }
            let title = chat["title"] as? String ?? String(id)
            if !isAllowed(chatId: String(id), title: title) {
                continue
            }
            dialogs.append(
                TelegramUserDialog(
                    id: String(id),
                    title: title,
                    type: Self.chatTypeName(chat["type"])
                )
            )
        }
        return dialogs
    }

    public func latestChat() async throws -> TelegramUserDialog {
        guard let dialog = try await dialogs(limit: 1).first else {
            throw TelegramCommandError.telegramAPIError("No Telegram chats were found.")
        }
        return dialog
    }

    public func findChat(named name: String) async throws -> TelegramUserDialog {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TelegramCommandError.chatNotFound(name)
        }

        let normalizedName = Self.normalize(trimmedName)
        let dialogs = try await dialogs(limit: 200)
        let exactMatches = dialogs.filter { dialog in
            Self.normalize(dialog.title) == normalizedName
        }
        if exactMatches.count == 1, let match = exactMatches.first {
            return match
        }
        if exactMatches.count > 1 {
            throw TelegramCommandError.multipleMatchingChats(name)
        }

        let partialMatches = dialogs.filter { dialog in
            Self.normalize(dialog.title).contains(normalizedName)
        }
        if partialMatches.count == 1, let match = partialMatches.first {
            return match
        }
        if partialMatches.count > 1 {
            throw TelegramCommandError.multipleMatchingChats(name)
        }

        throw TelegramCommandError.chatNotFound(name)
    }

    public func latestMessages(chatId: String, limit: Int = 20) async throws -> [TelegramMessage] {
        try requireReady()
        guard isAllowed(chatId: chatId, title: nil), let numericChatId = Int64(chatId) else {
            throw TelegramCommandError.missingPermission("Telegram user chat allowlist")
        }

        guard let response = try await sendRequest([
            "@type": "getChatHistory",
            "chat_id": numericChatId,
            "from_message_id": 0,
            "offset": 0,
            "limit": max(1, min(limit, 100)),
            "only_local": false
        ], timeout: 10),
              let messages = response["messages"] as? [[String: Any]] else {
            return []
        }

        return messages.compactMap { object in
            guard let id = Self.int64Value(object["id"]),
                  let date = Self.intValue(object["date"]),
                  let content = object["content"] as? [String: Any],
                  let text = Self.messageText(content),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let senderName = Self.senderName(object["sender_id"], chat: object["sender"])
            return TelegramMessage(
                id: String(id),
                chatId: chatId,
                senderName: senderName,
                text: text,
                date: Date(timeIntervalSince1970: TimeInterval(date))
            )
        }
    }

    public func sendMessage(chatId: String, text: String) async throws {
        try requireReady()
        guard isAllowed(chatId: chatId, title: nil), let numericChatId = Int64(chatId) else {
            throw TelegramCommandError.missingPermission("Telegram user chat allowlist")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TelegramCommandError.emptyMessageText
        }

        _ = try await sendRequest([
            "@type": "sendMessage",
            "chat_id": numericChatId,
            "input_message_content": [
                "@type": "inputMessageText",
                "text": [
                    "@type": "formattedText",
                    "text": String(trimmed.prefix(4096))
                ]
            ]
        ], timeout: 10)
    }

    public func close() async {
        guard let bridge, let clientId else {
            authorizationState = .closed
            self.bridge = nil
            self.clientId = nil
            return
        }
        try? bridge.send(clientId: clientId, request: ["@type": "close"])
        _ = await pumpAuthorization(timeout: 2)
        authorizationState = .closed
        self.bridge = nil
        self.clientId = nil
    }

    private func submitAuthenticationRequest(_ request: [String: Any]) async -> TelegramUserAuthorizationState {
        guard let bridge, let clientId else {
            return await start()
        }
        do {
            try bridge.send(clientId: clientId, request: request)
            return await pumpAuthorization(timeout: 20)
        } catch {
            authorizationState = .failed(error.localizedDescription)
            return authorizationState
        }
    }

    private func pumpAuthorization(timeout: TimeInterval) async -> TelegramUserAuthorizationState {
        guard let bridge else {
            authorizationState = .failed("TDLib is not started.")
            return authorizationState
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let update = bridge.receive(timeout: 0.5) else {
                continue
            }
            if let error = Self.errorDescription(update) {
                if error.contains("Parameters aren't specified") {
                    continue
                }
                authorizationState = .failed(error)
                return authorizationState
            }
            if update["@type"] as? String == "updateAuthorizationState",
               let state = update["authorization_state"] as? [String: Any] {
                await handleAuthorizationState(state)
                if case .ready = authorizationState {
                    return authorizationState
                }
                if case .waitingForCode = authorizationState {
                    return authorizationState
                }
                if case .waitingForPassword = authorizationState {
                    return authorizationState
                }
                if case .failed = authorizationState {
                    return authorizationState
                }
            } else if let state = update["@type"] as? String, state.hasPrefix("authorizationState") {
                await handleAuthorizationState(update)
            }
        }
        return authorizationState
    }

    private func handleAuthorizationState(_ state: [String: Any]) async {
        guard let type = state["@type"] as? String else {
            return
        }
        do {
            switch type {
            case "authorizationStateWaitTdlibParameters":
                try sendTdlibParameters()
            case "authorizationStateWaitEncryptionKey":
                try send([
                    "@type": "checkDatabaseEncryptionKey",
                    "encryption_key": settings.encryptionKey
                ])
            case "authorizationStateWaitPhoneNumber":
                authorizationState = .waitingForPhoneNumber
                try send([
                    "@type": "setAuthenticationPhoneNumber",
                    "phone_number": settings.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                ])
            case "authorizationStateWaitCode":
                authorizationState = .waitingForCode
            case "authorizationStateWaitPassword":
                authorizationState = .waitingForPassword
            case "authorizationStateReady":
                authorizationState = .ready
            case "authorizationStateClosed", "authorizationStateClosing":
                authorizationState = .closed
            default:
                break
            }
        } catch {
            authorizationState = .failed(error.localizedDescription)
        }
    }

    private func sendTdlibParameters() throws {
        try send([
            "@type": "setTdlibParameters",
            "use_test_dc": false,
            "database_directory": settings.databaseDirectory,
            "files_directory": settings.filesDirectory,
            "database_encryption_key": settings.encryptionKey,
            "use_file_database": true,
            "use_chat_info_database": true,
            "use_message_database": true,
            "use_secret_chats": false,
            "api_id": settings.apiId,
            "api_hash": settings.apiHash,
            "system_language_code": Locale.current.language.languageCode?.identifier ?? "en",
            "device_model": "Mac",
            "system_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "application_version": "Gracula",
            "enable_storage_optimizer": true
        ])
    }

    private func send(_ request: [String: Any]) throws {
        guard let bridge, let clientId else {
            throw TelegramCommandError.telegramNotConnected
        }
        try bridge.send(clientId: clientId, request: request)
    }

    private func sendRequest(_ request: [String: Any], timeout: TimeInterval) async throws -> [String: Any]? {
        guard let bridge, let clientId else {
            throw TelegramCommandError.telegramNotConnected
        }
        let extra = UUID().uuidString
        var request = request
        request["@extra"] = extra
        try bridge.send(clientId: clientId, request: request)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let response = bridge.receive(timeout: 0.5) else {
                continue
            }
            if response["@extra"] as? String == extra {
                if let error = Self.errorDescription(response) {
                    throw TelegramCommandError.telegramAPIError(error)
                }
                return response
            }
            if response["@type"] as? String == "updateAuthorizationState",
               let state = response["authorization_state"] as? [String: Any] {
                await handleAuthorizationState(state)
            }
        }
        throw TelegramCommandError.telegramAPIError("TDLib request timed out.")
    }

    private func requireReady() throws {
        guard case .ready = authorizationState else {
            throw TelegramCommandError.telegramAPIError(authorizationState.displayText)
        }
    }

    private func isAllowed(chatId: String, title: String?) -> Bool {
        guard !settings.chatAllowlist.isEmpty else {
            return true
        }
        let normalizedTitle = title?.lowercased()
        return settings.chatAllowlist.contains { allowed in
            let normalized = allowed.lowercased()
            return normalized == chatId || normalizedTitle == normalized
        }
    }

    private static func errorDescription(_ object: [String: Any]) -> String? {
        guard object["@type"] as? String == "error" else {
            return nil
        }
        let code = intValue(object["code"]).map(String.init) ?? "unknown"
        let message = object["message"] as? String ?? "Unknown TDLib error"
        return "TDLib \(code): \(message)"
    }

    private static func chatTypeName(_ object: Any?) -> String {
        guard let object = object as? [String: Any],
              let type = object["@type"] as? String else {
            return "unknown"
        }
        return type.replacingOccurrences(of: "chatType", with: "").lowercased()
    }

    private static func messageText(_ content: [String: Any]) -> String? {
        guard content["@type"] as? String == "messageText",
              let formatted = content["text"] as? [String: Any],
              let text = formatted["text"] as? String else {
            return nil
        }
        return text
    }

    private static func senderName(_ object: Any?, chat: Any?) -> String? {
        if let chat = chat as? [String: Any], let title = chat["title"] as? String, !title.isEmpty {
            return title
        }
        guard let object = object as? [String: Any],
              let type = object["@type"] as? String else {
            return nil
        }
        if let userId = int64Value(object["user_id"]), type == "messageSenderUser" {
            return "user:\(userId)"
        }
        if let chatId = int64Value(object["chat_id"]), type == "messageSenderChat" {
            return "chat:\(chatId)"
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func int(_ value: Any) -> Int64 {
        int64Value(value) ?? 0
    }

    private static func int64Value(_ value: Any?) -> Int64? {
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

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }
}
