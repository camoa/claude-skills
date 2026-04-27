#!/usr/bin/env bash
# review-command-spec.sh — verify commands/review.md invariants (v4.1.0+).
#
# Checks the 5-mechanism markers + body line budget + frontmatter required fields.
# Run pre-PR-merge or via /plugin-creation-tools:validate alongside.
#
# Exit 0 on all-pass; 1 on any fail.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${PLUGIN_ROOT}/commands/review.md"

if [ ! -f "$TARGET" ]; then
  printf 'FAIL: %s not found\n' "$TARGET" >&2
  exit 1
fi

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

# 1. Frontmatter required fields
for field in description allowed-tools argument-hint; do
  if grep -q "^${field}:" "$TARGET"; then
    pass_check "frontmatter has $field"
  else
    fail_check "frontmatter missing $field"
  fi
done

# 2. Body line count ≤120
BODY_LINES=$(awk 'BEGIN{f=0;d=0;n=0} /^---$/&&!d{f++;if(f==2)d=1;next} f==1&&!d{next} {n++} END{print n}' "$TARGET")
if [ "$BODY_LINES" -le 120 ]; then
  pass_check "body line count $BODY_LINES ≤ 120"
else
  fail_check "body line count $BODY_LINES > 120"
fi

# 3. 5-mechanism markers
declare -A MARKERS=(
  [anti-bypass-clause]="^## Anti-bypass clause"
  [mandated-wording-ref]="Mandated wording"
  [gate-audit-write-call]="gate-audit-write.sh"
  [show-not-summarize]="verbatim"
  [always-evaluated-framing]="all gates fire|always evaluated|always-evaluated|once invoked"
)
for name in "${!MARKERS[@]}"; do
  if grep -qE "${MARKERS[$name]}" "$TARGET"; then
    pass_check "5-mechanism marker: $name"
  else
    fail_check "5-mechanism marker missing: $name"
  fi
done

# 4. Required flags documented
for flag in --team --dry-run --rerun-failed --no-pr-body --skip-; do
  if grep -qF -- "$flag" "$TARGET"; then
    pass_check "flag documented: $flag"
  else
    fail_check "flag missing: $flag"
  fi
done

if [ "$FAIL" -ne 0 ]; then
  printf '\ncommands/review.md invariants violated.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for commands/review.md.\n'
exit 0
