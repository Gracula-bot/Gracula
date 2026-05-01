---
name: telegram-obs-track
description: "Enqueue Telegram group track links/commands into local stream track bridge"
metadata:
  {
    "openclaw":
      {
        "emoji": "🎵",
        "events": ["message:received"],
      },
  }
---

# Telegram OBS Track Hook

Listens for inbound Telegram group messages and forwards detected track requests
(links or play commands) to a local HTTP track bridge.

## Env vars

- `OPENCLAW_TRACK_BRIDGE_URL` (default: `http://127.0.0.1:7072/track`)
- `OPENCLAW_STREAM_BRIDGE_TOKEN` (optional bearer token)
- `OPENCLAW_TRACK_ONLY_GROUPS` (default: `1`)
- `OPENCLAW_TRACK_AUTO_LINKS` (default: `1`)
