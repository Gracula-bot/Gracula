#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPENCLAW_DIR="$ROOT/.openclaw"

if [ ! -d "$OPENCLAW_DIR" ]; then
  echo "No .openclaw directory found."
  exit 0
fi

find "$OPENCLAW_DIR" \
  \( -name "*.bak" -o -name "*.bak.*" -o -name "*.bak-*" -o -name "*.tmp" -o -name "*.temp" \) \
  -type f \
  -print \
  -delete

echo "Cleaned temporary Gracula/OpenClaw runtime files."
