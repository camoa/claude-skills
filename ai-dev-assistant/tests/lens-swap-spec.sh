#!/usr/bin/env bash
# Behavioral spec for the lens-swap component (review_ladder, PR 1). `skeptic` ("anything wrong at
# all") was the only lens a low-tier component got, and it is the exaggeration the epic exists to
# stop. Low tier now takes `correctness`, the lens that carries the method. `meets-ac` reads a
# component file's `## Acceptance criteria` as well as a work-order's `## Done =`.
#
# Cells:
#   - references/risk-tiering-rules.json tier_lenses.low is exactly ["correctness"]; low, medium
#     and high are each a non-empty array (a deleted lens must not leave a tier dispatching zero),
#     and security stays on medium and high.
#   - nothing tracked in the plugin names `skeptic`; tests/ may hold it as a fixture value and
#     CHANGELOG.md is history.
#   - agents/wo-critic.md's meets-ac definition names `## Acceptance criteria`.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
cannot_look() { printf 'lens-swap-spec: could not look: %s\n' "$1" >&2; exit 2; }

RULES="$ROOT/references/risk-tiering-rules.json"
[ -r "$RULES" ] || cannot_look "$RULES unreadable"
[ -r "$ROOT/agents/wo-critic.md" ] || cannot_look "$ROOT/agents/wo-critic.md unreadable"
command -v jq >/dev/null 2>&1 || cannot_look "jq is not on PATH"
command -v git >/dev/null 2>&1 || cannot_look "git is not on PATH"
TRACKED="$(git -C "$ROOT" ls-files -- . 2>/dev/null)" || cannot_look "$ROOT is not inside a git repository"
[ -n "$TRACKED" ] || cannot_look "git tracks nothing under $ROOT"

# Cell 1: low tier is exactly ["correctness"]
LOW="$(jq -c '.tier_lenses.low' "$RULES")" || cannot_look "risk-tiering-rules.json does not parse"
[ "$LOW" = '["correctness"]' ] && ok "tier_lenses.low is [\"correctness\"]" || bad "tier_lenses.low is $LOW"

# Cell 2: the invariant the swap relies on: low, medium, high each present, an array of at least
# one lens, and security still on medium and high.
if jq -e '.tier_lenses as $t
          | (["low","medium","high"] | all(. as $k | ($t[$k] | type == "array" and length >= 1)))
          and ($t.medium | index("security") != null) and ($t.high | index("security") != null)' "$RULES" >/dev/null; then
  ok "every tier is a non-empty lens array and security stays on medium and high"
else bad "tier_lenses invariant broken: $(jq -c .tier_lenses "$RULES")"; fi

# Cell 3: nothing tracked in the plugin names skeptic, tests (fixtures) and CHANGELOG (history) aside
HITS="$(git -C "$ROOT" grep -n -w 'skeptic' -- . ':!tests' ':!CHANGELOG.md' 2>/dev/null)"; GRC=$?
case "$GRC" in
  0) bad "an instruction or schema site still names skeptic" "$(printf '%s' "$HITS" | head -20)" ;;
  1) ok "no instruction or schema site names skeptic" ;;
  *) cannot_look "git grep exited $GRC" ;;
esac

# Cell 4: meets-ac reads a component file's heading too
if grep -q 'Acceptance criteria' "$ROOT/agents/wo-critic.md"; then ok "wo-critic.md's meets-ac names ## Acceptance criteria"
else bad "wo-critic.md's meets-ac names only ## Done ="; fi

echo "----"; echo "lens-swap-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
