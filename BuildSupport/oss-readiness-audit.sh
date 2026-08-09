#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  printf 'ERROR required-tool=rg missing; install ripgrep before running %s\n' "$0" >&2
  exit 127
fi

OUTPUT_FILE="$ROOT_DIR/.build/oss-readiness-audit-output.txt"
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

require_file() {
  local path="$1"
  if [[ -s "$path" ]]; then
    pass "required-file=$path"
  else
    fail "required-file=$path"
  fi
}

required_files=(
  "CODE_OF_CONDUCT.md"
  "GOVERNANCE.md"
  "MAINTAINERS.md"
  "CHANGELOG.md"
  "SUPPORT.md"
  "ROADMAP.md"
  "docs/RELEASING.md"
  "docs/MAINTAINER_WORKFLOWS.md"
  ".github/ISSUE_TEMPLATE/bug_report.yml"
  ".github/ISSUE_TEMPLATE/feature_request.yml"
  ".github/ISSUE_TEMPLATE/config.yml"
  ".github/pull_request_template.md"
  ".github/dependabot.yml"
)

for path in "${required_files[@]}"; do
  require_file "$path"
done

tracked_internal="$(
  while IFS= read -r path; do
    if [[ -e "$path" ]]; then
      printf '%s\n' "$path"
    fi
  done < <(
    git ls-files \
      '.omx/**' \
      '.omo/**' \
      '.gjc/**'
  )
)"
if [[ -z "$tracked_internal" ]]; then
  pass "tracked-internal-artifacts=0"
else
  fail "tracked-internal-artifacts=$(wc -l <<<"$tracked_internal" | tr -d ' ')"
fi

reference_artifacts="$(
  git grep -l -E \
    'folder-hub-clone|Folder Hub Clone|finderhub\.app' \
    -- . ':!.build' ':!BuildSupport/oss-readiness-audit.sh' 2>/dev/null || true
)"
if [[ -z "$reference_artifacts" ]]; then
  pass "tracked-reference-artifacts=0"
else
  fail "tracked-reference-artifacts=$(wc -l <<<"$reference_artifacts" | tr -d ' ')"
fi

public_files=(
  "README.md"
  "CONTRIBUTING.md"
  "SECURITY.md"
  "CODE_OF_CONDUCT.md"
  "GOVERNANCE.md"
  "MAINTAINERS.md"
  "CHANGELOG.md"
  "SUPPORT.md"
  "ROADMAP.md"
  "docs/RELEASING.md"
  "docs/MAINTAINER_WORKFLOWS.md"
  ".github/pull_request_template.md"
)
existing_public_files=()
for path in "${public_files[@]}"; do
  if [[ -f "$path" ]]; then
    existing_public_files+=("$path")
  fi
done

if ((${#existing_public_files[@]} > 0)) \
  && rg -n 'YOUR_USERNAME|TODO_REPLACE|REPLACE_ME|example\.com|TBD' \
    "${existing_public_files[@]}" >/dev/null; then
  fail "public-placeholders=present"
else
  pass "public-placeholders=0"
fi

if rg -F '../../security/advisories/new' SECURITY.md >/dev/null; then
  pass "private-security-reporting=actionable"
else
  fail "private-security-reporting=missing"
fi

if rg -U 'permissions:\n  contents: read' .github/workflows/ci.yml >/dev/null \
  && rg -F 'concurrency:' .github/workflows/ci.yml >/dev/null \
  && rg -F 'timeout-minutes:' .github/workflows/ci.yml >/dev/null \
  && rg '^[[:space:]]*uses:[[:space:]]*actions/checkout@[0-9a-fA-F]{40}[[:space:]]*$' \
    .github/workflows/ci.yml >/dev/null; then
  pass "ci-hardening=present"
else
  fail "ci-hardening=incomplete"
fi

if [[ -f ".github/dependabot.yml" ]] \
  && rg -F 'package-ecosystem: "github-actions"' .github/dependabot.yml >/dev/null; then
  pass "github-actions-dependabot=present"
else
  fail "github-actions-dependabot=missing"
fi

if ((failures > 0)); then
  printf 'OSS_READINESS_AUDIT failed count=%s\n' "$failures" | tee -a "$OUTPUT_FILE" >&2
  exit 1
fi

printf 'OSS_READINESS_AUDIT passed\n' | tee -a "$OUTPUT_FILE"
