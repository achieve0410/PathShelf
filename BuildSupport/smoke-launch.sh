#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
source BuildSupport/audit-lock.sh
APP_EXECUTABLE="$ROOT_DIR/.build/PathShelf.app/Contents/MacOS/PathShelf"
OUTPUT_FILE="$ROOT_DIR/.build/smoke-launch-output.txt"
SMOKE_ROOT="$ROOT_DIR/.build/smoke-$PPID-$$"
SETTINGS_FILE="$SMOKE_ROOT/smoke-settings.json"
BOOKMARKS_FILE="$SMOKE_ROOT/smoke-bookmarks.json"
GROUPS_FILE="$SMOKE_ROOT/smoke-favorite-groups.json"
FIXTURE_DIR="$SMOKE_ROOT/fixture"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Missing app executable: $APP_EXECUTABLE" >&2
  exit 1
fi

mkdir -p "$SMOKE_ROOT"

cat >"$SETTINGS_FILE" <<'JSON'
{
  "panelPlacement" : {
    "mode" : "activeDisplayTopCenter"
  },
  "shortcut" : {
    "keyCode" : 31,
    "modifiers" : [
      "control"
    ]
  },
  "launchAtLogin" : false
}
JSON

PATHSHELF_SMOKE=1 \
PATHSHELF_SETTINGS_PATH="$SETTINGS_FILE" \
PATHSHELF_BOOKMARKS_PATH="$BOOKMARKS_FILE" \
PATHSHELF_GROUPS_PATH="$GROUPS_FILE" \
PATHSHELF_SMOKE_FIXTURE="$FIXTURE_DIR" \
"$APP_EXECUTABLE" >"$OUTPUT_FILE" 2>&1 &
APP_PID=$!

for _ in {1..50}; do
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

grep -q "SMOKE hotkeyRegistered=true" "$OUTPUT_FILE"
grep -q "SMOKE fallbackReady=true" "$OUTPUT_FILE"
grep -q "SMOKE statusIconReady=true" "$OUTPUT_FILE"
grep -q "SMOKE betaFeedbackEntryReady=true" "$OUTPUT_FILE"
grep -q "SMOKE welcomeVisible=true" "$OUTPUT_FILE"
grep -q "SMOKE browserPreferencesReady=true" "$OUTPUT_FILE"
grep -q "SMOKE configurationTransferReady=true" "$OUTPUT_FILE"
grep -q "SMOKE configurationTransferAccessibilityReady=true" "$OUTPUT_FILE"
grep -q "SMOKE configurationRollbackFailureMessageReady=true" "$OUTPUT_FILE"
grep -q "SMOKE keyboardReauthorizationReady=true" "$OUTPUT_FILE"
grep -q "SMOKE keyboardReauthorizationTargetingReady=true" "$OUTPUT_FILE"
grep -q "SMOKE keyboardReauthorizationPreservesBrowserState=true" "$OUTPUT_FILE"
grep -q "SMOKE recoveredFavoriteWarningHidden=true" "$OUTPUT_FILE"
grep -q "SMOKE reopenPanelVisible=true" "$OUTPUT_FILE"
grep -q "SMOKE loadedPlacement=activeDisplayTopCenter" "$OUTPUT_FILE"
grep -q "SMOKE loadedShortcutValid=true" "$OUTPUT_FILE"
grep -q "SMOKE settingsCaptureReady=true" "$OUTPUT_FILE"
grep -q "SMOKE panelShown=true" "$OUTPUT_FILE"
grep -q "SMOKE panelFocused=true" "$OUTPUT_FILE"
grep -q "SMOKE appNameVisible=true" "$OUTPUT_FILE"
grep -q "SMOKE layoutReady=true" "$OUTPUT_FILE"
grep -q "SMOKE interactionsReady=true" "$OUTPUT_FILE"
grep -q "SMOKE searchControlReady=true" "$OUTPUT_FILE"
grep -q "SMOKE searchAccessibilityReady=true" "$OUTPUT_FILE"
grep -q "SMOKE searchKeyboardFocusReady=true" "$OUTPUT_FILE"
grep -q "SMOKE searchEscapeClearReady=true" "$OUTPUT_FILE"
grep -q "SMOKE favoriteAddControlReady=true" "$OUTPUT_FILE"
grep -q "SMOKE favoriteReturnActivationReady=true" "$OUTPUT_FILE"
grep -q "SMOKE favoriteAccessibilityReady=true" "$OUTPUT_FILE"
grep -q "SMOKE loadingStateReady=true" "$OUTPUT_FILE"
grep -q "SMOKE visibleDirectoryRefreshStable=true" "$OUTPUT_FILE"
grep -q "SMOKE filterNarrowsItems=true" "$OUTPUT_FILE"
grep -q "SMOKE filterNoResultsReady=true" "$OUTPUT_FILE"
grep -q "SMOKE filterClearRestores=true" "$OUTPUT_FILE"
grep -q "SMOKE filterCaptureReady=true" "$OUTPUT_FILE"
grep -q "SMOKE pathBarBoundaryPreserved=true" "$OUTPUT_FILE"
grep -q "SMOKE pathBarBoundaryCaptureReady=true" "$OUTPUT_FILE"
grep -q "SMOKE thumbnailRenderingPolicyReady=true" "$OUTPUT_FILE"
grep -q "SMOKE interactionProbePassed=true" "$OUTPUT_FILE"
grep -q "SMOKE panelResizable=true" "$OUTPUT_FILE"
grep -q "SMOKE panelUsesNormalWindowLevel=true" "$OUTPUT_FILE"
grep -q "SMOKE placementCalculationCount=3" "$OUTPUT_FILE"
grep -q "SMOKE toolbarControlCount=0" "$OUTPUT_FILE"
grep -q "SMOKE panelHidden=true" "$OUTPUT_FILE"
grep -q "SMOKE browserPathLoaded=true" "$OUTPUT_FILE"
grep -q "SMOKE browserFixtureEnumerated=true" "$OUTPUT_FILE"
grep -q "SMOKE browserSelectionClearedOnTeardown=true" "$OUTPUT_FILE"
grep -q "SMOKE browserConflictDefaultSkip=true" "$OUTPUT_FILE"
grep -q "SMOKE savedLocationRoundTrip=true" "$OUTPUT_FILE"
grep -q "SMOKE configurationTransferRoundTrip=true" "$OUTPUT_FILE"
grep -q "SMOKE configurationTransferFavoriteIncluded=true" "$OUTPUT_FILE"
grep -q "SMOKE configurationTransferMalformedRejected=true" "$OUTPUT_FILE"
grep -q "SMOKE previewTeardownCount=true" "$OUTPUT_FILE"
grep -q "SMOKE lifecycleObserversStopped=true" "$OUTPUT_FILE"
grep -q "SMOKE lifecycleTimersZero=true" "$OUTPUT_FILE"
grep -q "SMOKE lifecyclePostCloseCallbacksZero=true" "$OUTPUT_FILE"
grep -q "^PERF warm_ms=" "$OUTPUT_FILE"

echo "Smoke launch passed: PathShelf showed its welcome surface, registered hotkey, exposed fallback, showed panel, and terminated cleanly"
