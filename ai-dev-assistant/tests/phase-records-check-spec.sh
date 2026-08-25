#!/usr/bin/env bash
# phase-records-check-spec.sh — the phase that was performed by hand.
#
# The bypass this guards is invisible in the terminal. A session reads the protocol, does the work
# itself, and produces a good answer; what goes missing is everything the skipped skill would have
# WRITTEN. Measured on one real task: three skills bypassed in a single phase, and manual inspection
# found only one of them.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="${PLUGIN_ROOT}/scripts/phase-records-check.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
[ -x "$K" ] || { printf 'FAIL: %s not executable\n' "$K" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
REQUIRED="_pre-analysis.json coverage-map.json _agentic-recipe.json _mechanism-challenge.json _dev-guides-load.json _playbook-load.json _internal-prior-art.json research.md"

mk() { local d="$T/$1"; mkdir -p "$d"; shift; for f in "$@"; do printf '{}' > "$d/$f"; done; printf '%s' "$d"; }

# --- every required record present ---------------------------------------------
# shellcheck disable=SC2086
FULL=$(mk full $REQUIRED)
OUT=$(bash "$K" "$FULL" --phase research)
[ "$(printf '%s' "$OUT" | jq -r .verdict)" = "complete" ] \
  && pass_check "a phase with every record reports complete" \
  || fail_check "a complete phase must report complete"

# --- the real case: three skills bypassed --------------------------------------
BYPASSED=$(mk bypassed _pre-analysis.json _agentic-recipe.json _dev-guides-load.json _playbook-load.json research.md)
OUT=$(bash "$K" "$BYPASSED" --phase research)
[ "$(printf '%s' "$OUT" | jq -r .verdict)" = "incomplete" ] \
  && pass_check "a hand-rolled phase is caught" \
  || fail_check "missing required records must report incomplete"
[ "$(printf '%s' "$OUT" | jq -r .missing_required)" = "3" ] \
  && pass_check "every bypassed component is counted, not just the first" \
  || fail_check "expected 3 missing, got $(printf '%s' "$OUT" | jq -r .missing_required)"

# The point of the check is not that something is missing — it is WHO did not run.
# "missing _internal-prior-art.json" is a puzzle; naming the skill is an instruction.
PRODUCER=$(printf '%s' "$OUT" | jq -r '.records[]|select(.name=="_internal-prior-art.json")|.producer')
printf '%s' "$PRODUCER" | grep -q 'internal-prior-art-finder' \
  && pass_check "a missing record names the skill that owed it" \
  || fail_check "each missing record must name its producer"
printf '%s' "$OUT" | jq -e '.records[]|select(.name=="coverage-map.json")|select(.step=="step 2c")' >/dev/null \
  && pass_check "a missing record names the step it belongs to" \
  || fail_check "each record must name its protocol step"

# --- an empty file is not a record ---------------------------------------------
# It parses as absent everywhere downstream, so counting it present hides the problem one layer on.
# shellcheck disable=SC2086
EMPTY=$(mk empty $REQUIRED)
: > "$EMPTY/_internal-prior-art.json"
OUT=$(bash "$K" "$EMPTY" --phase research)
[ "$(printf '%s' "$OUT" | jq -r '.records[]|select(.name=="_internal-prior-art.json")|.status')" = "empty" ] \
  && pass_check "an empty file is reported empty, not present" \
  || fail_check "an empty record must not count as present"
[ "$(printf '%s' "$OUT" | jq -r .verdict)" = "incomplete" ] \
  && pass_check "an empty required record still fails the phase" \
  || fail_check "an empty required record must not pass"

# --- conditional records never block -------------------------------------------
# A maintainer offer that did not fire is not a missing record.
# shellcheck disable=SC2086
OUT=$(bash "$K" "$(mk cond $REQUIRED)" --phase research)
[ "$(printf '%s' "$OUT" | jq -r .verdict)" = "complete" ] \
  && pass_check "absent conditional records do not block" \
  || fail_check "conditional records must never fail the phase"
[ "$(printf '%s' "$OUT" | jq -r '[.records[]|select(.requirement=="conditional")]|length')" -gt 0 ] \
  && pass_check "conditional records are still reported for visibility" \
  || fail_check "conditional records must be listed"

# --- an unknown phase is UNKNOWN, never complete -------------------------------
# A phase this script has no contract for has not been checked. Saying complete would make the
# check the same kind of confident wrong answer it exists to catch.
# shellcheck disable=SC2086
[ "$(bash "$K" "$(mk other $REQUIRED)" --phase design | jq -r .verdict)" = "unknown" ] \
  && pass_check "a phase with no encoded contract reports unknown" \
  || fail_check "an unchecked phase must never report complete"

# --- defensive posture ----------------------------------------------------------
bash "$K" "$T/nope" --phase research | jq empty >/dev/null 2>&1 \
  && pass_check "a missing task folder still emits valid JSON" \
  || fail_check "must always emit valid JSON"
[ "$(bash "$K" "$T/nope" --phase research | jq -r .verdict)" = "unknown" ] \
  && pass_check "a missing task folder is unknown, not complete" \
  || fail_check "a missing folder must not report complete"

if [ "$FAIL" -ne 0 ]; then
  printf '\nSome invariants FAILED for scripts/phase-records-check.sh.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for scripts/phase-records-check.sh.\n'
exit 0
