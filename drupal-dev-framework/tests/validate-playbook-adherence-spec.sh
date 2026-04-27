#!/usr/bin/env bash
# validate-playbook-adherence-spec.sh — verify commands/validate-playbook-adherence.md invariants (v4.1.0+).

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${PLUGIN_ROOT}/commands/validate-playbook-adherence.md"

if [ ! -f "$TARGET" ]; then
  printf 'FAIL: %s not found\n' "$TARGET" >&2
  exit 1
fi

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

# 1. Frontmatter required
for field in description allowed-tools argument-hint; do
  grep -q "^${field}:" "$TARGET" && pass_check "frontmatter has $field" || fail_check "frontmatter missing $field"
done

# 2. Body ≤100 lines
BODY=$(awk 'BEGIN{f=0;d=0;n=0} /^---$/&&!d{f++;if(f==2)d=1;next} f==1&&!d{next} {n++} END{print n}' "$TARGET")
[ "$BODY" -le 100 ] && pass_check "body $BODY ≤ 100" || fail_check "body $BODY > 100"

# 3. Literal-string match (Grep -F) noted
grep -qE "Grep \\\`-F\\\`|Grep -F|literal-string match" "$TARGET" \
  && pass_check "literal-string Grep -F documented" \
  || fail_check "literal-string Grep -F not documented"

# 4. Section-aware skip headings
for kw in Rejected "Considered Alternatives" "Out of Scope"; do
  if grep -qF -- "$kw" "$TARGET"; then
    pass_check "section-skip header documented: $kw"
  else
    fail_check "section-skip header missing: $kw"
  fi
done

# 5. Required flags
for flag in --hard-block --strict --invoked-by; do
  grep -qF -- "$flag" "$TARGET" && pass_check "flag: $flag" || fail_check "flag missing: $flag"
done

# 6. Verdict logic enumerated (pass/warning/fail/skipped)
for verdict in pass warning fail skipped; do
  grep -qE "verdict.*${verdict}|\"${verdict}\"" "$TARGET" \
    && pass_check "verdict documented: $verdict" \
    || fail_check "verdict missing: $verdict"
done

if [ "$FAIL" -ne 0 ]; then
  printf '\ncommands/validate-playbook-adherence.md invariants violated.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for commands/validate-playbook-adherence.md.\n'
exit 0
