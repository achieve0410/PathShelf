#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
source BuildSupport/audit-lock.sh

MODE="${1:-ci}"
if [[ "$MODE" == "release" ]]; then
  STABILIZE_SECONDS="${STABILIZE_SECONDS:-60}"
  DURATION_SECONDS="${DURATION_SECONDS:-600}"
else
  STABILIZE_SECONDS="${STABILIZE_SECONDS:-2}"
  DURATION_SECONDS="${DURATION_SECONDS:-3}"
fi

bash BuildSupport/build-app.sh >/dev/null
swift build --arch arm64 --product ProcessMetricsProbe >/dev/null

APP_EXECUTABLE="$ROOT_DIR/.build/PathShelf.app/Contents/MacOS/PathShelf"
PROBE_EXECUTABLE="$ROOT_DIR/.build/arm64-apple-macosx/debug/ProcessMetricsProbe"
AUDIT_ROOT="$ROOT_DIR/.build/idle-audit-$PPID-$$"
SETTINGS_FILE="$AUDIT_ROOT/settings.json"
BOOKMARKS_FILE="$AUDIT_ROOT/bookmarks.json"
GROUPS_FILE="$AUDIT_ROOT/groups.json"
VISIBLE_DIR="$AUDIT_ROOT/visible"
OUT="$ROOT_DIR/.build/idle-audit-output.txt"
APP_LOG="$AUDIT_ROOT/app.log"

mkdir -p "$VISIBLE_DIR"
JSON_VISIBLE_DIR="${VISIBLE_DIR//\\/\\\\}"
JSON_VISIBLE_DIR="${JSON_VISIBLE_DIR//\"/\\\"}"
cat >"$SETTINGS_FILE" <<JSON
{
  "panelPlacement" : { "mode" : "cursorAdjacent" },
  "shortcut" : { "keyCode" : 31, "modifiers" : ["control"] },
  "launchAtLogin" : false,
  "defaultLocationPath" : "$JSON_VISIBLE_DIR"
}
JSON

PATHSHELF_SETTINGS_PATH="$SETTINGS_FILE" \
PATHSHELF_BOOKMARKS_PATH="$BOOKMARKS_FILE" \
PATHSHELF_GROUPS_PATH="$GROUPS_FILE" \
  "$APP_EXECUTABLE" >"$APP_LOG" 2>&1 &
APP_PID=$!
trap 'kill "$APP_PID" >/dev/null 2>&1 || true; pathshelf_release_audit_lock' EXIT

sleep "$STABILIZE_SECONDS"
START="$("$PROBE_EXECUTABLE" "$APP_PID")"
sleep "$DURATION_SECONDS"
END="$("$PROBE_EXECUTABLE" "$APP_PID")"

kill -TERM "$APP_PID" >/dev/null 2>&1 || true
wait "$APP_PID" >/dev/null 2>&1 || true
trap - EXIT
pathshelf_release_audit_lock

field() {
  local name="$1"
  local line="$2"
  awk -v key="$name" '{for(i=1;i<=NF;i++) if($i ~ "^" key "="){split($i,a,"="); print a[2]}}' <<<"$line"
}

START_CPU_NS=$(( $(field user_ns "$START") + $(field system_ns "$START") ))
END_CPU_NS=$(( $(field user_ns "$END") + $(field system_ns "$END") ))
CPU_DELTA_NS=$(( END_CPU_NS - START_CPU_NS ))
READ_DELTA=$(( $(field disk_read_bytes "$END") - $(field disk_read_bytes "$START") ))
WRITE_DELTA=$(( $(field disk_write_bytes "$END") - $(field disk_write_bytes "$START") ))
PHYS_BYTES="$(field phys_footprint_bytes "$END")"
CPU_AVG="$(awk -v ns="$CPU_DELTA_NS" -v d="$DURATION_SECONDS" 'BEGIN { if (d == 0) print 0; else print (ns / (d * 1000000000)) * 100 }')"

printf 'IDLE_AUDIT mode=%s stabilize_s=%s duration_s=%s avg_cpu_percent=%.3f phys_footprint_bytes=%s disk_read_bytes_delta=%s disk_write_bytes_delta=%s source=proc_pid_rusage\n' \
  "$MODE" "$STABILIZE_SECONDS" "$DURATION_SECONDS" "$CPU_AVG" "$PHYS_BYTES" "$READ_DELTA" "$WRITE_DELTA" | tee "$OUT"

awk -v v="$CPU_AVG" 'BEGIN { if (v > 0.2) exit 1 }'
awk -v v="$PHYS_BYTES" 'BEGIN { if (v > 157286400) exit 1 }'
awk -v v="$READ_DELTA" 'BEGIN { if (v != 0) exit 1 }'
awk -v v="$WRITE_DELTA" 'BEGIN { if (v != 0) exit 1 }'
