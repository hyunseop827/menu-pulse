#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${MENU_PULSE_BUILD_DIR:-$ROOT_DIR/build/release}"
APP_PATH="$BUILD_DIR/Menu Pulse.app"
BIN_PATH="$APP_PATH/Contents/MacOS/MenuPulse"
ARCH="${ARCH:-arm64}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
SRC_FILES=("$ROOT_DIR"/Sources/MenuPulse/*.m)

if [[ "$ARCH" != "arm64" ]]; then
  echo "build-app: Menu Pulse supports the arm64 architecture only" >&2
  exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

xcrun clang \
  -fobjc-arc \
  -fmodules \
  -Os \
  -DNDEBUG \
  -Wall \
  -Wextra \
  -Werror \
  -Wnullable-to-nonnull-conversion \
  -arch "$ARCH" \
  -mmacosx-version-min=13.0 \
  -isysroot "$SDKROOT" \
  "${SRC_FILES[@]}" \
  -o "$BIN_PATH" \
  -framework AppKit \
  -framework Foundation \
  -framework CoreFoundation \
  -framework IOKit \
  -framework ServiceManagement \
  -Wl,-dead_strip

strip -x "$BIN_PATH" 2>/dev/null || true
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/Packaging/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
printf "APPL????" > "$APP_PATH/Contents/PkgInfo"

codesign --force --sign - "$APP_PATH" >/dev/null
codesign --verify --strict "$APP_PATH"

echo "$APP_PATH"
