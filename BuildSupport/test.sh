#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift run ContractTests
swift run ServiceContractTests
swift run PanelContractTests
swift run EventContractTests

if rg -n "NSEvent\\.addGlobalMonitorForEvents|CGEventTap|AXIsProcessTrusted|Accessibility" Sources Package.swift; then
  echo "Forbidden global event or Accessibility path found" >&2
  exit 1
fi

if ! rg -n "RegisterEventHotKey|UnregisterEventHotKey|import Carbon\\.HIToolbox" Sources/PanelFeature Sources/AppShell >/dev/null; then
  echo "Carbon hotkey compile proof symbols were not found" >&2
  exit 1
fi

if rg -n "URLSession|import Network|NWConnection|NWPathMonitor|CFNetwork" Sources Package.swift; then
  echo "Forbidden app-initiated network client path found" >&2
  exit 1
fi

if rg -n "Timer\\.scheduledTimer|DispatchSource\\.makeTimerSource|while true" Sources; then
    echo "Forbidden polling/timer loop found in service targets" >&2
    exit 1
fi

if rg -n "explicitMove:\\s*false" Sources/AppShell; then
  echo "Drop move intent is hard-coded false in AppShell" >&2
  exit 1
fi

if ! rg -n "modifierFlags\\.contains\\(\\.control\\)|Drop copies; hold Control to move" Sources/AppShell >/dev/null; then
  echo "Drop move Control modifier or user hint is missing" >&2
  exit 1
fi

echo "Static hotkey audit passed"
echo "Static service audit passed"
echo "Static drop intent audit passed"
