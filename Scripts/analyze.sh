#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ANALYZE_ARCH="${ANALYZE_ARCH:-arm64}"

for source_file in "$ROOT_DIR"/Sources/MenuPulse/*.m; do
  xcrun clang --analyze \
    -fobjc-arc \
    -fmodules \
    -Wall \
    -Wextra \
    -Werror \
    -Wnullable-to-nonnull-conversion \
    -arch "$ANALYZE_ARCH" \
    -mmacosx-version-min=13.0 \
    -isysroot "$SDK_PATH" \
    -I "$ROOT_DIR/Sources/MenuPulse" \
    -Xanalyzer -analyzer-output=text \
    "$source_file" \
    -o /dev/null
done

echo "Clang static analysis passed."
