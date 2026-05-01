---
name: telegram-obs-voice
description: "Forward outbound Telegram bot replies to local OBS voice bridge"
metadata:
  {
    "openclaw":
      {
        "emoji": "🎙️",
        "events": ["message:sent"],
      },
  }
---

# Telegram OBS Voice Hook

Forwards outbound Telegram messages to a local HTTP bridge (`/speak`) so OBS can play the voice and show subtitles.

## Required env vars

- `OPENCLAW_STREAM_BRIDGE_URL` (default: `http://127.0.0.1:7070/speak`)
- `OPENCLAW_STREAM_BRIDGE_TOKEN` (optional bearer token)

## Optional env vars

- `OPENCLAW_STREAM_MIN_CHARS` (default: `20`)
- `OPENCLAW_STREAM_MAX_CHARS` (default: `500`)

This hook only forwards successful outbound messages where `channelId === "telegram"`.
Short messages, command-like text (`/something`, `!something`), and fallback error text are ignored.
