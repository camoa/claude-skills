#!/usr/bin/env bash
# Enforcement/observability test for the process-recipe path (v5.11.0+).
#
# The process-recipe path degrades to the framework-neutral floor silently when a
# recipe (or a recipe's gate declaration) is absent. v5.11.0 makes that visible +
# auditable via recipe-resolution.md step 7: (a) the recipe-declarations-audit.sh
# lint surfaces an absent recommended declaration, and (b) a `_recipe-load.json`
# gate audit records the resolution outcome (incl. degrade-first bypass branches).
#
# This spec guards two things:
#   WIRING  — the lint + audit are actually referenced by the protocol, so the
#             linter cannot silently re-orphan (the exact failure this fixes).
#   BEHAVIOR— gate-audit-write.sh really accepts the new `recipe-load` gate type
#             and writes `_recipe-load.json`; the lint really flags an absent
#             recommended declaration and passes a complete one.
#
# Exit: 0 = all pass; 1 = a failure.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."
PROTO="$ROOT/references/recipe-resolution.md"
AUDIT_WRITE="$ROOT/scripts/gate-audit-write.sh"
DECL_AUDIT="$ROOT/scripts/recipe-declarations-audit.sh"
fail=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

# ── WIRING: the linter + audit are referenced by the protocol (anti re-orphan) ──
for f in "$PROTO" "$AUDIT_WRITE" "$DECL_AUDIT"; do
  [ -f "$f" ] || { bad "missing required file: $f"; }
done

grep -Fq -- 'recipe-declarations-audit.sh' "$PROTO" \
  && pass "protocol references recipe-declarations-audit.sh (linter wired, not orphaned)" \
  || bad  "recipe-resolution.md does NOT reference recipe-declarations-audit.sh — linter re-orphaned"

grep -Fq -- 'gate-audit-write.sh' "$PROTO" && grep -Fq -- 'recipe-load' "$PROTO" \
  && pass "protocol references gate-audit-write.sh + recipe-load (audit wired)" \
  || bad  "recipe-resolution.md does NOT wire the _recipe-load.json audit-write"

# Every command that RESOLVES + FOLLOWS a recipe body (reads body_path) must carry the step-7
# audit write, or that entry point becomes a silent-resolution bypass (the research-team.md hole).
# `/upgrade-project` is deliberately excluded — it records sources without ever reading a body.
# NEW body-following callers MUST be added here AND given a step-7 pointer.
BODY_FOLLOWING_CALLERS="research design implement review setup-e2e setup-visual-regression research-team"
for cmd in $BODY_FOLLOWING_CALLERS; do
  cf="$ROOT/commands/$cmd.md"
  if [ ! -f "$cf" ]; then bad "body-following caller missing: commands/$cmd.md"; continue; fi
  if grep -Fq -- 'recipe-load' "$cf"; then
    pass "commands/$cmd.md carries the step-7 recipe-load write (not a silent bypass)"
  else
    bad  "commands/$cmd.md resolves a recipe body but has NO step-7 _recipe-load.json write — silent-resolution bypass"
  fi
done

# ── BEHAVIOR: gate-audit-write accepts the new recipe-load gate type ──
PAYLOAD=$(jq -nc --arg tf "$TMP" '{
  schema_version:"1.4", gate_type:"recipe-load", fired_at:"2026-01-01T00:00:00Z",
  task_folder:$tf, user_choice:"automatic", bypass_reason:null,
  gate_specific:{phase:"review", resolved_count:0, frameworks:[],
    bypass:{reason:"no_frameworks_defined"}}}')
if bash "$AUDIT_WRITE" "$TMP" recipe-load "$PAYLOAD" >/dev/null 2>&1 && [ -f "$TMP/_recipe-load.json" ]; then
  pass "gate-audit-write.sh accepts recipe-load + schema 1.4 → wrote _recipe-load.json"
else
  bad  "gate-audit-write.sh rejected recipe-load gate type or did not write _recipe-load.json"
fi

# guard: an unknown gate type is still rejected (the allowlist didn't go open)
if bash "$AUDIT_WRITE" "$TMP" not-a-real-gate "$PAYLOAD" >/dev/null 2>&1; then
  bad  "gate-audit-write.sh accepted a bogus gate type (allowlist regressed)"
else
  pass "gate-audit-write.sh still rejects an unknown gate type"
fi

# ── BEHAVIOR: the lint flags an absent recommended declaration, passes a full one ──
# review phase expects (per the kernel): code_quality_extensions (rec:0) + '## Change-impact globs' (rec:1)
BODY_MISSING="$TMP/recipe-missing.md"
printf '%s\n' '# review recipe' 'code_quality_extensions: phpstan' '(no change-impact section here)' > "$BODY_MISSING"
ABS_MISSING=$(bash "$DECL_AUDIT" --body "$BODY_MISSING" --phase review --framework drupal | jq -r '.summary.absent_recommended')
[ "$ABS_MISSING" = "1" ] \
  && pass "lint flags the absent recommended declaration (absent_recommended=1)" \
  || bad  "lint did NOT flag the missing '## Change-impact globs' (absent_recommended=$ABS_MISSING)"

BODY_FULL="$TMP/recipe-full.md"
printf '%s\n' '# review recipe' 'code_quality_extensions: phpstan' '## Change-impact globs' '- "**/*.php"' > "$BODY_FULL"
ABS_FULL=$(bash "$DECL_AUDIT" --body "$BODY_FULL" --phase review --framework drupal | jq -r '.summary.absent_recommended')
[ "$ABS_FULL" = "0" ] \
  && pass "lint passes a complete recipe (absent_recommended=0)" \
  || bad  "lint false-flagged a complete recipe (absent_recommended=$ABS_FULL)"

echo
[ "$fail" -eq 0 ] && { echo "recipe-enforcement-spec: ALL PASS"; exit 0; } || { echo "recipe-enforcement-spec: FAILURES"; exit 1; }
