#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
TEST_BIN="$BUILD_DIR/MonitorTests"
SETTINGS_TEST_BIN="$BUILD_DIR/SettingsSchedulerTests"
UI_TEST_BIN="$BUILD_DIR/MenuPulseUITests"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
TEST_ARCH="${TEST_ARCH:-$(uname -m)}"
TEST_HOME="$(/usr/bin/mktemp -d -t menu-pulse-test-home)"

cleanup() {
  local test_parent=""
  local expected_parent=""

  if [[ -n "$TEST_HOME" && -d "$TEST_HOME" ]]; then
    test_parent="$(cd "$(dirname "$TEST_HOME")" && pwd -P)"
    expected_parent="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  fi
  if [[ -n "$TEST_HOME" && "$(basename "$TEST_HOME")" == menu-pulse-test-home.* &&
        "$test_parent" == "$expected_parent" ]]; then
    /bin/rm -rf -- "$TEST_HOME"
  fi
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR"
mkdir -p "$TEST_HOME/Library/Preferences"

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

CFFIXED_USER_HOME="$TEST_HOME" "$TEST_BIN"

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
  "$ROOT_DIR/Tests/SettingsSchedulerTests.m" \
  "$ROOT_DIR/Tests/MemoryUserDefaults.m" \
  "$ROOT_DIR/Sources/MenuPulse/SettingsStore.m" \
  "$ROOT_DIR/Sources/MenuPulse/RefreshScheduler.m" \
  -o "$SETTINGS_TEST_BIN" \
  -framework Foundation

CFFIXED_USER_HOME="$TEST_HOME" "$SETTINGS_TEST_BIN"

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
  "$ROOT_DIR/Tests/MenuPulseUITests.m" \
  "$ROOT_DIR/Tests/MemoryUserDefaults.m" \
  "$ROOT_DIR/Sources/MenuPulse/LoginItemManager.m" \
  "$ROOT_DIR/Sources/MenuPulse/MenuPulse.m" \
  "$ROOT_DIR/Sources/MenuPulse/Monitors.m" \
  "$ROOT_DIR/Sources/MenuPulse/RefreshScheduler.m" \
  "$ROOT_DIR/Sources/MenuPulse/SettingsStore.m" \
  "$ROOT_DIR/Sources/MenuPulse/TemperatureReader.m" \
  -o "$UI_TEST_BIN" \
  -framework AppKit \
  -framework Foundation \
  -framework CoreFoundation \
  -framework IOKit \
  -framework ServiceManagement

CFFIXED_USER_HOME="$TEST_HOME" "$UI_TEST_BIN"

CFFIXED_USER_HOME="$TEST_HOME" "$ROOT_DIR/Tests/LifecycleScriptTests.sh"
