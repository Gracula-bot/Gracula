# Gracula
Ai helper robot

## Development

Run the full verification suite:

```bash
swift test
```

Manual milestone checks are documented in [manualtesting.md](manualtesting.md).

## Trace Logging

Gracula now writes structured JSONL request traces to:

- `.runtime/logs/request-trace.jsonl`

Each trace event includes a `traceID` that follows the request through:

- user input reception in `AgentViewModel`
- conversation context assembly in `AgentOrchestrator`
- LLM planning prompt compilation and provider requests
- tool execution
- final user-visible response

Canonical config flags live in `AppConfiguration.plist` under `tracing`:

- `enabled`: master switch for structured trace logging
- `logFullContext`: when `true`, emit full prompts, request bodies, and conversation context at `debug`
- `logResponseBodies`: when `true`, emit raw LLM response bodies at `debug`
- `redactSensitiveData`: when `true`, redact secrets and obvious sensitive strings before writing logs
- `logLevel`: minimum level to persist (`debug`, `info`, `warn`, `error`)

The same settings are exported to runtime environment variables:

```bash
GRACULA_TRACE_LOGGING_ENABLED=1
GRACULA_TRACE_LOG_FULL_CONTEXT=0
GRACULA_TRACE_LOG_RESPONSE_BODY=0
GRACULA_TRACE_REDACT_SENSITIVE_DATA=1
GRACULA_TRACE_LOG_LEVEL=info
GRACULA_TRACE_LOG_PATH=/absolute/path/to/.runtime/logs/request-trace.jsonl
```

What gets logged:

- user text received by the app shell
- conversation context metadata and, optionally, full recent messages
- LLM request metadata: provider, model, purpose, parameters, endpoint
- optional full prompt/request body payloads
- LLM response metadata: latency, finish reason, usage, pricing source, calculated `cost_usd`
- tool start/finish/failure events
- final user response with total latency, total LLM cost, LLM call count, and tool call count

What gets redacted when `redactSensitiveData = true`:

- `password`, `token`, `secret`, `apiKey`, `authorization`, `cookie`, `privateKey`
- bearer tokens and API-key-like substrings inside free-form text
- PEM private keys
- obvious email addresses and phone numbers inside traced payload text

Interpretation notes:

- `cost_usd` is computed from the internal pricing catalog in `Sources/LLM/LLMPricingCatalog.swift`
- `pricing_source` and `pricing_version` identify which pricing table was used
- local HTTP planners are logged with `cost_usd = 0` and `pricing_source = local-runtime`

## OpenClaw Internet Tools

The bundled Gracula OpenClaw workspace is now configured to expose the internet-facing tool set:

- `web_search` for live discovery
- `web_fetch` for direct page reads
- `browser` for interactive or JS-heavy sites

The checked-in [`.openclaw/openclaw.json`](/Users/gg/Gracula/.openclaw/openclaw.json) keeps the regular `messaging` profile and uses `tools.alsoAllow` to add `group:web` and `browser` on top of it. This is required because `tools.allow` only narrows the active profile and cannot re-enable tools that the `messaging` profile already excluded.

Notes:

- `web_fetch` works without extra setup for normal pages.
- `browser` works without extra API credentials once browser support is enabled in OpenClaw.
- `web_search` is enabled as a callable tool, but in this OpenClaw build it needs a supported provider key to return live search results.
- `web_search` is left without a pinned provider. If provider credentials exist, OpenClaw can use them; otherwise the agent should fall back to `web_fetch` and `browser` instead of failing the request.
- The browser plugin must stay allowed in `plugins.allow`, and the `browser` plugin entry must remain enabled.

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
