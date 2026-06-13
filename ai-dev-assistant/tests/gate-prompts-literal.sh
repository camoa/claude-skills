#!/usr/bin/env bash
# gate-prompts-literal.sh — verify v4.0.2's gate-hardening-prompts.md v1.1
# preserved every literal-block byte from v1.0.
#
# v1.1 was a presentation-only compression: the per-template literal text
# (the bytes inside the ``` fences immediately under each "## Template ID:"
# heading) MUST be byte-identical to v1.0. Any drift is a regression of the
# rationalization-resistance contract.
#
# Strategy:
#   1. Recover v1.0 of gate-hardening-prompts.md from git history (the file's
#      own changelog points at the commit that introduced v1.1; we use the
#      parent of the v1.1 commit).
#   2. For each known template ID, extract the literal block from v1.0 and
#      from the current file.
#   3. diff the two blocks. Any non-empty diff = test fail.
#
# Usage:
#   tests/gate-prompts-literal.sh                # check, exit non-zero on drift
#   tests/gate-prompts-literal.sh --baseline-ref <git_ref>   # override baseline
#
# Default baseline ref: `main:references/gate-hardening-prompts.md`. If that
# is unavailable (e.g., shallow clone), pass an explicit ref.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${PLUGIN_ROOT}/references/gate-hardening-prompts.md"

BASELINE_REF="main:ai-dev-assistant/references/gate-hardening-prompts.md"
if [ "${1:-}" = "--baseline-ref" ] && [ -n "${2:-}" ]; then
  BASELINE_REF="$2"
fi

# Recover v1.0 baseline. cd to repo root (one above PLUGIN_ROOT) so git can
# resolve the path inside BASELINE_REF.
REPO_ROOT="$(cd "$PLUGIN_ROOT/.." && pwd)"
BASELINE_TMP=$(mktemp)
trap 'rm -f "$BASELINE_TMP" "$CURRENT_TMP" "$LB_TMP" "$LC_TMP"' EXIT

if ! ( cd "$REPO_ROOT" && git show "$BASELINE_REF" 2>/dev/null ) > "$BASELINE_TMP"; then
  printf 'FAIL: could not recover baseline %s\n' "$BASELINE_REF" >&2
  printf 'Hint: pass --baseline-ref <git_ref> with a ref that exists locally.\n' >&2
  exit 1
fi

CURRENT_TMP=$(mktemp)
cp "$TARGET" "$CURRENT_TMP"

# Extract the literal block (between ``` fences) under a given template ID heading.
# Args: file, template_id (e.g. "pre-analysis-decision")
extract_literal() {
  local file="$1" id="$2"
  awk -v id="$id" '
    BEGIN { state="seek"; }
    state == "seek" && $0 ~ "^## Template ID: `" id "`$" { state="hdr"; next }
    state == "hdr" && /^```$/ { state="in"; next }
    state == "in" && /^```$/ { exit }
    state == "in" { print }
  ' "$file"
}

TEMPLATE_IDS=(
  "pre-analysis-decision"
  "coverage-mapping-fail"
  "skill-review-decision"
  "plugin-validate-decision"
  "phase-command-bypass-acknowledge"
  "review-gate-fail"
  "review-summary"
)

LB_TMP=$(mktemp)
LC_TMP=$(mktemp)

FAIL=0
for id in "${TEMPLATE_IDS[@]}"; do
  extract_literal "$BASELINE_TMP" "$id" > "$LB_TMP"
  extract_literal "$CURRENT_TMP"  "$id" > "$LC_TMP"
  if [ ! -s "$LB_TMP" ]; then
    printf 'WARN: template %s not found in baseline (new template? OK if so)\n' "$id" >&2
    continue
  fi
  if [ ! -s "$LC_TMP" ]; then
    printf 'FAIL: template %s missing in current file\n' "$id" >&2
    FAIL=1
    continue
  fi
  if ! cmp -s "$LB_TMP" "$LC_TMP"; then
    printf 'FAIL: literal block drift in template %s\n' "$id" >&2
    diff -u "$LB_TMP" "$LC_TMP" >&2 || true
    FAIL=1
  else
    printf 'OK   %s (literal block byte-identical)\n' "$id"
  fi
done

if [ "$FAIL" -ne 0 ]; then
  printf '\nLITERAL DRIFT detected. v4.0.0 rationalization-resistance contract broken.\n' >&2
  exit 1
fi

printf '\nAll template literals byte-identical to baseline %s.\n' "$BASELINE_REF"
exit 0
