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

# ── GAP-C: vacuous-skip observability (a declared playbook set that resolves to 0 plays must NOT read
#    as coverage; the loader signals it + the gate records WHY it skipped) ──

# 7. The gate distinguishes a vacuous skip (declared but 0 plays) from a genuine no-op (nothing declared).
if grep -qF -- 'declared_playbook_resolved_zero_plays' "$TARGET" && grep -qF -- 'no_playbook_declared' "$TARGET"; then
  pass_check "gate records vacuous skip distinctly from no-op (declared_playbook_resolved_zero_plays vs no_playbook_declared)"
else
  fail_check "gate does NOT distinguish a vacuous skip from a no-op (a 0-play skip would read as coverage)"
fi
if grep -qiF -- 'is NOT coverage' "$TARGET"; then
  pass_check "gate surfaces a 'this skip is NOT coverage' warning on the vacuous case"
else
  fail_check "gate vacuous skip has no 'not coverage' warning (silent vacuous pass)"
fi

# 8. The deterministic loader emits the heads-up behaviorally: a declared set + no user playbook →
#    playbook_sets_declared_zero_local_plays; an explicit 'none' opt-out → NO warning.
LOADER="${PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh"
_tmp="$(mktemp -d)"
printf '# t\n\n**Code path:** /tmp\n**Playbook Sets:** drupal/best-practices/camoa\n**User Playbook:** (docs-only-no-playbook)\n' > "$_tmp/project_state.md"
if bash "$LOADER" "$_tmp" | jq -e '[.warnings[].code] | index("playbook_sets_declared_zero_local_plays") != null' >/dev/null 2>&1; then
  pass_check "loader warns playbook_sets_declared_zero_local_plays on a declared set with 0 local plays"
else
  fail_check "loader did NOT warn on a declared set that loaded 0 concrete plays (silent vacuous load)"
fi
printf '# t\n\n**Code path:** /tmp\n**Playbook Sets:** none\n' > "$_tmp/project_state.md"
if bash "$LOADER" "$_tmp" | jq -e '[.warnings[].code] | index("playbook_sets_declared_zero_local_plays") == null' >/dev/null 2>&1; then
  pass_check "loader does NOT warn on an intentional 'none' opt-out (no false alarm)"
else
  fail_check "loader false-alarms on an intentional 'none' opt-out"
fi
rm -rf "$_tmp"

if [ "$FAIL" -ne 0 ]; then
  printf '\ncommands/validate-playbook-adherence.md invariants violated.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for commands/validate-playbook-adherence.md.\n'
exit 0
