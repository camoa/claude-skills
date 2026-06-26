#!/usr/bin/env bash
# Doc-contract test for the mechanism-challenge wiring (GAP G, v5.17.0).
#
# GAP G: AIDA verifies faithful execution of its input, not whether the input's MECHANISM was right, so a
# wrong-mechanism task ships through every gate. This wiring makes a stated mechanism a challengeable
# assumption — researched against native/recipe patterns, dispositioned by a deterministic kernel, recorded,
# and asserted fail-closed at /review. These assertions fail if any load-bearing piece regresses.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$DIR/.."
KERNEL="$ROOT/scripts/mechanism-disposition.sh"
REF="$ROOT/references/mechanism-challenge.md"
SCHEMA="$ROOT/references/gate-audit-schema.md"
AUDITW="$ROOT/scripts/gate-audit-write.sh"
FMH="$ROOT/scripts/fm-helpers.sh"
RESEARCH="$ROOT/commands/research.md"; DESIGN="$ROOT/commands/design.md"
IMPLEMENT="$ROOT/commands/implement.md"; REVIEW="$ROOT/commands/review.md"
fail=0
for f in "$KERNEL" "$REF" "$SCHEMA" "$AUDITW" "$FMH" "$RESEARCH" "$DESIGN" "$IMPLEMENT" "$REVIEW"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; fail=1; }
done
has(){ local f="$1" d="$2"; shift 2; if grep -Eq "$@" "$f"; then echo "PASS: $d"; else echo "FAIL: $d (missing: $* in $(basename "$f"))"; fail=1; fi; }
hasnt(){ local f="$1" d="$2"; shift 2; if grep -Eq "$@" "$f"; then echo "FAIL: $d (must NOT appear: $* in $(basename "$f"))"; fail=1; else echo "PASS: $d"; fi; }

# --- the deterministic kernel exists + is executable behaviorally (sanity, full matrix in its own spec) ---
has "$KERNEL" "disposition kernel exists"                         'action'
[ -x "$KERNEL" ] && echo "PASS: kernel executable" || { echo "FAIL: kernel not executable"; fail=1; }

# --- reference doc carries the whole contract ---
has "$REF" "reference: cascade tier 1 agentic recipes"           -i 'agentic recipes'
has "$REF" "reference: cascade tier 2 dev-guides"                -i 'dev-guides'
has "$REF" "reference: cascade tier 3 quick web"                 -i 'quick web'
has "$REF" "reference: first hit wins (ordered cascade)"         -i 'first.*(hit|tier).*wins'
has "$REF" "reference: web tier recency <=1 year"                 -i '1 year|12-month|<= ?1'
has "$REF" "reference: recency double-enforced"                   -i 'double-enforced|post-filter'
has "$REF" "reference: disposition matrix"                        -i 'disposition matrix'
has "$REF" "reference: required-hint never auto-swapped"          -i 'required.*never|never auto-swap'
has "$REF" "reference: runs research/design/implement, asserts review" -i 'implement.*backstop|backstop'
has "$REF" "reference: mechanisms_hash freshness"                 'mechanisms_hash'
has "$REF" "reference: mechanism_hints optional, prose floor"     -i 'prose extraction is the floor|prose-extraction floor|never depends'

# --- audit plumbing: allowlist + schema section + count bump ---
has "$AUDITW" "gate-audit-write allowlists mechanism-challenge"   'mechanism-challenge'
has "$AUDITW" "allowlist count comment bumped to 14"             '14 allowed values'
has "$SCHEMA" "schema doc has the mechanism-challenge section"    -i 'mechanism-challenge'
has "$SCHEMA" "schema records challenge_ran + mechanisms_hash"    'challenge_ran'
has "$SCHEMA" "schema gate_type count bumped to 14"              'one of the 14'

# --- frontmatter reader exposes mechanism_hints (defaulting []) ---
has "$FMH" "fm-helpers emits mechanism_hints"                     'mechanism_hints'

# --- the four phase commands are wired ---
has "$RESEARCH"  "research 2c runs the challenge"                 'mechanism-disposition\.sh'
has "$DESIGN"    "design refreshes the challenge"                 -i 'mechanism-challenge'
has "$IMPLEMENT" "implement preflight backstop"                   -i 'mechanism-challenge backstop|backstop'
has "$IMPLEMENT" "implement backstop can HALT the build"          -i 'halt|block'
has "$REVIEW"    "review asserts mechanism-challenge gate"        'name: "mechanism-challenge"'
has "$REVIEW"    "review gate is fail-closed on absent record"    -i 'fail-closed|absent.*fail|skipped.*unresolved'
has "$REVIEW"    "review mechanism gate ALWAYS emits (not conditional)" -i 'always emits|NOT conditional|always runs'

# --- decoupling from the converter (scope guard) ---
hasnt "$REF"      "reference has no /create-recipe authoring"     '/create-recipe'
has   "$REF"      "reference states converter decoupling"         -i 'never depends on it|converter stops prescribing'
hasnt "$RESEARCH" "research has no converter import/dependency"   -i 'g-conv|converter (import|dependency)'

echo
if [ "$fail" -eq 0 ]; then echo "mechanism-challenge-wiring-spec: ALL PASS"; exit 0; else echo "mechanism-challenge-wiring-spec: FAILURES"; exit 1; fi
