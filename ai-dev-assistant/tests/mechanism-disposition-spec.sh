#!/usr/bin/env bash
# Behavioral spec for scripts/mechanism-disposition.sh — the deterministic mechanism-challenge matrix
# (GAP G). Exhaustive over grounding {verified,unverified,none} × mode {attended,unattended} × hint
# {none,suggested,required} = 18 cells. The matrix MUST be deterministic (no model judgment) so it is
# identical across attended/unattended runs and CI-verifiable. The load-bearing safety cells:
#   - verified + unattended + required → defer (NEVER auto-swap an author-locked mechanism)
#   - unverified + unattended          → defer (an unverified web supersede never auto-applies)
#   - any attended supersede           → surface + blocks (human decides; build halts)
#   - none (no supersede)              → keep (regardless of mode/hint)
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
K="$ROOT/scripts/mechanism-disposition.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
no(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# exp <grounding> <mode> <hint> <action> <blocks> <decided_by>
exp(){
  local g="$1" m="$2" h="$3" ea="$4" eb="$5" ed="$6"
  local out; out="$("$K" --grounding "$g" --mode "$m" --hint "$h")"
  local a b d
  a="$(jq -r '.action' <<<"$out")"; b="$(jq -r '.blocks' <<<"$out")"; d="$(jq -r '.decided_by' <<<"$out")"
  if [ "$a" = "$ea" ] && [ "$b" = "$eb" ] && [ "$d" = "$ed" ]; then ok
  else no "$g/$m/$h => got {$a,$b,$d} expected {$ea,$eb,$ed}"; fi
}

# --- grounding=none → keep/false/auto for ALL mode×hint (6 cells) ---
for m in attended unattended; do for h in none suggested required; do
  exp none "$m" "$h" keep false auto
done; done

# --- grounding=verified ---
# attended (any hint) → surface/true/human (3 cells)
for h in none suggested required; do exp verified attended "$h" surface true human; done
# unattended + none/suggested → auto_adopt/false/auto (2 cells)
exp verified unattended none      auto_adopt false auto
exp verified unattended suggested auto_adopt false auto
# unattended + required → defer/false/deferred (the author-lock exception) (1 cell)
exp verified unattended required  defer false deferred

# --- grounding=unverified ---
# attended (any hint) → surface/true/human (3 cells)
for h in none suggested required; do exp unverified attended "$h" surface true human; done
# unattended (any hint) → defer/false/deferred (3 cells)
for h in none suggested required; do exp unverified unattended "$h" defer false deferred; done

# --- input validation: bad args fail-closed (exit 2, no verdict) ---
"$K" --grounding bogus --mode attended --hint none >/dev/null 2>&1 && no "bad grounding should exit 2" || ok
"$K" --grounding verified --mode bogus --hint none >/dev/null 2>&1 && no "bad mode should exit 2" || ok
"$K" --grounding verified --mode attended --hint bogus >/dev/null 2>&1 && no "bad hint should exit 2" || ok
# hint defaults to none when omitted
DA="$("$K" --grounding none --mode attended)"; [ "$(jq -r '.action' <<<"$DA")" = "keep" ] && ok || no "omitted hint should default none"

echo "----"; echo "mechanism-disposition-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
