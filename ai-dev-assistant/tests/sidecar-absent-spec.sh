#!/usr/bin/env bash
# An absent agent sidecar must reach every consumer as no_return, and must never be the value a
# silent default would produce.
#
# WHAT THIS CAN AND CANNOT DO, stated first because the gap matters.
#
# The consumers are command PROSE that an orchestrator follows, not code this spec can execute. So
# this cannot delete a file and observe a verdict. What it checks is that each consumer's
# instruction names the absent case and names a consequence that is not the passing one, and that
# the consequences DIFFER between consumers, because a single shared consequence would be evidence
# somebody flattened a distinction the framework keeps on purpose.
#
# One half IS executable and is checked by running it: the normalizer that guards the analysis-agent
# path returns a distinct code for an empty input rather than exit 0 and silence.
#
# THE DEFECT. Three consumers folded an absent or empty agent result into a passing one. An empty
# surface selection became `verdict: skipped` and stopped. Empty guide matches became zero coverage
# gaps and a clean pass. An absent tier-3 prior-art result resolved as "no native pattern found" and
# a build proceeded on an unchallenged mechanism. In each case an agent that errored and an agent
# that honestly found nothing produced the identical green.
#
# Exit: 0 = every consumer names the absent case with a non-passing consequence; 1 = a gap.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."
fail=0
checked=0

want() { # want <file> <regex> <what it proves>
  local f="$ROOT/$1"
  if [ ! -f "$f" ]; then
    echo "FAIL: consumer not found: $1"
    fail=1
    return
  fi
  checked=$((checked + 1))
  if grep -Eq -- "$2" "$f"; then
    echo "PASS: $1 — $3"
  else
    echo "FAIL: $1 does not $3"
    echo "      (looked for: $2)"
    fail=1
  fi
}

# --- every consumer names the absent case by the shared value ---
want commands/validate-visual-regression.md 'no_return' 'name the absent selection'
want commands/validate-guides.md            'no_return' 'name the absent match set'
want commands/research.md                   'no_return' 'name an absent agent result'
want commands/design.md                     'no_return' 'name an absent agent result'
want commands/implement.md                  'no_return' 'name an absent agent result'
want commands/complete.md                   'no_return' 'name an absent agent result'
want commands/propose-epics.md              'no_return' 'name an absent agent result'

# --- and names a consequence that is NOT the passing one, per consumer ---
# These differ deliberately. A missing surface selection is not a missing epic verdict.
want commands/validate-visual-regression.md 'unresolved' 'refuse a clean skip on an absent selection'
want commands/validate-guides.md            'unresolved' 'refuse zero coverage gaps on an absent match set'
want commands/implement.md                  'insufficient_info' 'refuse keep_flat on an absent scope verdict'
want commands/propose-epics.md              'insufficient_info' 'refuse keep_flat on an absent scope verdict'

# --- the consequences must not all be the same string ---
# A single shared consequence would mean somebody flattened distinctions the framework keeps.
DISTINCT=$(grep -ho -E 'unresolved|insufficient_info|not_searched' \
  "$ROOT/commands/validate-visual-regression.md" "$ROOT/commands/validate-guides.md" \
  "$ROOT/commands/implement.md" "$ROOT/commands/propose-epics.md" 2>/dev/null | sort -u | wc -l)
checked=$((checked + 1))
if [ "$DISTINCT" -ge 2 ]; then
  echo "PASS: consumers record $DISTINCT distinct consequences, not one flattened value"
else
  echo "FAIL: every consumer records the same consequence, which flattens events the framework separates"
  fail=1
fi

# --- the executable half: an empty input is a distinct, non-zero outcome ---
NORM="$ROOT/scripts/analysis-agent-normalize.sh"
if [ -x "$NORM" ] || [ -f "$NORM" ]; then
  checked=$((checked + 1))
  printf '' | bash "$NORM" - >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "PASS: an empty payload exits 2, distinct from unparseable input"
  else
    echo "FAIL: an empty payload exits $rc; before v5.37.0 it exited 0 with empty output, which is"
    echo "      indistinguishable from a run that legitimately filtered everything out"
    fail=1
  fi
  checked=$((checked + 1))
  printf '{"decision":"keep_flat","notes":[]}' | bash "$NORM" - >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "PASS: a payload missing required keys exits 2 rather than passing through unchecked"
  else
    echo "FAIL: a payload missing code_read and confidence exits $rc; the clamp cannot fire without"
    echo "      code_read, so this would read as an answer that had already been checked"
    fail=1
  fi
  # A verdict is an OBJECT. null, a list, a string, a number and a boolean are all valid JSON and
  # none of them is an answer. The first version of the empty-input check missed this: `null`
  # reached the clamp, `.code_read` on null is null, null is not false, so the clamp did not fire
  # and `null` came out on stdout with exit 0 — the silent default this release exists to remove,
  # rebuilt inside the fix for it. A string or number made the key check throw, and the fallback
  # read the throw as "nothing missing", which is the same pattern removed from
  # build-critique-assert.sh the day before.
  for bad in 'null' '[]' '"a string"' '42' 'true'; do
    checked=$((checked + 1))
    printf '%s' "$bad" | bash "$NORM" - >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "PASS: a payload of $bad is rejected as not an object"
    else
      echo "FAIL: a payload of $bad exits $rc; valid JSON that is not an object is not an answer"
      fail=1
    fi
  done

  checked=$((checked + 1))
  printf '{"decision":"keep_flat","confidence":"high","code_read":true}' | bash "$NORM" - >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "PASS: a well-formed payload still exits 0"
  else
    echo "FAIL: a well-formed payload exits $rc; the new checks reject a good input"
    fail=1
  fi
else
  echo "FAIL: normalizer not found at scripts/analysis-agent-normalize.sh"
  fail=1
fi

if [ "$checked" -lt 20 ]; then
  echo "FAIL: only $checked assertions ran; this spec expects 20"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "OK   absent sidecar: $checked assertions across 7 consumers and the normalizer"
exit "$fail"
