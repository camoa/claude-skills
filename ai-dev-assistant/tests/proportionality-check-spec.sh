#!/usr/bin/env bash
# Behavioral spec for scripts/proportionality-check.sh, the deterministic proportionality kernel.
# Exhaustive over the kernel's three branches and their boundaries:
#   1. no --expected-lines given            → cannot_judge/false/none, for ANY --actual-lines
#   2. --expected-lines given, ratio ≤ ceiling → within_expectation/false/ratio (boundary inclusive)
#   3. --expected-lines given, ratio > ceiling → disproportionate/false/ratio
# plus the zero-expectation edge (ceiling=0), a non-default multiplier, and every invalid-argument shape.
# The load-bearing cells:
#   - no expectation declared           → cannot_judge, NEVER within_expectation (the defect this repairs)
#   - actual-lines == ceiling exactly   → within_expectation (boundary is inclusive, not disproportionate)
#   - expected-lines 0, actual-lines 0  → within_expectation (0 > 0 is false)
#   - expected-lines 0, actual-lines >0 → disproportionate immediately (any work where none was declared)
#   - every action                      → blocks is always false (this check surfaces, never halts)
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/proportionality-check.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# exp <args...> -- <action> <blocks> <decided_by>
# Splits on a literal "--" so callers can pass a variable-length arg list.
exp(){
  local args=() ea eb ed sawsep=0
  for a in "$@"; do
    if [ "$sawsep" -eq 0 ] && [ "$a" = "--" ]; then sawsep=1; continue; fi
    if [ "$sawsep" -eq 0 ]; then args+=("$a"); else
      if [ -z "${ea:-}" ]; then ea="$a"; elif [ -z "${eb:-}" ]; then eb="$a"; else ed="$a"; fi
    fi
  done
  local out; out="$("$K" "${args[@]}")"
  local a b d
  a="$(jq -r '.action' <<<"$out")"; b="$(jq -r '.blocks' <<<"$out")"; d="$(jq -r '.decided_by' <<<"$out")"
  if [ "$a" = "$ea" ] && [ "$b" = "$eb" ] && [ "$d" = "$ed" ]; then ok
  else no "${args[*]} => got {$a,$b,$d} expected {$ea,$eb,$ed}"; fi
}

# --- branch 1: no --expected-lines → cannot_judge/false/none, regardless of --actual-lines ---
# Reporting an undeclared expectation as within_expectation is the exact defect this check exists to
# avoid repeating (mechanism-disposition.sh's `none` vs `not_searched` split, for the same reason).
exp --actual-lines 0    -- cannot_judge false none
exp --actual-lines 1    -- cannot_judge false none
exp --actual-lines 1000 -- cannot_judge false none

# --- branch 2/3: default multiplier (3), around the boundary ---
exp --actual-lines 29 --expected-lines 10 -- within_expectation false ratio
exp --actual-lines 30 --expected-lines 10 -- within_expectation false ratio   # boundary: == ceiling, inclusive
exp --actual-lines 31 --expected-lines 10 -- disproportionate   false ratio
exp --actual-lines 10 --expected-lines 10 -- within_expectation false ratio   # ratio 1:1
exp --actual-lines 0  --expected-lines 10 -- within_expectation false ratio   # under expectation is not disproportion

# --- zero-expectation edge: ceiling is 0*multiplier = 0 regardless of multiplier ---
exp --actual-lines 0 --expected-lines 0 -- within_expectation false ratio
exp --actual-lines 1 --expected-lines 0 -- disproportionate   false ratio

# --- non-default multiplier ---
exp --actual-lines 10 --expected-lines 10 --multiplier 1 -- within_expectation false ratio  # boundary
exp --actual-lines 11 --expected-lines 10 --multiplier 1 -- disproportionate   false ratio
exp --actual-lines 500 --expected-lines 100 --multiplier 5 -- within_expectation false ratio # boundary
exp --actual-lines 501 --expected-lines 100 --multiplier 5 -- disproportionate   false ratio

# --- evidence cases from the two live builds this check was built to catch ---
# ~1 line route + ~6 line component (declared 7) vs a 566-line peak: disproportionate.
exp --actual-lines 566  --expected-lines 7  -- disproportionate false ratio
# "create a directory and write a stub file" (declared 20) vs 1,637 insertions: disproportionate.
exp --actual-lines 1637 --expected-lines 20 -- disproportionate false ratio

# A flag with no value must exit 2, not hang. Inherited from mechanism-disposition.sh's arg loop and
# fixed in both: `shift 2` fails when one positional remains, so `$#` never decreases and the loop
# spins forever printing nothing.
for f in --actual-lines --expected-lines --multiplier; do
  timeout 5 "$K" "$f" >/dev/null 2>&1
  [ "$?" -eq 2 ] && ok || no "$f with no value must exit 2, not hang or pass"
done

# --- input validation: bad/missing args fail-closed (exit 2, no verdict) ---
"$K" >/dev/null 2>&1 && no "missing --actual-lines should exit 2" || ok
"$K" --actual-lines abc >/dev/null 2>&1 && no "non-numeric --actual-lines should exit 2" || ok
"$K" --actual-lines -5 >/dev/null 2>&1 && no "negative --actual-lines should exit 2" || ok
"$K" --actual-lines 07 >/dev/null 2>&1 && no "leading-zero --actual-lines should exit 2" || ok
"$K" --actual-lines 3.5 >/dev/null 2>&1 && no "non-integer --actual-lines should exit 2" || ok
"$K" --actual-lines 5 --expected-lines abc >/dev/null 2>&1 && no "non-numeric --expected-lines should exit 2" || ok
"$K" --actual-lines 5 --expected-lines -1 >/dev/null 2>&1 && no "negative --expected-lines should exit 2" || ok
"$K" --actual-lines 5 --multiplier 0 >/dev/null 2>&1 && no "zero --multiplier should exit 2" || ok
"$K" --actual-lines 5 --multiplier -1 >/dev/null 2>&1 && no "negative --multiplier should exit 2" || ok
"$K" --actual-lines 5 --multiplier 2.5 >/dev/null 2>&1 && no "non-integer --multiplier should exit 2" || ok
"$K" --actual-lines 5 --bogus >/dev/null 2>&1 && no "unknown arg should exit 2" || ok

# --- exit code discipline: a valid call exits 0 ---
"$K" --actual-lines 5 --expected-lines 5 >/dev/null 2>&1; [ $? -eq 0 ] && ok || no "valid call should exit 0"

# --- guard: this spec must have checked something ---
[ "$((PASS + FAIL))" -gt 0 ] || { echo "proportionality-check-spec: checked nothing"; exit 2; }

echo "----"; echo "proportionality-check-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
