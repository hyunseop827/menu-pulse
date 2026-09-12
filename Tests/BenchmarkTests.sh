#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d -t menu-pulse-benchmark-tests)"
BENCHMARK_SCRIPT_PID=""

cleanup() {
  if [[ -n "$BENCHMARK_SCRIPT_PID" ]]; then
    kill -TERM "$BENCHMARK_SCRIPT_PID" 2>/dev/null || true
    wait "$BENCHMARK_SCRIPT_PID" 2>/dev/null || true
  fi
  rm -r -- "$TEST_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() { echo "BenchmarkTests: $*" >&2; exit 1; }

mkdir -p "$TEST_DIR/Temp" "$TEST_DIR/Home/Library/Preferences"
PREFERENCES="$TEST_DIR/Home/Library/Preferences/dev.hyunseop.MenuPulse.plist"
plutil -create xml1 "$PREFERENCES"
plutil -insert cpuRefreshInterval -float 9 "$PREFERENCES"
cp "$PREFERENCES" "$TEST_DIR/preferences.before.plist"

# Watch the real run so the test checks the identity of the executable that is
# measured, as well as successful output and cleanup of its temporary files.
TMPDIR="$TEST_DIR/Temp/" CFFIXED_USER_HOME="$TEST_DIR/Home" \
  WARMUP=0 DURATION=2 INTERVAL=1 ALL_METRICS=0 \
  "$ROOT_DIR/Scripts/benchmark.sh" > "$TEST_DIR/output.log" 2>&1 &
BENCHMARK_SCRIPT_PID=$!
for ((attempt = 0; attempt < 600; attempt += 1)); do
  if grep -q '^Benchmark PID:' "$TEST_DIR/output.log"; then break; fi
  kill -0 "$BENCHMARK_SCRIPT_PID" 2>/dev/null || break
  sleep 0.1
done
grep -q '^Benchmark PID:' "$TEST_DIR/output.log" || {
  cat "$TEST_DIR/output.log" >&2
  fail 'benchmark did not start'
}
shopt -s nullglob
APPS=("$TEST_DIR"/Temp/menu-pulse-benchmark.*/Build/"Menu Pulse.app")
[[ "${#APPS[@]}" == 1 ]] || fail 'expected one temporary benchmark app'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APPS[0]}/Contents/Info.plist")" \
  == dev.hyunseop.MenuPulse.Benchmark ]] || fail 'benchmark shares the installed app identity'
codesign --verify --strict "${APPS[0]}"
MEASURED_PID="$(awk '/^Benchmark PID:/ {print $3}' "$TEST_DIR/output.log")"
wait "$BENCHMARK_SCRIPT_PID" || { cat "$TEST_DIR/output.log" >&2; fail 'benchmark failed'; }
BENCHMARK_SCRIPT_PID=""
grep -q '^CPU average:' "$TEST_DIR/output.log" || fail 'CPU results missing'
grep -q '^RSS average:' "$TEST_DIR/output.log" || fail 'memory results missing'
cmp -s "$PREFERENCES" "$TEST_DIR/preferences.before.plist" || fail 'preferences changed'
if kill -0 "$MEASURED_PID" 2>/dev/null; then fail 'measured process was left running'; fi
REMAINING=("$TEST_DIR"/Temp/*)
[[ "${#REMAINING[@]}" == 0 ]] || fail 'temporary build, preferences, or samples were left behind'

if TMPDIR="$TEST_DIR/Temp/" DURATION=0 "$ROOT_DIR/Scripts/benchmark.sh" \
  > "$TEST_DIR/invalid.log" 2>&1; then
  fail 'zero duration was accepted'
fi
grep -q 'DURATION must be greater than zero' "$TEST_DIR/invalid.log" || fail 'missing validation error'
REMAINING=("$TEST_DIR"/Temp/*)
[[ "${#REMAINING[@]}" == 0 ]] || fail 'invalid arguments created build output'

echo 'Benchmark isolation and cleanup tests passed.'
