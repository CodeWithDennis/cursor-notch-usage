#!/usr/bin/env bash
# Build "Cursor Notch Usage.app" and pack it into a drag-to-Applications DMG.
# Output: dist/Cursor-Notch-Usage-<version>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Cursor Notch Usage"
VERSION="0.1.0"
DMG_NAME="Cursor-Notch-Usage-${VERSION}"
DIST="$ROOT/dist"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/cursor-notch-usage-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

echo "[dmg] staging app..."
"$ROOT/scripts/install-app.sh" "$STAGE"

# Drag-to-install layout.
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST"
DMG_PATH="${DIST}/${DMG_NAME}.dmg"
rm -f "${DMG_PATH}"

echo "[dmg] creating ${DMG_PATH}..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "[dmg] done -> ${DMG_PATH}"
echo "[dmg] Open the DMG and drag the app into Applications."
