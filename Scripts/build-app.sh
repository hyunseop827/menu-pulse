#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/release"
APP_PATH="$BUILD_DIR/Menu Pulse.app"
BIN_PATH="$APP_PATH/Contents/MacOS/MenuPulse"
ARCH="${ARCH:-arm64}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
SRC_FILES=("$ROOT_DIR"/Sources/MenuPulse/*.m)

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

xcrun clang \
  -fobjc-arc \
  -fmodules \
  -Os \
  -DNDEBUG \
  -arch "$ARCH" \
  -mmacosx-version-min=12.0 \
  -isysroot "$SDKROOT" \
  "${SRC_FILES[@]}" \
  -o "$BIN_PATH" \
  -framework AppKit \
  -framework Foundation \
  -framework CoreFoundation \
  -framework IOKit \
  -Wl,-dead_strip

strip -x "$BIN_PATH" 2>/dev/null || true
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/Packaging/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
printf "APPL????" > "$APP_PATH/Contents/PkgInfo"

codesign --force --sign - "$APP_PATH" >/dev/null
codesign --verify --strict "$APP_PATH"

echo "$APP_PATH"
