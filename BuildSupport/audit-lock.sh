#!/usr/bin/env bash

if [[ "${PATHSHELF_AUDIT_LOCK_HELD:-0}" != "1" ]]; then
  PATHSHELF_AUDIT_LOCK_DIR="${ROOT_DIR:-$(pwd)}/.build/pathshelf-audit.lock"
  PATHSHELF_AUDIT_LOCK_TIMEOUT_SECONDS="${PATHSHELF_AUDIT_LOCK_TIMEOUT_SECONDS:-120}"
  pathshelf_audit_lock_started_at="$(date +%s)"
  mkdir -p "$(dirname "$PATHSHELF_AUDIT_LOCK_DIR")"
  while ! mkdir "$PATHSHELF_AUDIT_LOCK_DIR" 2>/dev/null; do
    pathshelf_audit_lock_now="$(date +%s)"
    if (( pathshelf_audit_lock_now - pathshelf_audit_lock_started_at >= PATHSHELF_AUDIT_LOCK_TIMEOUT_SECONDS )); then
      echo "Timed out waiting for audit lock: $PATHSHELF_AUDIT_LOCK_DIR" >&2
      exit 1
    fi
    sleep 0.2
  done
  export PATHSHELF_AUDIT_LOCK_HELD=1
  export PATHSHELF_AUDIT_LOCK_DIR
  pathshelf_release_audit_lock() {
    rmdir "$PATHSHELF_AUDIT_LOCK_DIR" >/dev/null 2>&1 || true
  }
  trap pathshelf_release_audit_lock EXIT
else
  pathshelf_release_audit_lock() {
    :
  }
fi
