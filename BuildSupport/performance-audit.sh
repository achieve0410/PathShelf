#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
source BuildSupport/audit-lock.sh

CONFIGURATION=release bash BuildSupport/build-app.sh >/dev/null

APP_EXECUTABLE="$ROOT_DIR/.build/PathShelf.app/Contents/MacOS/PathShelf"
PERF_ROOT="$ROOT_DIR/.build/perf-fixture-$PPID-$$"
VISIBLE_DIR="$PERF_ROOT/visible"
SETTINGS_FILE="$PERF_ROOT/settings.json"
BOOKMARKS_FILE="$PERF_ROOT/bookmarks.json"
OUTPUT_FILE="$ROOT_DIR/.build/performance-audit-output.txt"

cleanup_performance_audit() {
  rm -rf "$PERF_ROOT"
  pathshelf_release_audit_lock
}
trap cleanup_performance_audit EXIT

PATHSHELF_PERF_LINKER_PREFLIGHT=1 "$APP_EXECUTABLE"

mkdir -p "$VISIBLE_DIR"
for index in $(seq 0 999); do
  printf 'item %04d\n' "$index" >"$VISIBLE_DIR/item-$index.txt"
done

cat >"$SETTINGS_FILE" <<'JSON'
{
  "panelPlacement" : { "mode" : "cursorAdjacent" },
  "shortcut" : { "keyCode" : 31, "modifiers" : ["control"] },
  "launchAtLogin" : false
}
JSON

JSON_VISIBLE_DIR="${VISIBLE_DIR//\\/\\\\}"
JSON_VISIBLE_DIR="${JSON_VISIBLE_DIR//\"/\\\"}"
{
  printf '[\n'
  for index in $(seq 0 9); do
    if ((index > 0)); then
      printf ',\n'
    fi
    printf '  {\n'
    printf '    "availability" : "available",\n'
    printf '    "bookmark" : {\n'
    printf '      "data" : "",\n'
    printf '      "isSecurityScoped" : false,\n'
    printf '      "originalPath" : "%s"\n' "$JSON_VISIBLE_DIR"
    printf '    },\n'
    printf '    "displayName" : "Perf %d",\n' "$((index + 1))"
    printf '    "id" : "00000000-0000-4000-8000-%012d",\n' "$((index + 1))"
    printf '    "sortOrder" : %d\n' "$index"
    printf '  }'
  done
  printf '\n]\n'
} >"$BOOKMARKS_FILE"

START_NS="$(date +%s%N)"
PATHSHELF_PERF=1 \
PATHSHELF_PROCESS_START_NS="$START_NS" \
PATHSHELF_SETTINGS_PATH="$SETTINGS_FILE" \
PATHSHELF_BOOKMARKS_PATH="$BOOKMARKS_FILE" \
PATHSHELF_SMOKE_FIXTURE="$VISIBLE_DIR" \
PATHSHELF_PERF_FIXTURE="$VISIBLE_DIR" \
PATHSHELF_PERF_VISIBLE=1000 \
PATHSHELF_PERF_SAVED=10 \
"$APP_EXECUTABLE" >"$OUTPUT_FILE" 2>&1 &
APP_PID=$!

for _ in {1..100}; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if kill -0 "$APP_PID" 2>/dev/null; then
  kill -TERM "$APP_PID"
fi

wait "$APP_PID"
cat "$OUTPUT_FILE"

PERF_LINE="$(grep '^PERF ' "$OUTPUT_FILE")"
COLD_MS="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^cold_ms=/){split($i,a,"="); print a[2]}}' <<<"$PERF_LINE")"
APP_COLD_MS="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^app_cold_ms=/){split($i,a,"="); print a[2]}}' <<<"$PERF_LINE")"
WARM_P95_MS="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^warm_p95_ms=/){split($i,a,"="); print a[2]}}' <<<"$PERF_LINE")"
WARM_SAMPLES="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^warm_samples=/){split($i,a,"="); print a[2]}}' <<<"$PERF_LINE")"
PHYS_FOOTPRINT_BYTES="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^phys_footprint_bytes=/){split($i,a,"="); print a[2]}}' <<<"$PERF_LINE")"
RSS_BYTES="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^rss_bytes=/){split($i,a,"="); print a[2]}}' <<<"$PERF_LINE")"
VISIBLE_ITEMS="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^visible_items=/){split($i,a,"="); print a[2]}}' <<<"$PERF_LINE")"
SAVED_LOCATIONS="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^saved_locations=/){split($i,a,"="); print a[2]}}' <<<"$PERF_LINE")"
SELECTED_READY="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^selected_item_ready=/){split($i,a,"="); print a[2]}}' <<<"$PERF_LINE")"

[[ "$WARM_SAMPLES" == "20" ]]
[[ "$VISIBLE_ITEMS" == "1000" ]]
[[ "$SAVED_LOCATIONS" == "10" ]]
[[ "$SELECTED_READY" == "true" ]]
[[ "$PHYS_FOOTPRINT_BYTES" =~ ^[0-9]+$ ]]
((PHYS_FOOTPRINT_BYTES > 0))
awk -v v="$WARM_P95_MS" 'BEGIN { if (v > 150.0) exit 1 }'
awk -v v="$COLD_MS" 'BEGIN { if (v > 500.0) exit 1 }'
awk -v v="$PHYS_FOOTPRINT_BYTES" 'BEGIN { if (v > 157286400) exit 1 }'

printf 'PERFORMANCE_AUDIT linker_preflight=pass cold_ms=%s app_cold_ms=%s warm_p95_ms=%s warm_samples=%s phys_footprint_bytes=%s rss_bytes=%s visible_items=%s saved_locations=%s selected_item_ready=%s thresholds=pass definition=cold_shell_launch_to_first_selectable_row_app_cold_recorded_warm_invocation_to_first_selectable_row\n' \
  "$COLD_MS" "$APP_COLD_MS" "$WARM_P95_MS" "$WARM_SAMPLES" "$PHYS_FOOTPRINT_BYTES" "$RSS_BYTES" "$VISIBLE_ITEMS" "$SAVED_LOCATIONS" "$SELECTED_READY"
