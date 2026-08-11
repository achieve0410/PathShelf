#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source BuildSupport/audit-lock.sh

AUDIT_ROOT="$(mktemp -d "$ROOT_DIR/.build/release-package-audit.XXXXXX")"
ARCHIVE_NAME="PathShelf-macos-arm64.zip"
ARCHIVE_PATH="$AUDIT_ROOT/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
METADATA_PATH="$AUDIT_ROOT/PACKAGE-METADATA.txt"
EXTRACT_ROOT="$AUDIT_ROOT/extracted"

cleanup_release_package_audit() {
  rm -rf "$AUDIT_ROOT"
  pathshelf_release_audit_lock
}
trap cleanup_release_package_audit EXIT

if [[ ! -x BuildSupport/package-release.sh ]]; then
  CONFIGURATION=release bash BuildSupport/build-app.sh
else
  set +e
  fail_closed_output="$(
    PATHSHELF_RELEASE_OUTPUT_DIR="$AUDIT_ROOT" \
      bash BuildSupport/package-release.sh 2>&1
  )"
  fail_closed_status=$?
  set -e
  if [[ "$fail_closed_status" -eq 0 ]]; then
    echo "FAIL release-package accepted an ad-hoc bundle without QA opt-in" >&2
    exit 1
  fi
  grep -q "Refusing to package an ad-hoc app without PATHSHELF_ALLOW_ADHOC_QA=1" \
    <<<"$fail_closed_output"

  PATHSHELF_ALLOW_ADHOC_QA=1 \
    PATHSHELF_RELEASE_OUTPUT_DIR="$AUDIT_ROOT" \
    bash BuildSupport/package-release.sh
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "FAIL release-package archive missing: $ARCHIVE_PATH" >&2
  exit 1
fi
if [[ ! -f "$CHECKSUM_PATH" ]]; then
  echo "FAIL release-package checksum missing: $CHECKSUM_PATH" >&2
  exit 1
fi
if [[ ! -f "$METADATA_PATH" ]]; then
  echo "FAIL release-package metadata missing: $METADATA_PATH" >&2
  exit 1
fi

grep -qx "distribution=local-qa-only" "$METADATA_PATH"
(
  cd "$AUDIT_ROOT"
  shasum -a 256 -c "$ARCHIVE_NAME.sha256"
)

mkdir -p "$EXTRACT_ROOT"
ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_ROOT"
test -x "$EXTRACT_ROOT/PathShelf.app/Contents/MacOS/PathShelf"
codesign --verify --deep --strict "$EXTRACT_ROOT/PathShelf.app"

echo "RELEASE_PACKAGE_AUDIT passed archive=$ARCHIVE_NAME distribution=local-qa-only"
