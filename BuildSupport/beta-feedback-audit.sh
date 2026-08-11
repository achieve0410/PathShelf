#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_FILE="$ROOT_DIR/.build/beta-feedback-audit-output.txt"
FORM_PATH=".github/ISSUE_TEMPLATE/beta_feedback.yml"
PROTOCOL_PATH="docs/BETA_VALIDATION_PROTOCOL.md"
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

for path in "$FORM_PATH" "$PROTOCOL_PATH"; do
  if [[ -s "$path" ]]; then
    pass "required-file=$path"
  else
    fail "required-file=$path"
  fi
done

if ((failures > 0)); then
  printf 'BETA_FEEDBACK_AUDIT failed count=%s\n' "$failures" \
    | tee -a "$OUTPUT_FILE" >&2
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  printf 'ERROR required-tool=ruby missing\n' | tee -a "$OUTPUT_FILE" >&2
  exit 127
fi

ruby -ryaml -e '
  form = YAML.safe_load(File.read(ARGV.fetch(0)))
  fields = form.fetch("body").to_h { |field| [field["id"], field] }
  expected = {
    "workflow_frequency" => "dropdown",
    "setup_completed" => "dropdown",
    "week_two_use" => "dropdown",
    "one_time_price_intent" => "dropdown",
    "privacy_consent" => "checkboxes"
  }
  raise "unexpected field identifiers" unless fields.keys.sort == expected.keys.sort
  expected.each do |identifier, type|
    field = fields.fetch(identifier)
    raise "#{identifier} type" unless field.fetch("type") == type
    raise "#{identifier} required" unless field.dig("validations", "required") == true
    if type == "dropdown"
      options = field.fetch("attributes").fetch("options")
      raise "#{identifier} option type" unless options.all?(String)
    end
  end
  consent_options = fields.fetch("privacy_consent")
    .fetch("attributes")
    .fetch("options")
  raise "privacy consent option count" unless consent_options.length == 2
  raise "privacy consent option requirement" unless consent_options.all? {
    |option| option["required"] == true
  }
  puts "PASS form-field-ids=#{fields.keys.sort.join(",")}"
' "$FORM_PATH" | tee -a "$OUTPUT_FILE"

ruby -ryaml -e '
  document = File.read(ARGV.fetch(0))
  frontmatter = document.split(/^---\s*$/, 3).fetch(1)
  values = YAML.safe_load(frontmatter)
  expected = {
    "minimum_cohort_size" => 20,
    "follow_up_days" => 14,
    "minimum_week_two_active_rate" => 0.5,
    "minimum_paid_intent_rate" => 0.2,
    "one_time_price_usd" => 20
  }
  raise "protocol thresholds" unless values == expected
  puts "PASS protocol-thresholds=#{expected.values.join(",")}"
' "$PROTOCOL_PATH" | tee -a "$OUTPUT_FILE"

printf 'BETA_FEEDBACK_AUDIT passed\n' | tee -a "$OUTPUT_FILE"
