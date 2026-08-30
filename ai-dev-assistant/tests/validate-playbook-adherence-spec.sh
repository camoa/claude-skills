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
# (v5.35.7 split the single no-op reason into three; the no-op side is satisfied by any of them,
#  and check 9 below separately requires all three to be present.)
if grep -qF -- 'declared_playbook_resolved_zero_plays' "$TARGET" \
   && grep -qE 'no_playbook_declared|playbook_opt_out|playbook_never_configured' "$TARGET"; then
  pass_check "gate records vacuous skip distinctly from a no-op (declared_playbook_resolved_zero_plays vs the no-op reasons)"
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

# ── v5.35.7: an unconfigured playbook set reported as a clean skip, and "default" named an
#    empty list. Both are the same defect as GAP-C above one rung out: a result nobody measured
#    presented as a measured one. ──

STATE_READ="${PLUGIN_ROOT}/scripts/project-state-read.sh"
DEFAULTS="${PLUGIN_ROOT}/defaults.json"
_tmp="$(mktemp -d)"

# 9. The gate resolves an empty playbook into THREE reasons and no longer collapses them into one.
#    Keyed on all three literals together: the old single-reason text alone must not satisfy this.
_missing=""
for reason in playbook_opt_out playbook_never_configured playbook_config_unknown; do
  grep -qF -- "$reason" "$TARGET" || _missing="$_missing $reason"
done
if [ -z "$_missing" ]; then
  pass_check "gate resolves an empty playbook into three distinct reasons (opt-out / never-configured / unknown)"
else
  fail_check "gate is missing empty-playbook reason(s):$_missing (an unconfigured project would read as a clean skip)"
fi

# 10. The never-configured case is SURFACED (carries the not-coverage warning) and the deliberate
#     opt-out is explicitly SILENT. A fix that warns on both is as wrong as one that warns on neither.
if grep -qF -- 'playbook_never_configured' "$TARGET" \
   && grep -qE 'playbook_never_configured.*(this skip is NOT coverage|NOT coverage)' "$TARGET"; then
  pass_check "never-configured playbook is surfaced as not-coverage, not a clean skip"
else
  fail_check "never-configured playbook carries no 'NOT coverage' warning (it would read as coverage)"
fi
if grep -qE 'playbook_opt_out.*(no warning message|stay quiet)' "$TARGET"; then
  pass_check "a recorded opt-out stays quiet (no false nag at a project that chose none)"
else
  fail_check "gate does not state that a recorded opt-out stays quiet"
fi

# 11. The resolved reason is carried in the record, not only printed.
if grep -qF -- 'skip_reason' "$TARGET"; then
  pass_check "resolved skip reason is carried in the gate details (skip_reason)"
else
  fail_check "skip reason is not carried in the record (a reader of the JSON cannot tell which state applied)"
fi

# 12. BEHAVIORAL: with the shipped defaults.json (empty list), an absent **Playbook Sets:** line
#     resolves to default-empty — "nothing chosen and nothing to fall back to" — never "default".
printf '# t\n\n**Code path:** /tmp\n' > "$_tmp/project_state.md"
_src="$(bash "$STATE_READ" "$_tmp" | jq -r '.playbookSetsSource')"
_deflen="$(jq '.playbookSets | length' "$DEFAULTS" 2>/dev/null || echo 0)"
if [ "$_deflen" -eq 0 ] && [ "$_src" = "default-empty" ]; then
  pass_check "absent Playbook Sets line + empty defaults.json → default-empty (not 'default', which claims a set was applied)"
else
  fail_check "absent Playbook Sets line resolved to '$_src' with a ${_deflen}-entry defaults.json (expected default-empty)"
fi

# 13. BEHAVIORAL: "default" stays a REACHABLE, valid value meaning a non-empty default WAS applied.
#     This is the half that stops the new state being a rename out from under an existing reader.
_defbak="$(mktemp)"; cp "$DEFAULTS" "$_defbak"
printf '{"playbookSets":["spec/best-practices/fixture"]}\n' > "$DEFAULTS"
_src2="$(bash "$STATE_READ" "$_tmp" | jq -r '.playbookSetsSource')"
_sets2="$(bash "$STATE_READ" "$_tmp" | jq -c '.playbookSets')"
cp "$_defbak" "$DEFAULTS"; rm -f "$_defbak"
if [ "$_src2" = "default" ] && [ "$_sets2" = '["spec/best-practices/fixture"]' ]; then
  pass_check "a non-empty defaults.json still yields source 'default' with the set applied (existing value stays valid)"
else
  fail_check "non-empty defaults.json yielded source '$_src2' sets $_sets2 (expected 'default' — the old value must stay reachable)"
fi

# 14. DERIVED, not copied: every place that equality-tests this field against "default" must also
#     accept "default-empty" RIGHT THERE, or it silently stops firing in the exact case it was
#     written for. Scans the shipped tree from git ls-files rather than a maintained list, so a new
#     reader is caught too. The alternative must appear within 80 characters of the matched test:
#     a first draft only required it somewhere on the same line, which a realistic revert satisfied
#     with the prose further along the sentence — the check passed while the reader was broken.
#     Scope note: CHANGELOG.md records what was believed then, and tests/ state the value as fixture
#     data rather than branching on it, so neither is a reader — both excluded.
# Operator-agnostic on purpose: an earlier draft required `==` or `:` between the field and the
# literal, and the gate command's own reader — phrased "`playbook_sets_source` is `\"default\"`" —
# was never scanned at all. `[^"]{0,40}` keeps the match from crossing into an adjacent string.
_pat='(playbook_sets_source|playbookSetsSource)[^"]{0,40}"default"'
_scan_files="$(cd "$PLUGIN_ROOT" && git ls-files 'commands/*' 'references/*' 'skills/*' 'agents/*' 'scripts/*' 'hooks/*' '*.md' | grep -v '^CHANGELOG.md$' || true)"
if [ -z "$_scan_files" ]; then
  fail_check "reader scan matched no files — the check could not look, which is not the same as passing"
else
  _hits="$(cd "$PLUGIN_ROOT" && printf '%s\n' "$_scan_files" | tr '\n' '\0' \
    | xargs -0 grep -nE "$_pat" 2>/dev/null | grep -v '^$' || true)"
  if [ -z "$_hits" ]; then
    fail_check "reader scan found no equality test against playbook_sets_source at all — the check had nothing to compare (it cannot pass by finding nothing)"
  else
    _offenders=""
    while IFS= read -r _hit; do
      [ -n "$_hit" ] || continue
      printf '%s' "$_hit" | grep -qE "${_pat}.{0,80}default-empty" || _offenders="$_offenders ${_hit%%:*}"
    done <<SPEC_EOF
$_hits
SPEC_EOF
    _offenders="$(printf '%s' "$_offenders" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
    if [ -z "$_offenders" ]; then
      pass_check "every equality test against playbook_sets_source \"default\" accepts \"default-empty\" alongside it ($(printf '%s\n' "$_hits" | wc -l | tr -d ' ') reader(s) checked)"
    else
      fail_check "reader(s) match only \"default\" and would stop firing on the real value \"default-empty\": $_offenders"
    fi
  fi
fi

# 15. BEHAVIORAL: the loader carries user_playbook_state, so the record can tell a recorded
#     docs-only opt-out from a user playbook nobody ever set. Without it the two are one state.
printf '# t\n\n**Code path:** /tmp\n**Playbook Sets:** none\n**User Playbook:** (docs-only-no-playbook)\n' > "$_tmp/project_state.md"
_ups_out="$(bash "$LOADER" "$_tmp" | jq -r '.user_playbook_state')"
printf '# t\n\n**Code path:** /tmp\n**Playbook Sets:** none\n' > "$_tmp/project_state.md"
_ups_unset="$(bash "$LOADER" "$_tmp" | jq -r '.user_playbook_state')"
if [ "$_ups_out" = "docs-only-no-playbook" ] && [ "$_ups_unset" = "unset" ]; then
  pass_check "loader distinguishes a recorded user-playbook opt-out from one never set ($_ups_out vs $_ups_unset)"
else
  fail_check "loader user_playbook_state did not distinguish opt-out from never-set (got '$_ups_out' and '$_ups_unset')"
fi

# 16. BEHAVIORAL: when the loader cannot read project_state.md it must not name a configuration
#     state it never observed. Stub the reader to return nothing and check both fields say unknown.
_stub="$(mktemp -d)"
cp "$LOADER" "$_stub/playbook-load-deterministic.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$_stub/project-state-read.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$_stub/playbook-read.sh"
chmod +x "$_stub"/*.sh
_blind="$(bash "$_stub/playbook-load-deterministic.sh" "$_tmp" | jq -r '.playbook_sets_source + "/" + .user_playbook_state')"
rm -rf "$_stub"
if [ "$_blind" = "unknown/unknown" ]; then
  pass_check "loader reports unknown/unknown when it could not read project_state.md (never a configured-looking state)"
else
  fail_check "loader reported '$_blind' after reading nothing (expected unknown/unknown)"
fi

rm -rf "$_tmp"

if [ "$FAIL" -ne 0 ]; then
  printf '\ncommands/validate-playbook-adherence.md invariants violated.\n' >&2
  exit 1
fi

printf '\nAll invariants pass for commands/validate-playbook-adherence.md.\n'
exit 0
