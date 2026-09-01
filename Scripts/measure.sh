#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/release/Menu Pulse.app"
BIN_PATH="$APP_PATH/Contents/MacOS/MenuPulse"
DMG_PATH="$ROOT_DIR/dist/MenuPulse.dmg"

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
BENCHMARK_HOME=""
BENCHMARK_TEMP_ROOT=""
SAMPLE_FILE=""
LOG_FILE=""

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
  local benchmark_home_parent=""
  local expected_temp_parent=""

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

  [[ -z "$SAMPLE_FILE" ]] || rm -f "$SAMPLE_FILE"
  [[ -z "$LOG_FILE" ]] || rm -f "$LOG_FILE"

  if [[ -n "$BENCHMARK_HOME" && -d "$BENCHMARK_HOME" ]]; then
    benchmark_home_parent="$(cd "$(dirname "$BENCHMARK_HOME")" && pwd -P)"
    expected_temp_parent="$BENCHMARK_TEMP_ROOT"
  fi
  if [[ -n "$BENCHMARK_HOME" &&
        "$(basename "$BENCHMARK_HOME")" == menu-pulse-benchmark-home.* &&
        "$benchmark_home_parent" == "$expected_temp_parent" ]]; then
    /bin/rm -rf -- "$BENCHMARK_HOME"
  fi
  BENCHMARK_HOME=""
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

echo "Building Menu Pulse for measurement..."
"$ROOT_DIR/Scripts/build-app.sh" >/dev/null
[[ -x "$BIN_PATH" ]] || fail "Built executable was not found: $BIN_PATH"

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

SAMPLE_FILE="$(mktemp "$BENCHMARK_TEMP_ROOT/menu-pulse-samples.XXXXXX")"
LOG_FILE="$(mktemp "$BENCHMARK_TEMP_ROOT/menu-pulse-measure.XXXXXX")"
BENCHMARK_HOME="$(mktemp -d "$BENCHMARK_TEMP_ROOT/menu-pulse-benchmark-home.XXXXXX")"
/bin/mkdir -p "$BENCHMARK_HOME/Library/Preferences"

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
printf 'sample pcpu rss_kb\n' > "$SAMPLE_FILE"

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
    printf "CPU average: %.3f%%\n", cpu_sum / count
    printf "CPU maximum: %.3f%%\n", cpu_max
    printf "RSS average: %.1f MB\n", (rss_sum / count) / 1024
    printf "RSS maximum: %.1f MB\n", rss_max / 1024
  }
' "$SAMPLE_FILE"

PRIVATE_DIRTY=""
if command -v vmmap >/dev/null 2>&1; then
  PRIVATE_DIRTY="$(
    vmmap -summary "$BENCHMARK_PID" 2>/dev/null | awk '
      function to_mb(value) {
        unit = substr(value, length(value), 1)
        amount = substr(value, 1, length(value) - 1) + 0
        if (unit == "K") return amount / 1024
        if (unit == "M") return amount
        if (unit == "G") return amount * 1024
        return value / 1024 / 1024
      }
      /^TOTAL, minus reserved VM space/ {
        count = 0
        for (i = 1; i <= NF; i += 1) {
          if ($i ~ /^[0-9.]+[KMG]?$/) sizes[++count] = $i
        }
        if (count >= 3) printf "%.1f MB", to_mb(sizes[3])
        exit
      }
    '
  )"
fi

if [[ -n "$PRIVATE_DIRTY" ]]; then
  echo "Private dirty: $PRIVATE_DIRTY"
else
  echo "Private dirty: unavailable"
fi

APP_SIZE_KB="$(du -sk "$APP_PATH" | awk '{ print $1 }')"
awk -v size_kb="$APP_SIZE_KB" 'BEGIN { printf "App size: %.1f MB\n", size_kb / 1024 }'

if [[ -f "$DMG_PATH" ]]; then
  DMG_SIZE_BYTES="$(stat -f '%z' "$DMG_PATH")"
  awk -v size_bytes="$DMG_SIZE_BYTES" 'BEGIN { printf "DMG size: %.1f MB\n", size_bytes / 1024 / 1024 }'
else
  echo "DMG size: unavailable ($DMG_PATH not found)"
fi
