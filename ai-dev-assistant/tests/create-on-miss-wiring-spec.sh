#!/usr/bin/env bash
# Doc-contract test for the maintainer create-on-miss / recipe-gap wiring (v5.16.0).
#
# The ROOT CAUSE this guards against (from the p2_tokens-era audit): the navigator's create-on-miss
# offer was real but lived only in the navigator skill body, and the lifecycle's guide preflight
# (script + guides-matcher agent over the cache) never invoked it — so it could never surface. This
# wiring moves the offer to the COMMAND level (where a prompt reaches the user). These assertions fail
# if that wiring regresses out of the command prose.
#
# Three surfaces (references/maintainer-create-on-miss.md):
#   1. GUIDE  — assertive one-time OFFER, handoff to /create-guide (research Step 3 + design Step 2).
#   2. AGENTIC-RECIPE — PROPOSE-ONLY notice on genuine no_match (research step 2c).
#   3. PROCESS-RECIPE — PROPOSE-ONLY note appended to the ask-user (recipe-resolution step 5).
# All gated on maintainer_mode == true; consumers never see them; none block.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$DIR/.."
SCRIPT="$ROOT/scripts/maintainer-mode-detect.sh"
REF="$ROOT/references/maintainer-create-on-miss.md"
RESEARCH="$ROOT/commands/research.md"
DESIGN="$ROOT/commands/design.md"
IMPLEMENT="$ROOT/commands/implement.md"
RECIPERES="$ROOT/references/recipe-resolution.md"
fail=0
for f in "$SCRIPT" "$REF" "$RESEARCH" "$DESIGN" "$IMPLEMENT" "$RECIPERES"; do [ -f "$f" ] || { echo "FAIL: missing $f"; fail=1; }; done

has() { # <file> <description> [grep flags...] <pattern>
  local f="$1" d="$2"; shift 2
  if grep -Eq "$@" "$f"; then echo "PASS: $d"; else echo "FAIL: $d  (missing: $* in $(basename "$f"))"; fail=1; fi
}
hasnt() { # <file> <description> [grep flags...] <pattern that must NOT appear>
  local f="$1" d="$2"; shift 2
  if grep -Eq "$@" "$f"; then echo "FAIL: $d  (present but must not be: $* in $(basename "$f"))"; fail=1; else echo "PASS: $d"; fi
}

# --- The detector kernel exists + is the canonical gate ---
has "$SCRIPT"  "detector emits maintainer_mode + dg_src"        'maintainer_mode'
has "$SCRIPT"  "detector uses the full 4-part signature"        'generate_llms\.py'
has "$SCRIPT"  "detector checks docs/agentic-recipes"           'docs/agentic-recipes'

# --- The reference doc carries all three surfaces ---
has "$REF" "reference: Surface 1 GUIDE offer"                   'Surface 1'
has "$REF" "reference: Surface 2 agentic-recipe propose"       'Surface 2'
has "$REF" "reference: Surface 3 process-recipe propose"       'Surface 3'
has "$REF" "reference: guides hand off to /create-guide"        '/create-guide'
has "$REF" "reference: recipes are propose-only (no authoring)" -i 'propose-only|propose only|visibility only'
has "$REF" "reference: consumers never see it"                  -i 'consumer'

# --- Surface 1 wired into /research, /design AND /implement (every guide-loading phase), gated + one-time + handoff ---
for f in "$RESEARCH" "$DESIGN" "$IMPLEMENT"; do
  n="$(basename "$f")"
  has "$f" "$n: runs the maintainer-mode detector"             'maintainer-mode-detect\.sh'
  has "$f" "$n: guide offer gated on maintainer_mode"          'maintainer_mode'
  has "$f" "$n: genuine-miss trigger (domain group empty)"     -i 'genuine (domain )?miss|none auto-matched|catalog_candidates'
  has "$f" "$n: hands off to /create-guide"                    '/create-guide'
  has "$f" "$n: one-time via DURABLE _create-on-miss.json sidecar" '_create-on-miss\.json'
  has "$f" "$n: durable record, NOT the overwrite-on-fire audit" -i 'overwrite-on-fire|observability only|durabl'
  has "$f" "$n: never authors here (detect/offer/handoff)"     -i 'never author|hand off'
done

# The one-time record MUST be durable, not the overwrite-on-fire _dev-guides-load.json (the red-team bug:
# the offer fires in BOTH /research and /design, so a per-run-overwritten audit cannot suppress the re-offer).
has "$REF" "reference: durable sidecar is the suppression source"  '_create-on-miss\.json'
has "$REF" "reference: names the overwrite-on-fire hazard"         -i 'overwrite-on-fire'

# --- Surface 2: agentic-recipe propose-only in research step 2c ---
has "$RESEARCH" "research: agentic-recipe propose on no_match"  -i 'recipe_gap_proposed'
has "$RESEARCH" "research: propose gated on recipe_lookup_status ok" 'recipe_lookup_status == "ok"'
has "$RESEARCH" "research: propose is NOT a y/n offer"          -i 'propose-only|visibility only|informational'

# --- Surface 3: process-recipe propose-only appended to ask-user ---
has "$RECIPERES" "recipe-resolution: maintainer recipe-gap note" -i 'maintainer'
has "$RECIPERES" "recipe-resolution: runs the detector"         'maintainer-mode-detect\.sh'
has "$RECIPERES" "recipe-resolution: propose-only, no handoff"  -i 'propose-only|not done automatically|no authoring'

# --- Negative guard: there is NO /create-recipe authoring wiring (scope: recipes propose only) ---
hasnt "$REF"      "no /create-recipe authoring handoff in reference"   '/create-recipe'
hasnt "$RESEARCH" "no /create-recipe authoring handoff in research"    '/create-recipe'

echo
if [ "$fail" -eq 0 ]; then echo "create-on-miss-wiring-spec: ALL PASS"; exit 0; else echo "create-on-miss-wiring-spec: FAILURES"; exit 1; fi
