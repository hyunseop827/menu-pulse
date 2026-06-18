#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_APP_PATH="$ROOT_DIR/build/release/MenuPulse.app"
INSTALL_APP_PATH="$HOME/Applications/MenuPulse.app"
BIN_PATH="$INSTALL_APP_PATH/Contents/MacOS/MenuPulse"
PLIST_PATH="$HOME/Library/LaunchAgents/dev.hyunseop.MenuPulse.plist"
LABEL="dev.hyunseop.MenuPulse"

"$ROOT_DIR/Scripts/build-app.sh"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true

mkdir -p "$HOME/Applications"
mkdir -p "$HOME/Library/LaunchAgents"
rm -rf "$INSTALL_APP_PATH"
cp -R "$BUILD_APP_PATH" "$INSTALL_APP_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>/tmp/MenuPulse.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/MenuPulse.err.log</string>
</dict>
</plist>
PLIST

open "$INSTALL_APP_PATH"

echo "MenuPulse installed to $INSTALL_APP_PATH and set to open at login."
