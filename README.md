# Gracula
Ai helper robot

## Development

Run the full verification suite:

```bash
swift test
```

Manual milestone checks are documented in [manualtesting.md](manualtesting.md).

## Telegram Reply Integration

Gracula now has a local Telegram voice-command route for OpenClaw. A recognized reply command sends the message automatically without calling the LLM/OpenClaw planner.

Supported commands:

- `OpenClaw, ответь в Telegram Антону: буду через 10 минут`
- `ответь Антону в Telegram: сейчас занят`
- `ответь в последнем чате Telegram: напишу позже`
- `прочитай последнее сообщение в Telegram`

Current backend: `TelegramRoutingService`. It routes requests across three adapters:

- `TelegramUserTDLibClient` for personal-account chat discovery, reading, and direct MTProto replies.
- `TelegramBusinessBotService` for Telegram Business polling and replies through Bot API business connections.
- `TelegramMacAppAutomationService` as a macOS Telegram Desktop fallback for manual account sending when no API backend is available.

When TDLib is configured, Gracula prefers TDLib for reading messages and sending replies. When a Business bot token is configured, Gracula can also read the latest pending Telegram Business message and answer through the same connection. If neither API backend is available, Gracula falls back to Telegram Desktop UI automation for sending.

Additional authorization commands for the TDLib user backend:

- `код Telegram 12345`
- `введи код телеграм 12345`
- `пароль Telegram мой_пароль_2fa`

Required macOS permissions:

- Microphone, for voice capture.
- Speech Recognition, when Apple Speech is used.
- Automation, for controlling Telegram and System Events.
- Accessibility, for UI-scripting the chat search, paste, and Enter actions.

Supported environment variables for the unified Telegram backend:

```bash
GRACULA_TELEGRAM_USER_ENABLED=1
GRACULA_TELEGRAM_API_ID=123456
GRACULA_TELEGRAM_API_HASH=...
GRACULA_TELEGRAM_PHONE=+79990000000
GRACULA_TDLIB_JSON_LIBRARY=/opt/homebrew/lib/libtdjson.dylib
GRACULA_TELEGRAM_USER_CHAT_ALLOWLIST=Anton,-1001234567890

GRACULA_TELEGRAM_BOT_TOKEN=123456:ABCDEF
GRACULA_TELEGRAM_BUSINESS_CONNECTION_ID=optional_business_connection_id
```

The Telegram Desktop fallback still does not require Telegram API secrets, but TDLib/MTProto and Telegram Business credentials must stay out of source code and should be stored in Keychain or another secure storage layer.

Local test path:

```bash
swift test
xcodebuild -project Examples/GraculaExample/GraculaExample.xcodeproj -scheme GraculaExample -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

For manual testing, open Telegram, open the example app, then record or type a Telegram command. For a named chat command, verify Telegram searches/selects that chat and sends the text. For a latest-chat command, verify the message is sent to the currently selected Telegram chat.
