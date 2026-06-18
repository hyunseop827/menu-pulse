#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/MenuPulse.dmg"
VOLUME_NAME="Menu Pulse"
STAGING_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

APP_PATH="$("$ROOT_DIR/Scripts/build-app.sh" | tail -n 1)"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

cp -R "$APP_PATH" "$STAGING_DIR/Menu Pulse.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
