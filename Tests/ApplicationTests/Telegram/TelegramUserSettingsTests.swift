import Application
import Foundation
import Testing

@Test
func telegramUserSettingsReadsEnvironment() {
    let configDirectory = URL(fileURLWithPath: "/tmp/gracula-openclaw", isDirectory: true)
    let settings = TelegramUserSettings.make(
        environment: [
            "GRACULA_TELEGRAM_USER_ENABLED": "1",
            "GRACULA_TELEGRAM_API_ID": "12345",
            "GRACULA_TELEGRAM_API_HASH": "hash",
            "GRACULA_TELEGRAM_PHONE": "+10000000000",
            "GRACULA_TDLIB_JSON_LIBRARY": "/tmp/libtdjson.dylib",
            "GRACULA_TELEGRAM_USER_CHAT_ALLOWLIST": "Alice, -100123"
        ],
        configDirectory: configDirectory
    )

    #expect(settings.enabled)
    #expect(settings.apiId == 12345)
    #expect(settings.apiHash == "hash")
    #expect(settings.phoneNumber == "+10000000000")
    #expect(settings.tdjsonLibraryPath == "/tmp/libtdjson.dylib")
    #expect(settings.chatAllowlist == ["Alice", "-100123"])
    #expect(settings.databaseDirectory == "/tmp/gracula-openclaw/telegram-user/database")
    #expect(settings.filesDirectory == "/tmp/gracula-openclaw/telegram-user/files")
    #expect(settings.isConfigured)
}

@Test
func telegramUserSettingsRequiresCoreCredentials() {
    let configDirectory = URL(fileURLWithPath: "/tmp/gracula-openclaw", isDirectory: true)
    let settings = TelegramUserSettings.make(
        environment: ["GRACULA_TELEGRAM_USER_ENABLED": "true"],
        configDirectory: configDirectory
    )

    #expect(settings.enabled)
    #expect(!settings.isConfigured)
}

@Test
func telegramUserSettingsAcceptsGenericTelegramMTProtoEnvironment() {
    let settings = TelegramUserSettings.make(
        environment: [
            "TELEGRAM_MODE": "mtproto",
            "TELEGRAM_API_ID": "42",
            "TELEGRAM_API_HASH": "hash",
            "TELEGRAM_PHONE": "+10000000000"
        ],
        configDirectory: URL(fileURLWithPath: "/tmp/gracula-openclaw", isDirectory: true)
    )

    #expect(settings.enabled)
    #expect(settings.apiId == 42)
    #expect(settings.apiHash == "hash")
    #expect(settings.phoneNumber == "+10000000000")
    #expect(settings.isConfigured)
}

@Test
func tdlibCandidatePathsPreferExplicitPath() {
    let paths = DynamicTDLibJSONBridge.candidateLibraryPaths(explicitPath: "/custom/libtdjson.dylib")

    #expect(paths.first == "/custom/libtdjson.dylib")
    #expect(paths.contains("/opt/homebrew/lib/libtdjson.dylib"))
}
