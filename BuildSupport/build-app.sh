#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
SIGNING_IDENTITY="${PATHSHELF_SIGNING_IDENTITY:--}"
APP_DIR="$ROOT_DIR/.build/PathShelf.app"
EXECUTABLE_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

cd "$ROOT_DIR"
source BuildSupport/audit-lock.sh
swift build --arch arm64 -c "$CONFIGURATION"

mkdir -p "$EXECUTABLE_DIR" "$RESOURCES_DIR"
cp ".build/arm64-apple-macosx/$CONFIGURATION/PathShelf" "$EXECUTABLE_DIR/PathShelf"
cp "BuildSupport/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "BuildSupport/PathShelf.entitlements" "$RESOURCES_DIR/PathShelf.entitlements"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force \
    --sign - \
    --entitlements BuildSupport/PathShelf.entitlements \
    --timestamp=none \
    "$APP_DIR" >/dev/null
else
  codesign --force \
    --sign "$SIGNING_IDENTITY" \
    --entitlements BuildSupport/PathShelf.entitlements \
    --options runtime \
    --timestamp \
    "$APP_DIR" >/dev/null
fi
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
