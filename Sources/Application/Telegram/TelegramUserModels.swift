import Foundation

public struct TelegramUserSettings: Sendable, Equatable {
    public var enabled: Bool
    public var apiId: Int
    public var apiHash: String
    public var phoneNumber: String
    public var databaseDirectory: String
    public var filesDirectory: String
    public var encryptionKey: String
    public var tdjsonLibraryPath: String?
    public var chatAllowlist: [String]

    public init(
        enabled: Bool = false,
        apiId: Int = 0,
        apiHash: String = "",
        phoneNumber: String = "",
        databaseDirectory: String,
        filesDirectory: String,
        encryptionKey: String = "",
        tdjsonLibraryPath: String? = nil,
        chatAllowlist: [String] = []
    ) {
        self.enabled = enabled
        self.apiId = apiId
        self.apiHash = apiHash
        self.phoneNumber = phoneNumber
        self.databaseDirectory = databaseDirectory
        self.filesDirectory = filesDirectory
        self.encryptionKey = encryptionKey
        self.tdjsonLibraryPath = tdjsonLibraryPath
        self.chatAllowlist = chatAllowlist
    }

    public var isConfigured: Bool {
        enabled
            && apiId > 0
            && !apiHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func make(environment: [String: String], configDirectory: URL) -> TelegramUserSettings {
        let databaseDirectory = environment["GRACULA_TELEGRAM_USER_DATABASE_DIR"]
            ?? configDirectory.appendingPathComponent("telegram-user/database", isDirectory: true).path
        let filesDirectory = environment["GRACULA_TELEGRAM_USER_FILES_DIR"]
            ?? configDirectory.appendingPathComponent("telegram-user/files", isDirectory: true).path
        return TelegramUserSettings(
            enabled: Self.bool(environment["GRACULA_TELEGRAM_USER_ENABLED"])
                || environment["TELEGRAM_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mtproto",
            apiId: Int(environment["GRACULA_TELEGRAM_API_ID"] ?? environment["TELEGRAM_API_ID"] ?? "") ?? 0,
            apiHash: environment["GRACULA_TELEGRAM_API_HASH"] ?? environment["TELEGRAM_API_HASH"] ?? "",
            phoneNumber: environment["GRACULA_TELEGRAM_PHONE"] ?? environment["TELEGRAM_PHONE"] ?? "",
            databaseDirectory: databaseDirectory,
            filesDirectory: filesDirectory,
            encryptionKey: environment["GRACULA_TELEGRAM_USER_ENCRYPTION_KEY"] ?? "",
            tdjsonLibraryPath: environment["GRACULA_TDLIB_JSON_LIBRARY"],
            chatAllowlist: Self.list(environment["GRACULA_TELEGRAM_USER_CHAT_ALLOWLIST"])
        )
    }

    private static func bool(_ rawValue: String?) -> Bool {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            true
        default:
            false
        }
    }

    private static func list(_ rawValue: String?) -> [String] {
        rawValue?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }
}

public enum TelegramUserAuthorizationState: Sendable, Equatable {
    case disabled
    case notConfigured(String)
    case libraryMissing([String])
    case waitingForPhoneNumber
    case waitingForCode
    case waitingForPassword
    case ready
    case closed
    case failed(String)

    public var displayText: String {
        switch self {
        case .disabled:
            "Telegram user API disabled."
        case .notConfigured(let reason):
            "Telegram user API is not configured: \(reason)"
        case .libraryMissing(let paths):
            "TDLib JSON library not found. Checked: \(paths.joined(separator: ", "))"
        case .waitingForPhoneNumber:
            "Telegram is waiting for a phone number."
        case .waitingForCode:
            "Telegram sent a login code."
        case .waitingForPassword:
            "Telegram account requires 2FA password."
        case .ready:
            "Telegram user API is authorized."
        case .closed:
            "Telegram user API session is closed."
        case .failed(let message):
            "Telegram user API failed: \(message)"
        }
    }
}

public struct TelegramUserDialog: Sendable, Equatable {
    public let id: String
    public let title: String
    public let type: String

    public init(id: String, title: String, type: String) {
        self.id = id
        self.title = title
        self.type = type
    }
}
