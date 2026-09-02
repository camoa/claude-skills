#!/usr/bin/env bash
# accept-verdict-unit-spec.sh — unit spec for scripts/accept-verdict.sh, the 8 pure decisions
# extracted from the repair accept verdict block in build-critique-assert.sh.
#
# THIS SPEC SOURCES scripts/accept-verdict.sh AND NOTHING ELSE. It calls the 8 functions
# directly and asserts on their returned values; it invokes build-critique-assert.sh as a
# process zero times. The whole-block, first-hit-wins behaviour that block still owns is
# proven by tests/repair-accept-gate-spec.sh, which this file does not touch and does not
# duplicate.
#
# MESSAGES and EVIDENCE are left unset on purpose. build-critique-assert.sh mutates those two
# globals through add_msg/set_ev/set_ev_s; if any function under test read either one, `set -u`
# below would fail the run at that call rather than let a stale value pass silently.
set -u

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNIT="${PLUGIN_ROOT}/scripts/accept-verdict.sh"

if [ ! -f "$UNIT" ]; then
  printf 'FAIL: %s not found\n' "$UNIT" >&2
  exit 1
fi

# shellcheck source=../scripts/accept-verdict.sh
. "$UNIT"

FAIL=0
ASSERTIONS=0
fail_check() { ASSERTIONS=$((ASSERTIONS+1)); printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
pass_check() { ASSERTIONS=$((ASSERTIONS+1)); printf 'OK   %s\n' "$1"; }

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then pass_check "$1"; else fail_check "$1 — expected [$2] got [$3]"; fi
}

MALFORMED='not json at all'

# ═══════════════════════════════════════════════════════════════════════════
# 1. accept_bad_action_components
# ═══════════════════════════════════════════════════════════════════════════

CLEAN_ACTION='{"components":[{"component":"a","accept":{"action":"accepted"}}]}'
assert_eq "bad_action: a component with a clean accepted action trips nothing" \
  '[]' "$(accept_bad_action_components "$CLEAN_ACTION")"

TRIP_ACTION='{"components":[{"component":"a","accept":{"action":"maybe"}}]}'
assert_eq "bad_action: an off-enum action names the component" \
  '["a"]' "$(accept_bad_action_components "$TRIP_ACTION")"

assert_eq "bad_action: malformed JSON returns the sentinel" \
  "$JQ_ERR" "$(accept_bad_action_components "$MALFORMED")"

# ═══════════════════════════════════════════════════════════════════════════
# 2. accept_bad_suite_components
# ═══════════════════════════════════════════════════════════════════════════

CLEAN_SUITE='{"components":[{"component":"a","accept":{"suite":"green"}}]}'
assert_eq "bad_suite: a component with a clean green suite trips nothing" \
  '[]' "$(accept_bad_suite_components "$CLEAN_SUITE")"

TRIP_SUITE='{"components":[{"component":"a","accept":{"suite":"yellow"}}]}'
assert_eq "bad_suite: an off-enum suite names the component" \
  '["a"]' "$(accept_bad_suite_components "$TRIP_SUITE")"

assert_eq "bad_suite: malformed JSON returns the sentinel" \
  "$JQ_ERR" "$(accept_bad_suite_components "$MALFORMED")"

# ═══════════════════════════════════════════════════════════════════════════
# 3. accept_bad_basis_components
# ═══════════════════════════════════════════════════════════════════════════

CLEAN_BASIS='{"components":[{"component":"a","accept":{"decided_by":"motion","reason":"the suite was green"}}]}'
assert_eq "bad_basis: a readable decided_by and a non-blank reason trip nothing" \
  '[]' "$(accept_bad_basis_components "$CLEAN_BASIS")"

TRIP_BASIS_ENUM='{"components":[{"component":"a","accept":{"decided_by":"vibes","reason":"the suite was green"}}]}'
assert_eq "bad_basis: an off-enum decided_by names the component" \
  '["a"]' "$(accept_bad_basis_components "$TRIP_BASIS_ENUM")"

TRIP_BASIS_BLANK='{"components":[{"component":"a","accept":{"decided_by":"motion","reason":"   "}}]}'
assert_eq "bad_basis: a whitespace-only reason names the component" \
  '["a"]' "$(accept_bad_basis_components "$TRIP_BASIS_BLANK")"

assert_eq "bad_basis: malformed JSON returns the sentinel" \
  "$JQ_ERR" "$(accept_bad_basis_components "$MALFORMED")"

# ═══════════════════════════════════════════════════════════════════════════
# 4. accept_unreadable_repair_components
# ═══════════════════════════════════════════════════════════════════════════

assert_eq "unreadable_repair: malformed JSON returns the sentinel" \
  "$JQ_ERR" "$(accept_unreadable_repair_components "$MALFORMED")"

# --- c4: unreadable is a malformed checkpoint, not a malformed count -----------------------
# Written from the criterion before the function was touched. A sha or null both answer the
# question; anything else present says a repair state was written down and cannot be read.

CLEAN_CHECKPOINT='{"components":[{"component":"a","checkpoint_repaired":"deadbee"}]}'
assert_eq "unreadable_repair: a sha checkpoint trips nothing" \
  '[]' "$(accept_unreadable_repair_components "$CLEAN_CHECKPOINT")"

TRIP_CHECKPOINT='{"components":[{"component":"a","checkpoint_repaired":12}]}'
assert_eq "unreadable_repair: a non-string non-null checkpoint names the component" \
  '["a"]' "$(accept_unreadable_repair_components "$TRIP_CHECKPOINT")"

NULL_CHECKPOINT='{"components":[{"component":"a","checkpoint_repaired":null}]}'
assert_eq "unreadable_repair: a null checkpoint is readable and trips nothing" \
  '[]' "$(accept_unreadable_repair_components "$NULL_CHECKPOINT")"

# ═══════════════════════════════════════════════════════════════════════════
# 6. accept_missing_verdict_components
# ═══════════════════════════════════════════════════════════════════════════

CLEAN_MISSING='{"components":[{"component":"a","rounds":1}]}'
assert_eq "missing_verdict: a component that never entered the repair path trips nothing" \
  '[]' "$(accept_missing_verdict_components "$CLEAN_MISSING")"

assert_eq "missing_verdict: malformed JSON returns the sentinel" \
  "$JQ_ERR" "$(accept_missing_verdict_components "$MALFORMED")"

# --- c4: the repair signal is the repaired checkpoint, not the round count -----------------
# Written from the criterion before the function was touched. Under c4 a component gets at
# most one critic round, so `rounds` is 1 on every row and can no longer say who was repaired.
# `<component>.repaired` is captured only on the `[a]ddress` path, so a non-null
# `checkpoint_repaired` is the fact that the path ran. The four cells below fail against the
# round-count reading and pass against the checkpoint reading.

REPAIRED_ONE_ROUND='{"components":[{"component":"a","rounds":1,"checkpoint_repaired":"deadbee"}]}'
assert_eq "missing_verdict: a repaired component at rounds 1 with no verdict names the component" \
  '["a"]' "$(accept_missing_verdict_components "$REPAIRED_ONE_ROUND")"

NEVER_REPAIRED='{"components":[{"component":"a","rounds":1,"checkpoint_repaired":null}]}'
assert_eq "missing_verdict: a null repaired checkpoint is not a repair and trips nothing" \
  '[]' "$(accept_missing_verdict_components "$NEVER_REPAIRED")"

REPAIRED_WITH_VERDICT='{"components":[{"component":"a","rounds":1,"checkpoint_repaired":"deadbee","accept":{"action":"accepted"}}]}'
assert_eq "missing_verdict: a repaired component that recorded a verdict trips nothing" \
  '[]' "$(accept_missing_verdict_components "$REPAIRED_WITH_VERDICT")"

NO_CHECKPOINT_FIELD='{"components":[{"component":"a","rounds":1}]}'
assert_eq "missing_verdict: an absent checkpoint field is not a repair and trips nothing" \
  '[]' "$(accept_missing_verdict_components "$NO_CHECKPOINT_FIELD")"

# ═══════════════════════════════════════════════════════════════════════════
# 7. accept_unaccepted_components
# ═══════════════════════════════════════════════════════════════════════════

CLEAN_UNACC='{"components":[{"component":"a","accept":{"action":"accepted"}}]}'
assert_eq "unaccepted: an accepted verdict trips nothing" \
  '[]' "$(accept_unaccepted_components "$CLEAN_UNACC")"

TRIP_UNACC='{"components":[{"component":"a","accept":{"action":"not_accepted"}}]}'
assert_eq "unaccepted: a non-accepted verdict names the component" \
  '["a"]' "$(accept_unaccepted_components "$TRIP_UNACC")"

assert_eq "unaccepted: malformed JSON returns the sentinel" \
  "$JQ_ERR" "$(accept_unaccepted_components "$MALFORMED")"

# ═══════════════════════════════════════════════════════════════════════════
# 8. accept_escalation_reason
# ═══════════════════════════════════════════════════════════════════════════

CLEAN_ESC='{"escalation":{"reason":"operator accepted the red suite"}}'
assert_eq "escalation_reason: a top-level escalation reason is returned trimmed" \
  "operator accepted the red suite" "$(accept_escalation_reason "$CLEAN_ESC")"

NO_ESC='{"escalation":{"reason":""},"rounds":[]}'
assert_eq "escalation_reason: no escalation and no round resolution returns empty" \
  "" "$(accept_escalation_reason "$NO_ESC")"

FALLBACK_ESC='{"escalation":{"reason":""},"rounds":[{"resolution":"shipped on the round that settled it"}]}'
assert_eq "escalation_reason: falls back to the last non-blank round resolution" \
  "shipped on the round that settled it" "$(accept_escalation_reason "$FALLBACK_ESC")"

assert_eq "escalation_reason: malformed JSON returns the sentinel" \
  "$JQ_ERR" "$(accept_escalation_reason "$MALFORMED")"

# --- a spec that checked nothing has not passed ---
# Seven functions since v5.47.0, not eight: `accept_unreadable_round_components` was deleted
# with the `rounds[]` reading it disambiguated. 3 cases each for the 3 functions with one
# tripping condition (bad_action, bad_suite, unaccepted), 4 cases each for the 2 with two
# independent cases beyond clean/malformed (bad_basis: off-enum decided_by AND blank reason;
# escalation_reason: no decision recorded AND the round-resolution fallback), 4 for
# unreadable_repair and 6 for missing_verdict. Those last two both moved onto
# `checkpoint_repaired`: unreadable_repair takes clean, malformed, a non-string non-null
# value and an explicit null; missing_verdict adds an absent field and a repaired row that
# did record a verdict. Every round-count case was deleted with the reading.
# (3 x 3) + (4 x 2) + 4 + 6 = 27.
EXPECTED=27
[ "$ASSERTIONS" -eq "$EXPECTED" ] && pass_check "ran the expected $EXPECTED assertions" \
  || fail_check "expected $EXPECTED assertions, ran $ASSERTIONS (a skipped block reads as green)"

echo "----"; echo "accept-verdict-unit-spec: $((ASSERTIONS - FAIL)) passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
