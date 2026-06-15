#!/usr/bin/env bash
# recipe-consumption-spec.sh — prove process-recipe CONSUMPTION is real.
#
# tests/recipe-interface-spec.sh checks token SPELLING (a consumer greps the same
# token the contract documents). scripts/recipe-declarations-audit.sh lints recipe
# BODIES. Neither proves a consumer ACTS on a resolved recipe value. This test does:
# per interface declaration, a fixture recipe declaration must change consumer
# behaviour (or the wiring that makes consumption possible) vs its absence.
#
#   SCRIPT-backed declarations (run the real kernel, fixture vs none, assert differ):
#     - ## Change-impact globs   → change-impact-classify.sh --rules-from <fixture>
#                                  vs the neutral floor → recommended gates differ.
#     - e2e.preflight_command    → ensure-registry-preflight.sh with a fixture value
#                                  vs a registry never seeded → registry effect differs.
#
#   PROSE-backed declarations (model-driven commands — assert the wiring/ordering
#   that makes consumption possible, since they cannot be run behaviourally in bash):
#     - ## Routing hints         → implement.md resolves the recipe BEFORE a plan-mode
#                                  guides-matcher pass that injects routing_hints.
#                                  (REGRESSION GUARD for the routing-hints fix: FAILs on
#                                  the pre-fix ordering, PASSes after.)
#     - ## Code-quality extensions → review.md feeds the resolved value into the
#                                  code-quality file filter, reading the SAME body it
#                                  already resolved (not a hardcode).
#     - ## Screenshot capture    → setup-visual-regression.md reads the capture block
#                                  from the resolved recipe body.
#
# Deterministic, no network. Exit 0 = every consumption link proven; 1 = a break.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."
fail=0
pass() { echo "PASS: $1"; }
die()  { echo "FAIL: $1"; fail=1; }

need_jq() { command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required"; exit 1; }; }
need_jq

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CLASSIFY="$ROOT/scripts/change-impact-classify.sh"
PREFLIGHT="$ROOT/scripts/ensure-registry-preflight.sh"
IMPL="$ROOT/commands/implement.md"
REVIEW="$ROOT/commands/review.md"
SETUP_VR="$ROOT/commands/setup-visual-regression.md"

for f in "$CLASSIFY" "$PREFLIGHT" "$IMPL" "$REVIEW" "$SETUP_VR"; do
  [ -f "$f" ] || { echo "FAIL: required file missing: $f"; exit 1; }
done

# ---------------------------------------------------------------------------
# 1. ## Change-impact globs (SCRIPT) — fixture recipe rules change the verdict.
#    Neutral fixture ext (.tpl) names no real framework: it is NOT in the shipped
#    neutral floor, so absent-recipe → [] and present-recipe → the declared gate.
# ---------------------------------------------------------------------------
echo "templates/node.tpl" > "$TMP/files.txt"
cat > "$TMP/recipe-rules.json" <<'EOF'
{ "schema_version": "1.0",
  "rules": [ { "glob": "**/*.tpl", "gates": ["visual_regression"] } ] }
EOF

absent_gates="$(bash "$CLASSIFY" /nonexistent-task --files-from "$TMP/files.txt" 2>/dev/null | jq -c '.gates_recommended')"
present_gates="$(bash "$CLASSIFY" /nonexistent-task --files-from "$TMP/files.txt" --rules-from "$TMP/recipe-rules.json" 2>/dev/null | jq -c '.gates_recommended')"

if [ "$absent_gates" = "[]" ] && [ "$present_gates" = '["visual_regression"]' ] && [ "$absent_gates" != "$present_gates" ]; then
  pass "## Change-impact globs — recipe declaration changes the recommendation (absent=$absent_gates, present=$present_gates)"
else
  die "## Change-impact globs — recipe declaration did NOT change the verdict (absent=$absent_gates, present=$present_gates) — consumer ignores --rules-from?"
fi

# ---------------------------------------------------------------------------
# 2. e2e.preflight_command (SCRIPT) — a recipe-supplied value changes registry state.
#    Recipe declared a preflight → setup seeds it; recipe declared none → not seeded.
# ---------------------------------------------------------------------------
mk_registry() { printf '# surface registry\nsurfaces:\n  - id: home\n    url: /\n' > "$1"; }
mk_registry "$TMP/reg_with.yml"     # recipe DID declare a preflight_command
mk_registry "$TMP/reg_without.yml"  # recipe declared NONE — script is never invoked

PREFLIGHT_VALUE="npm run e2e:bootstrap"
bash "$PREFLIGHT" "$TMP/reg_with.yml" "$PREFLIGHT_VALUE" >/dev/null 2>&1

with_has="$(grep -c "preflight_command: \"$PREFLIGHT_VALUE\"" "$TMP/reg_with.yml" 2>/dev/null || true)"
without_has="$(grep -c 'preflight_command:' "$TMP/reg_without.yml" 2>/dev/null || true)"

if [ "$with_has" -ge 1 ] && [ "$without_has" -eq 0 ] && ! diff -q "$TMP/reg_with.yml" "$TMP/reg_without.yml" >/dev/null 2>&1; then
  pass "e2e.preflight_command — recipe value seeds the registry; absent leaves it unseeded (effect differs)"
else
  die "e2e.preflight_command — registry effect did NOT differ (with_has=$with_has, without_has=$without_has) — value not consumed?"
fi

# Idempotency corollary: re-running does not duplicate the field (a real consumer guard).
bash "$PREFLIGHT" "$TMP/reg_with.yml" "$PREFLIGHT_VALUE" >/dev/null 2>&1
dup_count="$(grep -c 'preflight_command:' "$TMP/reg_with.yml" 2>/dev/null || true)"
if [ "$dup_count" -eq 1 ]; then
  pass "e2e.preflight_command — re-seed is idempotent (single field)"
else
  die "e2e.preflight_command — re-seed duplicated the field ($dup_count occurrences)"
fi

# ---------------------------------------------------------------------------
# 3. ## Routing hints (PROSE / ordering) — REGRESSION GUARD.
#    implement.md must resolve the recipe (phase: implement) BEFORE a plan-mode
#    guides-matcher pass that injects routing_hints. Pre-fix the ONLY routing_hints
#    pass is the step-3 preflight, which runs before resolution → this FAILS.
#    Post-fix a supplemental step-6 pass injects routing_hints after resolution → PASS.
# ---------------------------------------------------------------------------
recipe_line="$(grep -n 'phase: implement' "$IMPL" | head -1 | cut -d: -f1)"
if [ -z "$recipe_line" ]; then
  die "## Routing hints — could not locate the implement recipe resolution (phase: implement) in implement.md"
else
  # First routing_hints reference that occurs AFTER the recipe is resolved.
  hints_line="$(awk -v r="$recipe_line" 'NR>r && /routing_hints/ {print NR; exit}' "$IMPL")"
  if [ -z "$hints_line" ]; then
    die "## Routing hints — no routing_hints injection occurs AFTER recipe resolution (line $recipe_line): the resolve→inject→consume chain never completes (pre-fix ordering)"
  else
    # The post-resolution routing_hints pass must be a real plan-mode guides-matcher consume.
    line_text="$(awk -v n="$hints_line" 'NR==n' "$IMPL")"
    if echo "$line_text" | grep -q 'guides-matcher' && echo "$line_text" | grep -q 'mode: "plan"'; then
      pass "## Routing hints — recipe resolved at line $recipe_line, routing_hints injected into a plan-mode guides-matcher pass at line $hints_line (after resolution)"
    else
      die "## Routing hints — routing_hints appears after resolution (line $hints_line) but not in a plan-mode guides-matcher pass (not a real consume)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 4. ## Code-quality extensions (PROSE / wiring) — review.md feeds the resolved
#    value into the code-quality file filter, reusing the SAME resolved body.
# ---------------------------------------------------------------------------
ck4=0
grep -Fq 'code_quality_extensions' "$REVIEW" || { die "## Code-quality extensions — review.md never names code_quality_extensions"; ck4=1; }
grep -Fq 'same review recipe body already Read at step 5.0' "$REVIEW" || { die "## Code-quality extensions — review.md does not reuse the step-5.0 resolved body (would be a second resolution or a hardcode)"; ck4=1; }
grep -Fq -- '--files' "$REVIEW" || { die "## Code-quality extensions — review.md does not feed the filtered list to the gates via --files"; ck4=1; }
[ "$ck4" -eq 0 ] && pass "## Code-quality extensions — review.md unions the recipe's code_quality_extensions (from the already-resolved body) into the --files gate filter"

# ---------------------------------------------------------------------------
# 5. ## Screenshot capture (PROSE / wiring) — setup-visual-regression.md reads the
#    capture block from the RESOLVED recipe body (not a hardcoded capture call).
# ---------------------------------------------------------------------------
ck5=0
grep -Fq '## Screenshot capture' "$SETUP_VR" || { die "## Screenshot capture — setup-visual-regression.md never reads the ## Screenshot capture block"; ck5=1; }
grep -Fq 'resolved VR process recipe' "$SETUP_VR" || { die "## Screenshot capture — setup-visual-regression.md does not tie the capture block to the resolved recipe body"; ck5=1; }
grep -Fq 'screenshot_import' "$SETUP_VR" && grep -Fq 'screenshot_capture' "$SETUP_VR" || { die "## Screenshot capture — setup-visual-regression.md does not substitute screenshot_import/screenshot_capture from the recipe"; ck5=1; }
grep -Fq 'captured_by' "$SETUP_VR" || { die "## Screenshot capture — setup-visual-regression.md does not record captured_by from the recipe"; ck5=1; }
[ "$ck5" -eq 0 ] && pass "## Screenshot capture — setup-visual-regression.md substitutes the resolved recipe's capture block (import/capture/captured_by) instead of the native default"

if [ "$fail" -eq 0 ]; then
  echo "OK: every recipe interface declaration is provably consumed"
fi
exit "$fail"
