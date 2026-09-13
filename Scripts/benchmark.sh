#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH=""
BIN_PATH=""
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/build/benchmarks}"

WARMUP="${WARMUP:-30}"
DURATION="${DURATION:-300}"
INTERVAL="${INTERVAL:-1}"
CPU_RAM_REFRESH_INTERVAL="${CPU_RAM_REFRESH_INTERVAL:-${REFRESH_INTERVAL:-3}}"
TEMPERATURE_REFRESH_INTERVAL="${TEMPERATURE_REFRESH_INTERVAL:-30}"
DISK_REFRESH_INTERVAL="${DISK_REFRESH_INTERVAL:-300}"
SHOW_CPU="${SHOW_CPU:-1}"
SHOW_RAM="${SHOW_RAM:-1}"
SHOW_TEMPERATURE="${SHOW_TEMPERATURE:-0}"
SHOW_DISK="${SHOW_DISK:-0}"
ALL_METRICS="${ALL_METRICS:-}"

BENCHMARK_PID=""
BENCHMARK_DIR=""
BENCHMARK_HOME=""
BENCHMARK_TEMP_ROOT=""
SAMPLE_FILE=""
LOG_FILE=""
REPORT_TEE_PID=""

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_nonnegative_integer() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail "$name must be a non-negative integer."
}

require_positive_integer() {
  local name="$1"
  local value="$2"
  require_nonnegative_integer "$name" "$value"
  (( 10#$value > 0 )) || fail "$name must be greater than zero."
}

require_boolean() {
  local name="$1"
  local value="$2"
  case "$value" in
    0|1) ;;
    *) fail "$name must be 0 or 1." ;;
  esac
}

boolean_argument() {
  [[ "$1" == "1" ]] && echo YES || echo NO
}

cleanup() {
  if [[ -n "$BENCHMARK_PID" ]] && kill -0 "$BENCHMARK_PID" >/dev/null 2>&1; then
    kill -TERM "$BENCHMARK_PID" >/dev/null 2>&1 || true

    local attempt
    for ((attempt = 0; attempt < 20; attempt += 1)); do
      if ! kill -0 "$BENCHMARK_PID" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done

    if kill -0 "$BENCHMARK_PID" >/dev/null 2>&1; then
      kill -KILL "$BENCHMARK_PID" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "$BENCHMARK_PID" ]]; then
    wait "$BENCHMARK_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$BENCHMARK_DIR" && -d "$BENCHMARK_DIR" &&
        "$BENCHMARK_DIR" == "$BENCHMARK_TEMP_ROOT"/menu-pulse-benchmark.* ]]; then
    /bin/rm -r -- "$BENCHMARK_DIR"
  fi
  BENCHMARK_DIR=""

  if [[ -n "$REPORT_TEE_PID" ]]; then
    # Close the report pipe and wait for tee so the saved report is complete
    # when the benchmark exits, including on an interrupted run.
    exec 1>&3 2>&4 3>&- 4>&-
    wait "$REPORT_TEE_PID" || true
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_nonnegative_integer WARMUP "$WARMUP"
require_positive_integer DURATION "$DURATION"
require_positive_integer INTERVAL "$INTERVAL"
WARMUP=$(( 10#$WARMUP ))
DURATION=$(( 10#$DURATION ))
INTERVAL=$(( 10#$INTERVAL ))

case "$CPU_RAM_REFRESH_INTERVAL" in
  1|3|10) ;;
  *) fail "CPU_RAM_REFRESH_INTERVAL must be 1, 3, or 10." ;;
esac

case "$TEMPERATURE_REFRESH_INTERVAL" in
  1|3|10|30|60) ;;
  *) fail "TEMPERATURE_REFRESH_INTERVAL must be 1, 3, 10, 30, or 60." ;;
esac

case "$DISK_REFRESH_INTERVAL" in
  60|180|300|600) ;;
  *) fail "DISK_REFRESH_INTERVAL must be 60, 180, 300, or 600." ;;
esac

require_boolean SHOW_CPU "$SHOW_CPU"
require_boolean SHOW_RAM "$SHOW_RAM"
require_boolean SHOW_TEMPERATURE "$SHOW_TEMPERATURE"
require_boolean SHOW_DISK "$SHOW_DISK"
if [[ -n "$ALL_METRICS" ]]; then
  require_boolean ALL_METRICS "$ALL_METRICS"
  if [[ "$ALL_METRICS" == "1" ]]; then
    SHOW_CPU=1
    SHOW_RAM=1
    SHOW_TEMPERATURE=1
    SHOW_DISK=1
  fi
fi
if [[ "$SHOW_CPU$SHOW_RAM$SHOW_TEMPERATURE$SHOW_DISK" == "0000" ]]; then
  fail "at least one metric must be enabled."
fi

[[ -d "${TMPDIR:-/tmp}" ]] || fail "TMPDIR must refer to an existing directory."
BENCHMARK_TEMP_ROOT="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
[[ -n "$BENCHMARK_TEMP_ROOT" && "$BENCHMARK_TEMP_ROOT" != "/" ]] || \
  fail "TMPDIR must resolve to a non-root directory."

mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd -P)"
RESULT_DIR="$(mktemp -d "$RESULTS_DIR/run-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
BENCHMARK_DIR="$(mktemp -d "$BENCHMARK_TEMP_ROOT/menu-pulse-benchmark.XXXXXX")"
SAMPLE_FILE="$RESULT_DIR/samples.txt"
LOG_FILE="$RESULT_DIR/app.log"
VMMAP_FILE="$RESULT_DIR/vmmap.txt"
exec 3>&1 4>&2
# A normal background job is waitable even with macOS's bundled Bash 3.2.
mkfifo "$BENCHMARK_DIR/report.pipe"
tee "$RESULT_DIR/report.txt" < "$BENCHMARK_DIR/report.pipe" &
REPORT_TEE_PID=$!
exec > "$BENCHMARK_DIR/report.pipe" 2>&1

echo "Menu Pulse benchmark"
echo "Started (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Results: $RESULT_DIR"
echo "Build source: current checkout, rebuilt with bundle ID dev.hyunseop.MenuPulse.Benchmark"
echo "This measures a temporary build, not the downloaded GitHub DMG."
echo "Git commit: $(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unavailable)"
if GIT_STATUS="$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null)"; then
  if [[ -z "$GIT_STATUS" ]]; then echo "Git worktree: clean"; else echo "Git worktree: dirty"; fi
else
  echo "Git worktree: unavailable"
fi
echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "Mac model: $(sysctl -n hw.model)"
echo "Chip: $(sysctl -n machdep.cpu.brand_string)"
echo "Architecture: $(uname -m)"
awk -v bytes="$(sysctl -n hw.memsize)" \
  'BEGIN { printf "Physical RAM: %.1f GiB (%s bytes)\n", bytes / 1024 / 1024 / 1024, bytes }'
echo "Power source: $(pmset -g batt | sed -n '1p')"
echo "Workload: menu bar only at launch; no automated interaction with settings."
echo "Other apps, display sleep, and power settings are not controlled by this script."
echo "CPU: repeated ps %cpu samples (a decaying average over up to one minute), not interval CPU time."
echo "Memory: RSS samples and end-of-run vmmap Private dirty are separate measures."
echo "Private dirty is not total memory usage or physical footprint. Memory units are binary (MiB)."

echo "Building Menu Pulse for measurement..."
APP_PATH="$BENCHMARK_DIR/Build/Menu Pulse.app"
BIN_PATH="$APP_PATH/Contents/MacOS/MenuPulse"
BENCHMARK_HOME="$BENCHMARK_DIR/Home"
/bin/mkdir -p "$BENCHMARK_HOME/Library/Preferences"
# A distinct bundle identifier keeps measurement builds separate from the
# installed app's ServiceManagement registration. Only results are retained.
make -s -C "$ROOT_DIR" app BUILD_DIR="$BENCHMARK_DIR/Build" \
  BUNDLE_ID=dev.hyunseop.MenuPulse.Benchmark >/dev/null
[[ -x "$BIN_PATH" ]] || fail "Built executable was not found: $BIN_PATH"
echo "App version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"

SHOW_CPU_ARGUMENT="$(boolean_argument "$SHOW_CPU")"
SHOW_RAM_ARGUMENT="$(boolean_argument "$SHOW_RAM")"
SHOW_TEMPERATURE_ARGUMENT="$(boolean_argument "$SHOW_TEMPERATURE")"
SHOW_DISK_ARGUMENT="$(boolean_argument "$SHOW_DISK")"
SCENARIO_PARTS=()
[[ "$SHOW_CPU" == "0" ]] || SCENARIO_PARTS+=(CPU)
[[ "$SHOW_RAM" == "0" ]] || SCENARIO_PARTS+=(RAM)
[[ "$SHOW_TEMPERATURE" == "0" ]] || SCENARIO_PARTS+=(TEMP)
[[ "$SHOW_DISK" == "0" ]] || SCENARIO_PARTS+=(DISK)
SCENARIO="$(IFS=/; echo "${SCENARIO_PARTS[*]}")"

# The command-line pairs select the scenario through NSArgumentDomain.
# CFFIXED_USER_HOME isolates persistent defaults, including legacy-key cleanup.
CFFIXED_USER_HOME="$BENCHMARK_HOME" \
  MENU_PULSE_DISABLE_LOGIN_ITEM_MIGRATION=1 \
  "$BIN_PATH" \
  -showCPU "$SHOW_CPU_ARGUMENT" \
  -showRAM "$SHOW_RAM_ARGUMENT" \
  -showTemperature "$SHOW_TEMPERATURE_ARGUMENT" \
  -showDisk "$SHOW_DISK_ARGUMENT" \
  -temperatureUnit C \
  -cpuRAMRefreshIntervalSeconds "$CPU_RAM_REFRESH_INTERVAL" \
  -temperatureRefreshIntervalSeconds "$TEMPERATURE_REFRESH_INTERVAL" \
  -diskRefreshIntervalSeconds "$DISK_REFRESH_INTERVAL" \
  -hasCompletedOpenAtLoginPrompt YES \
  >"$LOG_FILE" 2>&1 &
BENCHMARK_PID=$!

sleep 0.2
if ! kill -0 "$BENCHMARK_PID" >/dev/null 2>&1; then
  echo "Menu Pulse exited during startup:" >&2
  sed -n '1,80p' "$LOG_FILE" >&2
  exit 1
fi

echo "Scenario: $SCENARIO"
if [[ "$SHOW_CPU" == "1" || "$SHOW_RAM" == "1" ]]; then
  echo "CPU/RAM refresh interval: ${CPU_RAM_REFRESH_INTERVAL}s"
fi
if [[ "$SHOW_TEMPERATURE" == "1" ]]; then
  echo "Temperature refresh interval: ${TEMPERATURE_REFRESH_INTERVAL}s"
fi
if [[ "$SHOW_DISK" == "1" ]]; then
  echo "Disk refresh interval: ${DISK_REFRESH_INTERVAL}s"
fi
echo "Benchmark PID: $BENCHMARK_PID (existing Menu Pulse processes are untouched)"
echo "Warm-up: ${WARMUP}s"

if (( WARMUP > 0 )); then
  sleep "$WARMUP"
fi

if ! kill -0 "$BENCHMARK_PID" >/dev/null 2>&1; then
  echo "Menu Pulse exited during warm-up:" >&2
  sed -n '1,80p' "$LOG_FILE" >&2
  exit 1
fi

SAMPLE_COUNT=$(( (DURATION + INTERVAL - 1) / INTERVAL ))
echo "Measurement: ${DURATION}s (${SAMPLE_COUNT} samples, ${INTERVAL}s sample interval)"
printf 'sample pcpu rss_kib\n' > "$SAMPLE_FILE"

for ((sample = 1; sample <= SAMPLE_COUNT; sample += 1)); do
  if ! kill -0 "$BENCHMARK_PID" >/dev/null 2>&1; then
    echo "Menu Pulse exited during measurement:" >&2
    sed -n '1,80p' "$LOG_FILE" >&2
    exit 1
  fi

  PROCESS_SAMPLE="$(ps -p "$BENCHMARK_PID" -o pcpu= -o rss=)"
  [[ -n "$PROCESS_SAMPLE" ]] || fail "Could not sample PID $BENCHMARK_PID."
  awk -v sample="$sample" '{ print sample, $1, $2 }' <<< "$PROCESS_SAMPLE" >> "$SAMPLE_FILE"

  ELAPSED=$(( (sample - 1) * INTERVAL ))
  REMAINING=$(( DURATION - ELAPSED ))
  SLEEP_TIME="$INTERVAL"
  if (( REMAINING < INTERVAL )); then
    SLEEP_TIME="$REMAINING"
  fi
  sleep "$SLEEP_TIME"
done

awk '
  NR > 1 {
    cpu_sum += $2
    rss_sum += $3
    if (count == 0 || $2 > cpu_max) cpu_max = $2
    if (count == 0 || $3 > rss_max) rss_max = $3
    count += 1
  }
  END {
    if (count == 0) exit 1
    printf "Samples collected: %d\n", count
    printf "CPU sample average: %.3f%%\n", cpu_sum / count
    printf "CPU sample maximum: %.3f%%\n", cpu_max
    printf "RSS average: %.1f MiB\n", (rss_sum / count) / 1024
    printf "RSS maximum: %.1f MiB\n", rss_max / 1024
  }
' "$SAMPLE_FILE"

PRIVATE_DIRTY=""
if command -v vmmap >/dev/null 2>&1 && vmmap -summary "$BENCHMARK_PID" > "$VMMAP_FILE" 2>&1; then
  PRIVATE_DIRTY="$(
    awk '
      function to_mib(value) {
        unit = substr(value, length(value), 1)
        amount = substr(value, 1, length(value) - 1) + 0
        if (unit == "K") return amount / 1024
        if (unit == "M") return amount
        if (unit == "G") return amount * 1024
        return value / 1024 / 1024
      }
      /^TOTAL[[:space:]]|^TOTAL, minus reserved VM space/ {
        count = 0
        for (i = 1; i <= NF; i += 1) {
          if ($i ~ /^[0-9.]+[KMG]?$/) sizes[++count] = $i
        }
        if (count >= 3) dirty = to_mib(sizes[3])
      }
      END { if (dirty != "") printf "%.1f MiB", dirty }
    ' "$VMMAP_FILE"
  )"
else
  echo "vmmap unavailable or failed; Private dirty could not be measured." >> "$VMMAP_FILE"
fi

if [[ -n "$PRIVATE_DIRTY" ]]; then
  echo "Private dirty (vmmap DIRTY total, end of run): $PRIVATE_DIRTY"
else
  echo "Private dirty: unavailable"
fi

APP_SIZE_KB="$(du -sk "$APP_PATH" | awk '{ print $1 }')"
awk -v size_kb="$APP_SIZE_KB" 'BEGIN { printf "App disk usage: %.1f MiB\n", size_kb / 1024 }'
echo "Completed (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
