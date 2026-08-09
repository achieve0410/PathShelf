#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  printf 'ERROR required-tool=rg missing; install ripgrep before running %s\n' "$0" >&2
  exit 127
fi

source BuildSupport/audit-lock.sh

bash BuildSupport/build-app.sh >/dev/null

APP_EXECUTABLE="$ROOT_DIR/.build/PathShelf.app/Contents/MacOS/PathShelf"
AUDIT_ROOT="$ROOT_DIR/.build/network-audit-$PPID-$$"
OUTPUT_FILE="$ROOT_DIR/.build/network-audit-output.txt"
SETTINGS_FILE="$AUDIT_ROOT/settings.json"
APP_LOG="$AUDIT_ROOT/app.log"
LSOF_FILE="$AUDIT_ROOT/lsof.txt"
NETTOP_FILE="$AUDIT_ROOT/nettop.txt"
NM_FILE="$AUDIT_ROOT/nm.txt"

mkdir -p "$AUDIT_ROOT"
cat >"$SETTINGS_FILE" <<'JSON'
{
  "panelPlacement" : { "mode" : "cursorAdjacent" },
  "shortcut" : { "keyCode" : 31, "modifiers" : ["control"] },
  "launchAtLogin" : false
}
JSON

PATHSHELF_SETTINGS_PATH="$SETTINGS_FILE" "$APP_EXECUTABLE" >"$APP_LOG" 2>&1 &
APP_PID=$!
trap 'kill "$APP_PID" >/dev/null 2>&1 || true; pathshelf_release_audit_lock' EXIT

fail_with_app_log() {
  local message="$1"
  local status="${2:-unknown}"
  echo "NETWORK_AUDIT failed: $message status=$status" >&2
  if [[ -s "$APP_LOG" ]]; then
    echo "NETWORK_AUDIT app log:" >&2
    cat "$APP_LOG" >&2
  fi
  exit 1
}

ensure_app_alive() {
  local stage="$1"
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    local status=0
    wait "$APP_PID" >/dev/null 2>&1 || status=$?
    trap - EXIT
    pathshelf_release_audit_lock
    fail_with_app_log "app exited during $stage" "$status"
  fi
}

sleep 1
ensure_app_alive "startup observation"
: >"$LSOF_FILE"
LSOF_SAMPLES=0
for _ in 1 2 3 4 5; do
  ensure_app_alive "lsof observation"
  if command -v lsof >/dev/null 2>&1; then
    LSOF_SAMPLES=$((LSOF_SAMPLES + 1))
    lsof -nP -a -p "$APP_PID" -iTCP -iUDP >>"$LSOF_FILE" || true
  fi
  sleep 0.2
done
ensure_app_alive "lsof observation"

NETTOP_SAMPLES=0
: >"$NETTOP_FILE"
if command -v nettop >/dev/null 2>&1; then
  ensure_app_alive "nettop observation"
  NETTOP_SAMPLES=1
  nettop -n -x -P -L 1 -p "$APP_PID" >"$NETTOP_FILE" 2>/dev/null || true
  ensure_app_alive "nettop observation"
fi

kill -TERM "$APP_PID" >/dev/null 2>&1 || true
wait "$APP_PID" >/dev/null 2>&1 || TERMINATION_STATUS=$?
trap - EXIT
pathshelf_release_audit_lock
TERMINATION_STATUS="${TERMINATION_STATUS:-0}"
if [[ "$TERMINATION_STATUS" != "0" && "$TERMINATION_STATUS" != "143" ]]; then
  fail_with_app_log "app exited nonzero after graceful termination" "$TERMINATION_STATUS"
fi

nm -m "$APP_EXECUTABLE" >"$NM_FILE" 2>/dev/null || true

DNS_API_SYMBOLS=0
if rg "getaddrinfo|gethostbyname|gethostbyaddr|CFHost|NWResolver|URLSession|NWConnection|NWPathMonitor|CFNetwork" "$NM_FILE" >/dev/null; then
  DNS_API_SYMBOLS=1
fi
if rg -n "getaddrinfo|gethostbyname|gethostbyaddr|CFHost|NWResolver|URLSession|import Network|NWConnection|NWPathMonitor|CFNetwork" Sources Package.swift >/dev/null; then
  DNS_API_SYMBOLS=1
fi

LSOF_SOCKET_LINES=0
if [[ -s "$LSOF_FILE" ]]; then
  LSOF_SOCKET_LINES="$(wc -l <"$LSOF_FILE" | tr -d ' ')"
fi

RUNTIME_SOCKET_BYTES=0
if [[ -s "$NETTOP_FILE" ]]; then
  RUNTIME_SOCKET_BYTES="$(awk -F, '
    NR == 1 {
      for (i = 1; i <= NF; i++) {
        if ($i == "bytes_in") bytesIn = i
        if ($i == "bytes_out") bytesOut = i
      }
      next
    }
    bytesIn > 0 {
      inValue = $bytesIn == "" ? 0 : $bytesIn
      outValue = $bytesOut == "" ? 0 : $bytesOut
      total += inValue + outValue
    }
    END { printf "%.0f", total + 0 }
  ' "$NETTOP_FILE")"
fi

printf 'NETWORK_AUDIT lsof_socket_lines=%s lsof_samples=%s nettop_samples=%s dns_api_symbols=%s runtime_socket_bytes=%s source=lsof_nettop_nm_source_scan\n' \
  "$LSOF_SOCKET_LINES" "$LSOF_SAMPLES" "$NETTOP_SAMPLES" "$DNS_API_SYMBOLS" "$RUNTIME_SOCKET_BYTES" | tee "$OUTPUT_FILE"

if [[ "$LSOF_SOCKET_LINES" != "0" || "$DNS_API_SYMBOLS" != "0" || "$RUNTIME_SOCKET_BYTES" != "0" ]]; then
  cat "$LSOF_FILE"
  cat "$NETTOP_FILE"
  fail_with_app_log "app-owned network path observed or linked" 0
fi
