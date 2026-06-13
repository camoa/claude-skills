#!/usr/bin/env bash
# gate-prompts-vs-inline.sh — verify v1.2 templates are byte-identical to inline literals.
#
# Scope: only templates that exist in BOTH places (inline in command body + reference doc).
# Currently 2 templates: `review-gate-fail`, `review-summary`. Authored as inline literals
# in commands/review.md FIRST (PR #138), then copied to references/gate-hardening-prompts.md
# v1.2 (PR plumbing_docs_tests). The other 5 v1.0/v1.1 templates (pre-analysis-decision,
# coverage-mapping-fail, skill-review-decision, plugin-validate-decision,
# phase-command-bypass-acknowledge) have NO inline counterparts — they live only in
# references/gate-hardening-prompts.md. This test does NOT cover those 5; baseline-byte
# equivalence for them is enforced by tests/gate-prompts-literal.sh against git main.
#
# Usage:
#   tests/gate-prompts-vs-inline.sh   # exit 0 on identical, 1 on drift
#
# Companion to tests/gate-prompts-literal.sh which compares against git baseline.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_FILE="${PLUGIN_ROOT}/references/gate-hardening-prompts.md"
COMMAND_FILE="${PLUGIN_ROOT}/commands/review.md"

# Templates that should appear inline in commands/review.md
TEMPLATE_IDS=(
  "review-gate-fail"
  "review-summary"
)

# Extract a template's literal block from gate-hardening-prompts.md
# under "## Template ID: `<id>`" heading.
extract_from_templates() {
  local id="$1"
  awk -v id="$id" '
    BEGIN { state="seek"; }
    state == "seek" && $0 ~ "^## Template ID: `" id "`$" { state="hdr"; next }
    state == "hdr" && /^```$/ { state="in"; next }
    state == "in" && /^```$/ { exit }
    state == "in" { print }
  ' "$TEMPLATES_FILE"
}

# Extract from commands/review.md by its inline ID line:
#   `review-gate-fail`:
#   ```
#   <literal>
#   ```
extract_from_command() {
  local id="$1"
  awk -v id="$id" '
    BEGIN { state="seek"; }
    state == "seek" && $0 ~ "^`" id "`:$" { state="hdr"; next }
    state == "hdr" && /^```$/ { state="in"; next }
    state == "in" && /^```$/ { exit }
    state == "in" { print }
  ' "$COMMAND_FILE"
}

LB_TMP=$(mktemp)
LC_TMP=$(mktemp)
trap 'rm -f "$LB_TMP" "$LC_TMP"' EXIT

FAIL=0
for id in "${TEMPLATE_IDS[@]}"; do
  extract_from_templates "$id" > "$LB_TMP"
  extract_from_command   "$id" > "$LC_TMP"
  if [ ! -s "$LB_TMP" ]; then
    printf 'FAIL: template %s missing in references/gate-hardening-prompts.md\n' "$id" >&2
    FAIL=1
    continue
  fi
  if [ ! -s "$LC_TMP" ]; then
    printf 'FAIL: inline literal %s missing in commands/review.md\n' "$id" >&2
    FAIL=1
    continue
  fi
  if ! cmp -s "$LB_TMP" "$LC_TMP"; then
    printf 'FAIL: drift between templates and inline for %s\n' "$id" >&2
    diff -u "$LB_TMP" "$LC_TMP" >&2 || true
    FAIL=1
  else
    printf 'OK   %s (templates ↔ inline byte-identical)\n' "$id"
  fi
done

if [ "$FAIL" -ne 0 ]; then
  printf '\nDRIFT detected between v1.2 templates and inline literals.\n' >&2
  printf 'Either templates or inline diverged. Bring them back to byte-equivalence.\n' >&2
  exit 1
fi

printf '\nAll v1.2 templates byte-identical to inline literals in commands/review.md.\n'
exit 0
