#!/usr/bin/env bash
# Dev: build the bridge (if needed) and launch Cursor Notch Usage.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE_DIR="$ROOT/bridge"

cd "$BRIDGE_DIR"
if [[ ! -d node_modules ]]; then
  echo "[run] npm install..."
  npm install
fi
if [[ ! -f dist/index.js ]] || [[ src/index.ts -nt dist/index.js ]]; then
  echo "[run] building bridge..."
  npm run build
fi

if lsof -nP -iTCP:4318 -sTCP:LISTEN >/dev/null 2>&1; then
  if curl -sf --max-time 0.3 "http://127.0.0.1:4318/health" | grep -q '"apiVersion"'; then
    echo "[run] stopping previous bridge on :4318"
    lsof -tiTCP:4318 -sTCP:LISTEN | xargs kill 2>/dev/null || true
    sleep 0.2
  fi
fi

cd "$ROOT"
echo "[run] launching Cursor Notch Usage..."
exec swift run
