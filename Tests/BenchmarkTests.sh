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
# The measured app would remove this legacy key from its own defaults domain
# if it ever used this home instead of its private benchmark home.
PREFERENCES_DIR="$TEST_DIR/Home/Library/Preferences"
for domain in dev.hyunseop.MenuPulse dev.hyunseop.MenuPulse.Benchmark; do
  plutil -create xml1 "$PREFERENCES_DIR/$domain.plist"
  plutil -insert cpuRefreshInterval -float 9 "$PREFERENCES_DIR/$domain.plist"
done
cp -R "$PREFERENCES_DIR" "$TEST_DIR/preferences.before"

# Watch the real run so the test checks the identity of the executable that is
# measured, as well as successful output and cleanup of its temporary files.
TMPDIR="$TEST_DIR/Temp/" CFFIXED_USER_HOME="$TEST_DIR/Home" \
  RESULTS_DIR="$TEST_DIR/Saved results" \
  WARMUP=0 DURATION=2 INTERVAL=1 ALL_METRICS=0 \
  SHOW_CPU=1 SHOW_RAM=1 SHOW_TEMPERATURE=0 SHOW_DISK=0 CPU_RAM_REFRESH_INTERVAL=3 \
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
grep -q '^CPU sample average:' "$TEST_DIR/output.log" || fail 'CPU results missing'
grep -q '^RSS average:' "$TEST_DIR/output.log" || fail 'memory results missing'
diff -r "$PREFERENCES_DIR" "$TEST_DIR/preferences.before" >/dev/null || fail 'preferences changed'
if kill -0 "$MEASURED_PID" 2>/dev/null; then fail 'measured process was left running'; fi
REMAINING=("$TEST_DIR"/Temp/*)
[[ "${#REMAINING[@]}" == 0 ]] || fail 'temporary build or preferences were left behind'

RESULTS=("$TEST_DIR/Saved results"/run-*)
[[ "${#RESULTS[@]}" == 1 ]] || fail 'expected one saved benchmark run'
REPORT="${RESULTS[0]}/report.txt"
cmp -s "$REPORT" "$TEST_DIR/output.log" || {
  diff -u "$REPORT" "$TEST_DIR/output.log" >&2 || true
  fail 'saved report does not match terminal output'
}
EXPECTED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Packaging/Info.plist")"
grep -Fxq "App version: $EXPECTED_VERSION" "$REPORT" || fail 'app version missing'
grep -Fxq "Git commit: $(git -C "$ROOT_DIR" rev-parse HEAD)" "$REPORT" || fail 'commit missing'
grep -Eq '^Git worktree: (clean|dirty)$' "$REPORT" || fail 'worktree state missing'
for field in 'Started (UTC):' 'Completed (UTC):' 'macOS:' 'Mac model:' 'Chip:' 'Physical RAM:'; do
  grep -Fq "$field" "$REPORT" || fail "metadata missing: $field"
done
grep -Fq 'not the downloaded GitHub DMG' "$REPORT" || fail 'build provenance missing'
grep -Fxq 'Scenario: CPU/RAM' "$REPORT" || fail 'scenario missing'
grep -Fxq 'CPU/RAM refresh interval: 3s' "$REPORT" || fail 'refresh interval missing'
grep -Fxq 'Samples collected: 2' "$REPORT" || fail 'sample count missing'
grep -Eq '^RSS average: [0-9.]+ MiB$' "$REPORT" || fail 'RSS units incorrect'
grep -Fq 'Private dirty is not total memory usage' "$REPORT" || fail 'memory caveat missing'
grep -Fq 'decaying average' "$REPORT" || fail 'CPU sample semantics missing'
if grep -q '^DMG size:' "$REPORT"; then fail 'unrelated DMG size was reported'; fi
awk '
  NR == 1 { if ($0 != "sample pcpu rss_kib") exit 1; next }
  { if (NF != 3 || $1 != NR - 1 || $2 !~ /^[0-9.]+$/ || $3 !~ /^[0-9]+$/) exit 1 }
  END { if (NR != 3) exit 1 }
' "${RESULTS[0]}/samples.txt" || fail 'saved ps samples are incomplete or invalid'
[[ -s "${RESULTS[0]}/vmmap.txt" ]] || fail 'vmmap output or failure reason missing'
[[ -f "${RESULTS[0]}/app.log" ]] || fail 'app log was not retained'

# Failure of this optional tool must still leave a usable, distinct report.
mkdir "$TEST_DIR/Tools"
printf '#!/bin/sh\necho "vmmap unavailable for test" >&2\nexit 1\n' > "$TEST_DIR/Tools/vmmap"
chmod +x "$TEST_DIR/Tools/vmmap"
PATH="$TEST_DIR/Tools:$PATH" TMPDIR="$TEST_DIR/Temp/" RESULTS_DIR="$TEST_DIR/Saved results" \
  WARMUP=0 DURATION=1 INTERVAL=1 "$ROOT_DIR/Scripts/benchmark.sh" \
  > "$TEST_DIR/vmmap-failure.log" 2>&1 || { cat "$TEST_DIR/vmmap-failure.log" >&2; fail 'vmmap failure aborted benchmark'; }
FAILURE_RESULT="$(sed -n 's/^Results: //p' "$TEST_DIR/vmmap-failure.log")"
grep -Fxq 'Private dirty: unavailable' "$FAILURE_RESULT/report.txt" || fail 'missing vmmap fallback'
grep -Fq 'vmmap unavailable for test' "$FAILURE_RESULT/vmmap.txt" || fail 'vmmap error was not retained'
RESULTS=("$TEST_DIR/Saved results"/run-*)
[[ "${#RESULTS[@]}" == 2 ]] || fail 'successive runs overwrote saved results'
REMAINING=("$TEST_DIR"/Temp/*)
[[ "${#REMAINING[@]}" == 0 ]] || fail 'vmmap failure left temporary output behind'

if TMPDIR="$TEST_DIR/Temp/" RESULTS_DIR="$TEST_DIR/Invalid results" DURATION=0 "$ROOT_DIR/Scripts/benchmark.sh" \
  > "$TEST_DIR/invalid.log" 2>&1; then
  fail 'zero duration was accepted'
fi
grep -q 'DURATION must be greater than zero' "$TEST_DIR/invalid.log" || fail 'missing validation error'
REMAINING=("$TEST_DIR"/Temp/*)
[[ "${#REMAINING[@]}" == 0 ]] || fail 'invalid arguments created build output'
[[ ! -e "$TEST_DIR/Invalid results" ]] || fail 'invalid arguments created result output'

echo 'Benchmark isolation, saved results, and cleanup tests passed.'
