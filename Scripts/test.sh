#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BIN="$BUILD_DIR/MonitorTests"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
TEST_ARCH="${TEST_ARCH:-$(uname -m)}"

mkdir -p "$BUILD_DIR"

xcrun clang \
  -fobjc-arc \
  -fmodules \
  -Wall \
  -Wextra \
  -Werror \
  -Wnullable-to-nonnull-conversion \
  -arch "$TEST_ARCH" \
  -mmacosx-version-min=13.0 \
  -isysroot "$SDKROOT" \
  -I "$ROOT_DIR/Sources/MenuPulse" \
  "$ROOT_DIR/Tests/MonitorTests.m" \
  "$ROOT_DIR/Sources/MenuPulse/Monitors.m" \
  -o "$TEST_BIN" \
  -framework Foundation

"$TEST_BIN"
