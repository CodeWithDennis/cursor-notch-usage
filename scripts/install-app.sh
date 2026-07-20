#!/usr/bin/env bash
# Build a launchable .app that embeds the bridge and Swift binary.
# Usage: ./scripts/install-app.sh [parent-dir]
# Default: ~/Applications/Cursor Notch Usage.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Cursor Notch Usage"
BIN_NAME="CursorNotchUsage"
VERSION="0.1.0"
APP_DIR="${1:-$HOME/Applications}/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BRIDGE_SRC="$ROOT/bridge"

echo "[app] building bridge..."
cd "$BRIDGE_SRC"
if [[ ! -d node_modules ]]; then npm install; fi
npm run build

echo "[app] building Swift (release)..."
cd "$ROOT"
swift build -c release

BIN="$ROOT/.build/release/${BIN_NAME}"
[[ -x "$BIN" ]] || { echo "missing $BIN" >&2; exit 1; }

echo "[app] assembling ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES/bridge/dist"

cp "$ROOT/Assets/AppIcon.icns" "$RESOURCES/AppIcon.icns"

cp "$BRIDGE_SRC/dist/index.js" "$RESOURCES/bridge/dist/"
cp "$BRIDGE_SRC/package.json" "$RESOURCES/bridge/"
cp "$BIN" "$MACOS/${BIN_NAME}"
chmod +x "$MACOS/${BIN_NAME}"

cat > "$MACOS/launch" <<EOF
#!/bin/bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
RESOURCES="\$(cd "\$HERE/../Resources" && pwd)"
export BRIDGE_PORT="\${BRIDGE_PORT:-4318}"
export PATH="/opt/homebrew/bin:/usr/local/bin:\$HOME/.nvm/versions/node/\$(ls "\$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -1)/bin:\$PATH"
cd "\$RESOURCES"
exec "\$HERE/${BIN_NAME}"
EOF
chmod +x "$MACOS/launch"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.codewithdennis.cursor-notch-usage</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>launch</string>
  <key>CFBundleGetInfoString</key>
  <string>${APP_NAME} ${VERSION}, Copyright (c) 2026 CodeWithDennis</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright (c) 2026 CodeWithDennis</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
</dict>
</plist>
EOF

echo "[app] installed -> ${APP_DIR}"
