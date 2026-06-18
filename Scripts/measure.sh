#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DURATION="${DURATION:-30}"
INTERVAL="${INTERVAL:-3}"
APP_PATH="$ROOT_DIR/build/release/Menu Pulse.app"
PID="${PID:-}"
STARTED_APP=0

if [[ -z "$PID" ]]; then
  PID="$(pgrep -x MenuPulse | head -n 1 || true)"
fi

if [[ -z "$PID" ]]; then
  "$ROOT_DIR/Scripts/build-app.sh" >/dev/null
  open "$APP_PATH"
  STARTED_APP=1
  sleep 2
  PID="$(pgrep -x MenuPulse | head -n 1 || true)"
fi

if [[ -z "$PID" ]]; then
  echo "MenuPulse is not running." >&2
  exit 1
fi

cleanup() {
  if [[ "$STARTED_APP" == "1" ]]; then
    kill "$PID" >/dev/null 2>&1 || true
    sleep 1
    if ps -p "$PID" >/dev/null 2>&1; then
      kill -9 "$PID" >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT

SAMPLES=$(( DURATION / INTERVAL ))
if [[ "$SAMPLES" -lt 1 ]]; then
  SAMPLES=1
fi

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"; cleanup' EXIT

echo "Measuring MenuPulse PID $PID for ${DURATION}s (${SAMPLES} samples, ${INTERVAL}s interval)"
echo "sample pcpu rss_kb" > "$TMP_FILE"

for sample in $(seq 1 "$SAMPLES"); do
  if ! ps -p "$PID" >/dev/null; then
    echo "MenuPulse exited during measurement." >&2
    exit 1
  fi

  ps -o pcpu= -o rss= -p "$PID" | awk -v sample="$sample" '{ print sample, $1, $2 }' >> "$TMP_FILE"
  sleep "$INTERVAL"
done

awk '
  NR > 1 {
    cpu_sum += $2
    rss_sum += $3
    if ($2 > cpu_max) cpu_max = $2
    if ($3 > rss_max) rss_max = $3
    count += 1
  }
  END {
    if (count == 0) exit 1
    printf "CPU avg: %.3f%%\n", cpu_sum / count
    printf "CPU max: %.3f%%\n", cpu_max
    printf "RSS avg: %.1f MB\n", (rss_sum / count) / 1024
    printf "RSS max: %.1f MB\n", rss_max / 1024
  }
' "$TMP_FILE"

if command -v vmmap >/dev/null; then
  DIRTY_MB="$(
    vmmap -summary "$PID" 2>/dev/null | awk '
      function to_mb(value) {
        unit = substr(value, length(value), 1)
        amount = substr(value, 1, length(value) - 1) + 0
        if (unit == "K") return amount / 1024
        if (unit == "M") return amount
        if (unit == "G") return amount * 1024
        return value + 0
      }
      /TOTAL, minus reserved VM space/ {
        count = 0
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^[0-9.]+[KMG]$/) {
            sizes[++count] = $i
          }
        }
        if (count >= 3) {
          printf "%.1f", to_mb(sizes[3])
        }
        exit
      }
    '
  )"
  if [[ -n "$DIRTY_MB" ]]; then
    echo "Private dirty: ${DIRTY_MB} MB"
  fi
fi

if [[ -d "$APP_PATH" ]]; then
  file "$APP_PATH/Contents/MacOS/MenuPulse"
  otool -L "$APP_PATH/Contents/MacOS/MenuPulse"
  du -sh "$APP_PATH" "$APP_PATH/Contents/MacOS/MenuPulse" 2>/dev/null
fi

if [[ -f "$ROOT_DIR/dist/MenuPulse.dmg" ]]; then
  du -sh "$ROOT_DIR/dist/MenuPulse.dmg"
fi
