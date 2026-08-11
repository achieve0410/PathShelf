#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source BuildSupport/audit-lock.sh

OUTPUT_DIR="${PATHSHELF_RELEASE_OUTPUT_DIR:-$ROOT_DIR/.build/release}"
ARCHIVE_NAME="PathShelf-macos-arm64.zip"
ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
METADATA_PATH="$OUTPUT_DIR/PACKAGE-METADATA.txt"
APP_DIR="$ROOT_DIR/.build/PathShelf.app"

if [[ "${PATHSHELF_PACKAGE_EXISTING_APP:-0}" != "1" ]]; then
  CONFIGURATION=release bash BuildSupport/build-app.sh >/dev/null
else
  test -x "$APP_DIR/Contents/MacOS/PathShelf"
fi
codesign --verify --deep --strict "$APP_DIR"

signature_details="$(codesign -dvvv "$APP_DIR" 2>&1)"
distribution="notarized"
if grep -q "^Signature=adhoc$" <<<"$signature_details"; then
  if [[ "${PATHSHELF_ALLOW_ADHOC_QA:-0}" != "1" ]]; then
    echo "Refusing to package an ad-hoc app without PATHSHELF_ALLOW_ADHOC_QA=1" >&2
    exit 1
  fi
  distribution="local-qa-only"
else
  if ! grep -q "^Authority=Developer ID Application:" <<<"$signature_details"; then
    echo "Refusing to package an app without a Developer ID Application signature" >&2
    exit 1
  fi
  xcrun stapler validate "$APP_DIR"
  spctl --assess --type execute --verbose=2 "$APP_DIR"
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH" "$METADATA_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE_PATH"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$ARCHIVE_NAME" >"$ARCHIVE_NAME.sha256"
)
printf 'distribution=%s\narchitecture=arm64\n' "$distribution" >"$METADATA_PATH"

echo "RELEASE_PACKAGE created archive=$ARCHIVE_PATH distribution=$distribution"
