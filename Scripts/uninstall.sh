#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/dev.hyunseop.MenuPulse.plist"
INSTALL_APP_PATH="$HOME/Applications/Menu Pulse.app"
BIN_PATH="$INSTALL_APP_PATH/Contents/MacOS/MenuPulse"

if [[ -x "$BIN_PATH" ]]; then
  "$BIN_PATH" --unregister-login-item >/dev/null 2>&1 || true
fi

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"
rm -rf "$INSTALL_APP_PATH"

echo "MenuPulse removed."
