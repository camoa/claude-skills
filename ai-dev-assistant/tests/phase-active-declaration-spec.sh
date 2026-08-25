#!/usr/bin/env bash
# phase-active-declaration-spec.sh — the guardrail that fired on every correct run.
#
# phase-command-bypass-detect.sh read `lastPhase` from the session file. Nothing in the plugin ever
# wrote it: session-context-write.sh preserves it and says another component owns it, and no such
# component existed. So it was always null, null never equalled the expected phase, and a bypass was
# recorded every time a phase artifact was written — including by the phase command doing its job.
# Seen live on a research run that passed all its gates and still left an unexplained bypass record.
#
# A guardrail that fires 100% of the time carries no information. These assertions pin the three
# states apart: declared-and-matching writes nothing, a different phase is a real bypass, and
# nothing-declared is `undetermined` rather than an accusation.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="${PLUGIN_ROOT}/scripts/phase-active-write.sh"
D="${PLUGIN_ROOT}/scripts/phase-command-bypass-detect.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
for f in "$W" "$D"; do [ -x "$f" ] || { printf 'FAIL: %s not executable\n' "$f" >&2; exit 1; }; done

T=$(mktemp -d); trap 'bash "$W" none >/dev/null 2>&1 || true; rm -rf "$T"' EXIT
det() { bash "$D" "$T" "$1" 2>/dev/null; }

# --- the writer exists and round-trips ------------------------------------------
[ "$(bash "$W" research | jq -r .lastPhase)" = "research" ] \
  && pass_check "a phase command can declare itself active" \
  || fail_check "phase-active-write.sh must record the phase"

# --- declared and matching: no record at all ------------------------------------
[ "$(det research.md)" = "{}" ] \
  && pass_check "the declaring phase command writes no bypass record" \
  || fail_check "a matching phase must produce no record, got: $(det research.md)"

# --- a genuinely different phase is a real bypass, and names itself --------------
bash "$W" implement >/dev/null
OUT=$(det research.md)
[ "$(printf '%s' "$OUT" | jq -r '.gate_specific.verdict')" = "bypass" ] \
  && pass_check "writing research.md under /implement is a real bypass" \
  || fail_check "a mismatched phase must be reported as a bypass"
[ "$(printf '%s' "$OUT" | jq -r '.gate_specific.phase_command_active')" = "implement" ] \
  && pass_check "the bypass record names the phase that was actually active" \
  || fail_check "a bypass must record which phase was active"

# --- nothing declared: undetermined, NOT a bypass -------------------------------
# This is the state that produced a false positive on every task in the plugin's history.
bash "$W" none >/dev/null
OUT=$(det research.md)
[ "$(printf '%s' "$OUT" | jq -r '.gate_specific.verdict')" = "undetermined" ] \
  && pass_check "nothing declared reports undetermined, not a bypass" \
  || fail_check "an undeclared phase must not be reported as a bypass"
[ "$(printf '%s' "$OUT" | jq -r '.gate_specific.reason')" != "null" ] \
  && pass_check "the undetermined record says why it could not tell" \
  || fail_check "undetermined must carry its reason"

# --- both records use the audit envelope, not a shape of their own ---------------
# A reader keying on gate_specific must find both; a flat record would parse as empty.
for phase in implement none; do
  bash "$W" "$phase" >/dev/null
  printf '%s' "$(det research.md)" | jq -e '.schema_version and .gate_type and .gate_specific' >/dev/null \
    && pass_check "the record written when phase=$phase uses the gate-audit envelope" \
    || fail_check "the phase=$phase record must carry schema_version, gate_type and gate_specific"
done

# --- the three phase commands declare themselves --------------------------------
for c in research design implement; do
  grep -q 'phase-active-write.sh' "$PLUGIN_ROOT/commands/$c.md" \
    && pass_check "/$c declares its phase on entry" \
    || fail_check "commands/$c.md must call phase-active-write.sh before writing anything"
done

# --- a malformed phase is refused, never recorded as fact ------------------------
[ "$(bash "$W" nonsense | jq -r .ok)" = "false" ] \
  && pass_check "an unrecognised phase is refused" \
  || fail_check "an unrecognised phase must not be written"

if [ "$FAIL" -ne 0 ]; then
  printf '\nSome invariants FAILED for the phase-active declaration.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for the phase-active declaration.\n'
exit 0
