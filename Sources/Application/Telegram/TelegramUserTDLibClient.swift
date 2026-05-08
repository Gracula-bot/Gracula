import Foundation

public actor TelegramUserTDLibClient: TelegramUserClienting {
    public private(set) var authorizationState: TelegramUserAuthorizationState = .disabled

    private let settings: TelegramUserSettings
    private let bridgeFactory: @Sendable (String?) throws -> any TDLibJSONBridge
    private let diagnosticSink: @Sendable (String) -> Void
    private var bridge: (any TDLibJSONBridge)?
    private var clientId: Int32?
    private var lastAuthorizationStateType: String?
    private var lastTDLibErrorDescription: String?
    private var didSubmitTDLibParameters = false
    private var didSubmitEncryptionKey = false
    private var didSubmitPhoneNumber = false
    private var didExtendAuthorizationTimeoutAfterPhoneSubmission = false

    public init(
        settings: TelegramUserSettings,
        bridgeFactory: @escaping @Sendable (String?) throws -> any TDLibJSONBridge = { try DynamicTDLibJSONBridge(libraryPath: $0) },
        diagnosticSink: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.settings = settings
        self.bridgeFactory = bridgeFactory
        self.diagnosticSink = diagnosticSink
    }

    public func currentAuthorizationState() -> TelegramUserAuthorizationState {
        authorizationState
    }

    @discardableResult
    public func start() async -> TelegramUserAuthorizationState {
        emitDiagnostic(
            "start requested; api_id=\(settings.apiId); phone=\(Self.maskedPhoneNumber(settings.phoneNumber)); " +
            "db=\(settings.databaseDirectory); files=\(settings.filesDirectory); " +
            "tdjson=\(settings.tdjsonLibraryPath ?? "auto"); encryption_key_present=\(!settings.encryptionKey.isEmpty)"
        )
        if bridge != nil {
            if case .closed = authorizationState {
                emitDiagnostic("existing TDLib session is closed; resetting connection state before restart")
                resetConnectionState()
            } else {
                emitDiagnostic("start skipped because TDLib session already exists with state=\(authorizationState.displayText)")
                return authorizationState
            }
        }
        guard bridge == nil else {
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
            emitDiagnostic("TDLib bridge loaded successfully; client_id=\(clientId)")
            _ = try bridge.execute([
                "@type": "setLogVerbosityLevel",
                "new_verbosity_level": 1
            ])
            didSubmitTDLibParameters = true
            emitDiagnostic("bootstrapping TDLib parameters immediately after client creation")
            try sendTdlibParameters()
            return await pumpAuthorization(timeout: 10)
        } catch TDLibJSONBridgeError.libraryNotFound(let paths) {
            emitDiagnostic("TDLib library not found. Checked paths: \(paths.joined(separator: ", "))")
            authorizationState = .libraryMissing(paths)
            return authorizationState
        } catch {
            emitDiagnostic("TDLib start failed: \(error.localizedDescription)")
            authorizationState = .failed(error.localizedDescription)
            return authorizationState
        }
    }

    @discardableResult
    public func submitCode(_ code: String) async -> TelegramUserAuthorizationState {
        if case .waitingForPassword = authorizationState {
            let message = "Telegram is waiting for the 2FA password, not a login code."
            emitDiagnostic("rejected authentication request: \(message)")
            authorizationState = .failed(message)
            return authorizationState
        }
        return await submitAuthenticationRequest([
            "@type": "checkAuthenticationCode",
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
    }

    @discardableResult
    public func submitPassword(_ password: String) async -> TelegramUserAuthorizationState {
        if case .waitingForCode = authorizationState {
            let message = "Telegram is waiting for the login code, not the 2FA password."
            emitDiagnostic("rejected authentication request: \(message)")
            authorizationState = .failed(message)
            return authorizationState
        }
        return await submitAuthenticationRequest([
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
        emitDiagnostic("closing TDLib session; client_id=\(clientId)")
        try? bridge.send(clientId: clientId, request: ["@type": "close"])
        _ = await pumpAuthorization(timeout: 2)
        authorizationState = .closed
        self.bridge = nil
        self.clientId = nil
    }

    private func submitAuthenticationRequest(_ request: [String: Any]) async -> TelegramUserAuthorizationState {
        guard let bridge, let clientId else {
            emitDiagnostic("authentication request received before TDLib start; starting session first")
            return await start()
        }
        do {
            emitDiagnostic("sending authentication request: \(Self.requestSummary(request))")
            try bridge.send(clientId: clientId, request: request)
            return await pumpAuthorization(timeout: 20)
        } catch {
            emitDiagnostic("authentication request failed: \(error.localizedDescription)")
            authorizationState = .failed(error.localizedDescription)
            return authorizationState
        }
    }

    private func pumpAuthorization(timeout: TimeInterval) async -> TelegramUserAuthorizationState {
        guard let bridge else {
            authorizationState = .failed("TDLib is not started.")
            emitDiagnostic("authorization pump failed because TDLib bridge is not started")
            return authorizationState
        }
        emitDiagnostic("authorization pump started; timeout=\(Int(timeout))s")
        var deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let update = bridge.receive(timeout: 0.5) else {
                continue
            }
            if shouldIgnore(update: update) {
                continue
            }
            emitDiagnostic("received TDLib update: \(Self.updateSummary(update))")
            if let error = Self.errorDescription(update) {
                lastTDLibErrorDescription = error
                if error.contains("Parameters aren't specified") {
                    let context =
                        didSubmitTDLibParameters
                        ? "after TDLib parameters were already submitted"
                        : "before TDLib parameters are submitted"
                    emitDiagnostic("ignoring transient TDLib error \(context): \(error)")
                    continue
                }
                if error.contains("PASSWORD_HASH_INVALID") {
                    let message = "Telegram rejected the 2FA password. Enter the correct Telegram password."
                    emitDiagnostic("authorization pump failed with invalid 2FA password")
                    authorizationState = .failed(message)
                    return authorizationState
                }
                emitDiagnostic("authorization pump failed with TDLib error: \(error)")
                authorizationState = .failed(error)
                return authorizationState
            }
            if update["@type"] as? String == "updateAuthorizationState",
               let state = update["authorization_state"] as? [String: Any] {
                await handleAuthorizationState(state)
                if lastAuthorizationStateType == "authorizationStateWaitPhoneNumber",
                   didSubmitPhoneNumber,
                   !didExtendAuthorizationTimeoutAfterPhoneSubmission {
                    didExtendAuthorizationTimeoutAfterPhoneSubmission = true
                    deadline = max(deadline, Date().addingTimeInterval(60))
                    emitDiagnostic("phone number accepted locally; extending authorization wait by 60s for Telegram code delivery")
                }
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
                if lastAuthorizationStateType == "authorizationStateWaitPhoneNumber",
                   didSubmitPhoneNumber,
                   !didExtendAuthorizationTimeoutAfterPhoneSubmission {
                    didExtendAuthorizationTimeoutAfterPhoneSubmission = true
                    deadline = max(deadline, Date().addingTimeInterval(60))
                    emitDiagnostic("phone number accepted locally; extending authorization wait by 60s for Telegram code delivery")
                }
            }
        }
        emitDiagnostic(
            "authorization pump timed out after \(Int(timeout))s; last_state=\(lastAuthorizationStateType ?? "unknown"); " +
            "last_error=\(lastTDLibErrorDescription ?? "none")"
        )
        return authorizationState
    }

    private func handleAuthorizationState(_ state: [String: Any]) async {
        guard let type = state["@type"] as? String else {
            return
        }
        let previousState = lastAuthorizationStateType
        lastAuthorizationStateType = type
        emitDiagnostic("authorization state -> \(type)")
        do {
            switch type {
            case "authorizationStateWaitTdlibParameters":
                if didSubmitTDLibParameters {
                    emitDiagnostic("TDLib parameters already submitted for current session; skipping duplicate submission")
                } else {
                    didSubmitTDLibParameters = true
                    emitDiagnostic("submitting TDLib parameters")
                    try sendTdlibParameters()
                }
            case "authorizationStateWaitEncryptionKey":
                if didSubmitEncryptionKey {
                    emitDiagnostic("database encryption key already submitted for current session; skipping duplicate submission")
                } else {
                    didSubmitEncryptionKey = true
                    emitDiagnostic("submitting database encryption key; present=\(!settings.encryptionKey.isEmpty)")
                    try send([
                        "@type": "checkDatabaseEncryptionKey",
                        "encryption_key": settings.encryptionKey
                    ])
                }
            case "authorizationStateWaitPhoneNumber":
                authorizationState = .waitingForPhoneNumber
                if didSubmitPhoneNumber {
                    emitDiagnostic("phone number already submitted for current session; skipping duplicate submission")
                } else {
                    didSubmitPhoneNumber = true
                    emitDiagnostic("submitting phone number \(Self.maskedPhoneNumber(settings.phoneNumber))")
                    try send([
                        "@type": "setAuthenticationPhoneNumber",
                        "phone_number": settings.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                    ])
                }
            case "authorizationStateWaitCode":
                authorizationState = .waitingForCode
                emitDiagnostic("Telegram requested login code")
            case "authorizationStateWaitPassword":
                authorizationState = .waitingForPassword
                emitDiagnostic("Telegram requested 2FA password")
            case "authorizationStateReady":
                authorizationState = .ready
                emitDiagnostic("Telegram user authorization completed successfully")
            case "authorizationStateClosed", "authorizationStateClosing":
                let lastError = lastTDLibErrorDescription ?? "none"
                if lastError.contains("UPDATE_APP_TO_LOGIN") {
                    authorizationState = .failed(
                        "Telegram rejected login because TDLib is too old for login. " +
                        "Update libtdjson and try again."
                    )
                } else if lastError.contains("PASSWORD_HASH_INVALID") {
                    authorizationState = .failed(
                        "Telegram rejected the 2FA password. Enter the correct Telegram password."
                    )
                } else {
                    authorizationState = .closed
                }
                emitDiagnostic(
                    "TDLib session closed; previous_state=\(previousState ?? "unknown"); " +
                    "last_error=\(lastError)"
                )
                resetConnectionState()
            default:
                emitDiagnostic("authorization state \(type) is not explicitly handled")
                break
            }
        } catch {
            emitDiagnostic("failed while handling \(type): \(error.localizedDescription)")
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
            if shouldIgnore(update: response) {
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

    private func resetConnectionState() {
        emitDiagnostic("resetting TDLib connection state")
        bridge = nil
        clientId = nil
        didSubmitTDLibParameters = false
        didSubmitEncryptionKey = false
        didSubmitPhoneNumber = false
        didExtendAuthorizationTimeoutAfterPhoneSubmission = false
    }

    private func shouldIgnore(update: [String: Any]) -> Bool {
        guard let clientId else {
            return false
        }
        guard let updateClientId = Self.int32Value(update["@client_id"]) else {
            return false
        }
        guard updateClientId != clientId else {
            return false
        }
        emitDiagnostic("ignoring TDLib update for foreign client_id=\(updateClientId); current_client_id=\(clientId)")
        return true
    }

    private func emitDiagnostic(_ message: String) {
        diagnosticSink(message)
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

    private static func updateSummary(_ object: [String: Any]) -> String {
        let type = object["@type"] as? String ?? "unknown"
        if type == "updateAuthorizationState",
           let state = object["authorization_state"] as? [String: Any],
           let stateType = state["@type"] as? String {
            return "\(type) -> \(stateType)"
        }
        if type == "updateOption",
           let name = object["name"] as? String,
           name == "version",
           let value = object["value"] as? [String: Any],
           let optionType = value["@type"] as? String,
           optionType == "optionValueString",
           let version = value["value"] as? String {
            return "\(type) version=\(version)"
        }
        if type == "error" {
            return errorDescription(object) ?? "error"
        }
        return type
    }

    private static func requestSummary(_ request: [String: Any]) -> String {
        let type = request["@type"] as? String ?? "unknown"
        switch type {
        case "checkAuthenticationCode":
            let code = request["code"] as? String ?? ""
            return "\(type) length=\(code.count)"
        case "checkAuthenticationPassword":
            let password = request["password"] as? String ?? ""
            return "\(type) length=\(password.count)"
        case "setAuthenticationPhoneNumber":
            let phone = request["phone_number"] as? String ?? ""
            return "\(type) phone=\(maskedPhoneNumber(phone))"
        case "checkDatabaseEncryptionKey":
            let key = request["encryption_key"] as? String ?? ""
            return "\(type) present=\(!key.isEmpty)"
        case "setTdlibParameters":
            let apiId = intValue(request["api_id"]) ?? 0
            let databaseDirectory = request["database_directory"] as? String ?? ""
            let filesDirectory = request["files_directory"] as? String ?? ""
            return "\(type) api_id=\(apiId) db=\(databaseDirectory) files=\(filesDirectory)"
        default:
            return type
        }
    }

    private static func maskedPhoneNumber(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count > 4 else {
            return "[redacted-phone]"
        }
        return "[redacted-phone:\(digits.suffix(4))]"
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

    private static func int32Value(_ value: Any?) -> Int32? {
        guard let int64 = int64Value(value),
              int64 >= Int64(Int32.min),
              int64 <= Int64(Int32.max) else {
            return nil
        }
        return Int32(int64)
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
