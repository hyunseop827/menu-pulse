#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_APP_PATH="$ROOT_DIR/build/release/Menu Pulse.app"
INSTALL_APP_PATH="$HOME/Applications/Menu Pulse.app"
BIN_PATH="$INSTALL_APP_PATH/Contents/MacOS/MenuPulse"
PLIST_PATH="$HOME/Library/LaunchAgents/dev.hyunseop.MenuPulse.plist"

"$ROOT_DIR/Scripts/build-app.sh"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true

mkdir -p "$HOME/Applications"
rm -rf "$INSTALL_APP_PATH"
cp -R "$BUILD_APP_PATH" "$INSTALL_APP_PATH"

rm -f "$PLIST_PATH"

"$BIN_PATH" --unregister-login-item >/dev/null 2>&1 || true
if "$BIN_PATH" --register-login-item; then
  LOGIN_MESSAGE="Open at login enabled."
else
  LOGIN_MESSAGE="Open at login needs approval in System Settings."
fi

open "$INSTALL_APP_PATH"

echo "MenuPulse installed to $INSTALL_APP_PATH. $LOGIN_MESSAGE"
