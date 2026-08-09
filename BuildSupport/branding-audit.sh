#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  printf 'ERROR required-tool=rg missing; install ripgrep before running %s\n' "$0" >&2
  exit 127
fi

OUTPUT_FILE="$ROOT_DIR/.build/branding-audit-output.txt"
mkdir -p "$(dirname "$OUTPUT_FILE")"
: >"$OUTPUT_FILE"

failures=0

pass() {
  printf 'PASS %s\n' "$1" | tee -a "$OUTPUT_FILE"
}

fail() {
  printf 'FAIL %s\n' "$1" | tee -a "$OUTPUT_FILE" >&2
  failures=$((failures + 1))
}

require_literal() {
  local path="$1"
  local literal="$2"
  local label="$3"
  if [[ -f "$path" ]] && rg -F "$literal" "$path" >/dev/null; then
    pass "$label"
  else
    fail "$label"
  fi
}

require_plist_value() {
  local key="$1"
  local expected="$2"
  local label="$3"
  local actual
  actual="$(plutil -extract "$key" raw -o - BuildSupport/Info.plist 2>/dev/null || true)"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label"
  fi
}

legacy_product="Offline""FilePanel"
legacy_environment="OFFLINE""_FILE_PANEL"
legacy_lower="offline""filepanel"
legacy_offline="off""line"
legacy_file="fi""le"
legacy_panel="pan""el"
legacy_separator="[[:space:]_.-]*"
legacy_pattern="${legacy_offline}${legacy_separator}${legacy_file}${legacy_separator}${legacy_panel}"
legacy_detector_samples="$(
  printf '%s\n' \
    "$legacy_product" \
    "${legacy_offline}_${legacy_file}-${legacy_panel}" \
    "${legacy_offline}--${legacy_file}__${legacy_panel}" \
    "${legacy_offline} _ ${legacy_file}-${legacy_panel}" \
    "${legacy_offline}.${legacy_file}.${legacy_panel}"
)"
if [[ "$(printf '%s\n' "$legacy_detector_samples" | rg -i -c -e "$legacy_pattern")" == "5" ]]; then
  pass "legacy-detector-variants=5"
else
  fail "legacy-detector-variants"
fi

legacy_files="$(
  rg -Il \
    --hidden \
    -g '!.git' \
    -g '!.git/**' \
    -g '!.build/**' \
    -g '!.omo/**' \
    -g '!.gjc/**' \
    -g '!.omx/**' \
    -i \
    -e "$legacy_pattern" \
    . || true
)"
if [[ -z "$legacy_files" ]]; then
  pass "legacy-identifiers=0"
else
  fail "legacy-identifiers=$(printf '%s\n' "$legacy_files" | awk 'NF' | wc -l | tr -d ' ')"
fi

reference_name="Folder"" Hub"
reference_domain="finderhub"".app"
reference_clone="folder-hub-""clone"
reference_files="$(
  rg -Il \
    --hidden \
    -g '!.git' \
    -g '!.git/**' \
    -g '!.build/**' \
    -g '!.omo/**' \
    -g '!.gjc/**' \
    -g '!.omx/**' \
    -g '!BuildSupport/oss-readiness-audit.sh' \
    -g '!BuildSupport/branding-audit.sh' \
    -e "${reference_name}|${reference_domain}|${reference_clone}" \
    . || true
)"
if [[ -z "$reference_files" ]]; then
  pass "reference-product-identifiers=0"
else
  fail "reference-product-identifiers=$(printf '%s\n' "$reference_files" | awk 'NF' | wc -l | tr -d ' ')"
fi

required_files=(
  "Sources/AppShell/PathShelfApp.swift"
  "BuildSupport/PathShelf.entitlements"
)
for path in "${required_files[@]}"; do
  if [[ -s "$path" ]]; then
    pass "required-file=$path"
  else
    fail "required-file=$path"
  fi
done

removed_files=(
  "Sources/AppShell/${legacy_product}App.swift"
  "BuildSupport/${legacy_product}.entitlements"
)
for path in "${removed_files[@]}"; do
  if [[ ! -e "$path" ]]; then
    pass "removed-file=$path"
  else
    fail "removed-file=$path"
  fi
done

require_literal "Package.swift" 'name: "PathShelf"' "package-name=PathShelf"
require_literal "Package.swift" '.executable(name: "PathShelf"' "executable-product=PathShelf"
require_plist_value "CFBundleExecutable" "PathShelf" "bundle-executable=PathShelf"
require_plist_value "CFBundleIdentifier" "io.github.achieve0410.PathShelf" "bundle-id=io.github.achieve0410.PathShelf"
require_plist_value "CFBundleName" "PathShelf" "bundle-name=PathShelf"
require_literal "README.md" "# PathShelf" "readme-title=PathShelf"
require_literal "LICENSE" "PathShelf contributors" "license-attribution=PathShelf"
require_literal "Sources/AppShell/PathShelfApp.swift" "PATHSHELF_" "environment-prefix=PATHSHELF"

vendor_open="Open""AI"
vendor_codex="Co""dex"
vendor_chat="Chat""GPT"
vendor_credits="API ""credits"
vendor_files="$(
  rg -Il \
    -e "(?i)${vendor_open}|${vendor_codex}|${vendor_chat}|${vendor_credits}" \
    MAINTAINERS.md \
    docs/MAINTAINER_WORKFLOWS.md || true
)"
if [[ -z "$vendor_files" ]]; then
  pass "vendor-specific-policy=0"
else
  fail "vendor-specific-policy=$(printf '%s\n' "$vendor_files" | awk 'NF' | wc -l | tr -d ' ')"
fi

ignore_patterns=(
  ".env*"
  "!.env.example"
  "*.p12"
  "*.pfx"
  "*.mobileprovision"
  "*.private.xcconfig"
)
for pattern in "${ignore_patterns[@]}"; do
  if rg -Fx "$pattern" .gitignore >/dev/null; then
    pass "ignore-pattern=$pattern"
  else
    fail "ignore-pattern=$pattern"
  fi
done

if ((failures > 0)); then
  printf 'BRANDING_AUDIT failed count=%s\n' "$failures" | tee -a "$OUTPUT_FILE" >&2
  exit 1
fi

printf 'BRANDING_AUDIT passed\n' | tee -a "$OUTPUT_FILE"
