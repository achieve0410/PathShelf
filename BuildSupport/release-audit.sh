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

APP_EXECUTABLE=".build/PathShelf.app/Contents/MacOS/PathShelf"
APP_ENTITLEMENTS=".build/PathShelf.app/Contents/Resources/PathShelf.entitlements"

plutil -lint BuildSupport/Info.plist BuildSupport/PathShelf.entitlements .build/PathShelf.app/Contents/Info.plist "$APP_ENTITLEMENTS"
file "$APP_EXECUTABLE" | tee .build/release-file-audit.txt
grep -q "Mach-O 64-bit executable arm64" .build/release-file-audit.txt
codesign --verify --deep --strict --verbose=2 .build/PathShelf.app

if plutil -p "$APP_ENTITLEMENTS" | rg "network"; then
  echo "Network entitlement found" >&2
  exit 1
fi

if otool -L "$APP_EXECUTABLE" | rg "CFNetwork|Network\\.framework|libcurl"; then
  echo "Forbidden network client framework linked" >&2
  exit 1
fi

if nm -m "$APP_EXECUTABLE" 2>/dev/null | rg "getaddrinfo|gethostbyname|gethostbyaddr|CFHost|NWResolver|URLSession|NWConnection|NWPathMonitor|CFNetwork"; then
  echo "Forbidden network or DNS symbol found" >&2
  exit 1
fi

if rg -n "getaddrinfo|gethostbyname|gethostbyaddr|CFHost|NWResolver|URLSession|import Network|NWConnection|NWPathMonitor|CFNetwork|NSEvent\\.addGlobalMonitorForEvents|CGEventTap|CGPreflightListenEventAccess|CGRequestListenEventAccess|AXIsProcessTrusted|AXUIElement(Create|Copy|Perform)|AXObserver(Create|AddNotification)|kAXTrustedCheckOptionPrompt|import ApplicationServices" Sources Package.swift; then
  echo "Forbidden source pattern found" >&2
  exit 1
fi

BuildSupport/network-audit.sh

echo "RELEASE_AUDIT passed"
