#!/usr/bin/env bash
# gate-audit-payload-size-spec.sh — the guard a record could outgrow.
#
# gate-audit-write.sh took its payload only as a command-line argument. Linux caps a single
# argument at MAX_ARG_STRLEN, 128 KB, in the kernel; past it execve fails and bash never starts.
# Not a check inside the script failing — the script never runs at all, so nothing it does
# afterwards happens either.
#
# Which matters because of what the script does afterwards. v5.35.3 added a refusal: a rewrite
# that drops a top-level key the existing record has is rejected, because the build-critique
# record accumulates facts across rounds and a partial rewrite silently deletes them. Observed
# live: a nine-component build with six critique rounds produced a 136 KB `_build-critique.json`,
# every attempt to update it died with "argument list too long", and the record was updated by
# hand instead — the exact rewrite the guard exists to police, performed with the guard
# unreachable. A size limit in front of a guard is a way around the guard.
#
# So these assertions pin the property, not the mechanism: a record of any size reaches every
# check in the script. `@<path>` is how, but what is asserted is that size stops mattering.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
[ -f "$W" ] || { printf 'FAIL: %s missing\n' "$W" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
TD="$T/task"; mkdir -p "$TD"

# A payload comfortably past MAX_ARG_STRLEN (131072). Built with jq so the size comes from real
# repeated structure rather than one long string — a record grows by accumulating components and
# rounds, which is the shape that got past the limit live.
BIG="$T/big.json"
jq -nc '{
  phase: "implement",
  verdict: "pass",
  components_declared: 400,
  components_critiqued: 400,
  uncritiqued: [],
  components: [range(400) | {name: "component-\(.)", runtime: "executed",
                             notes: ("x" * 400)}],
  alignment: {criteria_unverifiable: []},
  tdd: {red_observed: true},
  contract: {changed: []},
  closing_fixes: {applied: 0}
}' > "$BIG"
BIG_BYTES=$(wc -c < "$BIG")

[ "$BIG_BYTES" -gt 131072 ] \
  && pass_check "the fixture is past MAX_ARG_STRLEN ($BIG_BYTES bytes)" \
  || fail_check "fixture is only $BIG_BYTES bytes; it must exceed 131072 to test anything"

# --- the argv form genuinely cannot carry it ------------------------------------
# Establishes that the problem is real rather than assumed. A subshell, because the failure is
# an exec failure in the caller and would otherwise take this script down with it.
ARGV_RC=0
( PAY=$(cat "$BIG"); bash "$W" "$TD" build-critique "$PAY" ) >/dev/null 2>&1 || ARGV_RC=$?
[ "$ARGV_RC" != "0" ] \
  && pass_check "a payload this size cannot be passed as an argument (rc=$ARGV_RC)" \
  || fail_check "the argv form unexpectedly accepted $BIG_BYTES bytes; this spec is testing nothing"

[ -f "$TD/_build-critique.json" ] \
  && fail_check "the failed argv write left a record behind" \
  || pass_check "the failed argv write left no record"

# --- the file form carries it ----------------------------------------------------
RC=0
bash "$W" "$TD" build-critique "@$BIG" >/dev/null 2>&1 || RC=$?
[ "$RC" = "0" ] \
  && pass_check "the same payload writes successfully from a file" \
  || fail_check "@<path> must accept a payload of any size, got rc=$RC"

[ -f "$TD/_build-critique.json" ] \
  && pass_check "the record was written" \
  || fail_check "no _build-critique.json after a successful write"

jq -e '.gate_specific.components | length == 400' "$TD/_build-critique.json" >/dev/null 2>&1 \
  && pass_check "the whole payload arrived, not a truncated prefix" \
  || fail_check "the written record does not carry all 400 components"

# --- the envelope is built the same way for both forms ---------------------------
# @<path> is an input channel, not a second contract. Everything the script stamps must be
# stamped identically or a record's provenance would depend on how it happened to be passed.
for k in schema_version gate_type task_folder fired_at plugin_version; do
  jq -e --arg k "$k" 'has($k) and (.[$k] != null)' "$TD/_build-critique.json" >/dev/null 2>&1 \
    && pass_check "a file-passed payload is still stamped with $k" \
    || fail_check "$k missing from a record written via @<path>"
done

jq -e '.gate_type == "build-critique"' "$TD/_build-critique.json" >/dev/null 2>&1 \
  && pass_check "the bare payload was wrapped in the envelope, not written flat" \
  || fail_check "@<path> must go through the same normalisation as an argv payload"

# --- the key-loss guard is reachable at this size --------------------------------
# The assertion this file exists for. Above the argv ceiling the guard was not merely untested,
# it was unreachable, and the operator's only remaining option — a hand edit — is the thing it
# refuses.
SHRUNK="$T/shrunk.json"
jq 'del(.components)' "$BIG" > "$SHRUNK"
GUARD_RC=0
GUARD_OUT=$(bash "$W" "$TD" build-critique "@$SHRUNK" 2>&1) || GUARD_RC=$?
[ "$GUARD_RC" = "2" ] \
  && pass_check "a rewrite that drops a key is still refused at $BIG_BYTES bytes" \
  || fail_check "the key-loss guard did not fire on a large record (rc=$GUARD_RC)"

printf '%s' "$GUARD_OUT" | grep -q 'components' \
  && pass_check "the refusal names the key that would have been lost" \
  || fail_check "the refusal must name the dropped key"

jq -e '.gate_specific.components | length == 400' "$TD/_build-critique.json" >/dev/null 2>&1 \
  && pass_check "the refused write left the existing record intact" \
  || fail_check "a refused write must not modify the record"

# --- an intended removal still works at this size --------------------------------
RC=0
bash "$W" "$TD" build-critique "@$SHRUNK" --allow-key-loss >/dev/null 2>&1 || RC=$?
[ "$RC" = "0" ] \
  && pass_check "--allow-key-loss still overrides the refusal on a large record" \
  || fail_check "the documented override must work at any size, got rc=$RC"

# --- a bad @<path> is an input error, not a silent empty write -------------------
# The failure mode worth naming: `@/typo.json` read as a literal payload would fail JSON
# parsing and exit 2 anyway, but a caller must be told which thing was wrong.
RC=0
OUT=$(bash "$W" "$TD" build-critique "@$T/does-not-exist.json" 2>&1) || RC=$?
[ "$RC" = "2" ] \
  && pass_check "a missing payload file exits 2" \
  || fail_check "a missing payload file must exit 2, got $RC"
printf '%s' "$OUT" | grep -qi 'not found' \
  && pass_check "the error says the payload file was not found" \
  || fail_check "a missing payload file must say so, got: $OUT"

# --- the argv form still works for a small payload -------------------------------
# @<path> is additive. Twenty-eight documented call sites pass a payload inline and none of them
# changed.
TD2="$T/task2"; mkdir -p "$TD2"
RC=0
bash "$W" "$TD2" playbook-load '{"phase":"implement","plays_loaded":0}' >/dev/null 2>&1 || RC=$?
[ "$RC" = "0" ] && [ -f "$TD2/_playbook-load.json" ] \
  && pass_check "an inline payload still writes exactly as before" \
  || fail_check "the argv form regressed (rc=$RC)"

# --- the documented callers of the unbounded records use the file form -----------
# build-critique and review are the two records with no upper bound on their size: one grows per
# component per round, the other aggregates every gate. A documented call that passes either
# inline is a call that works until the task is big enough, which is the worst time to find out.
for pair in "implement.md:build-critique" "review.md:review"; do
  CMD="${pair%%:*}"; GATE="${pair##*:}"
  F="$PLUGIN_ROOT/commands/$CMD"
  if grep -q "gate-audit-write.sh.*$GATE.*@" "$F" || grep -q "@.*payload" "$F"; then
    pass_check "commands/$CMD passes the $GATE payload from a file"
  else
    fail_check "commands/$CMD must pass the unbounded $GATE payload via @<path>"
  fi
done

if [ "$FAIL" = "0" ]; then
  printf '\nAll invariants pass for gate-audit payload size.\n'
else
  printf '\ngate-audit-payload-size-spec: FAILURES\n' >&2
  exit 1
fi
