#!/usr/bin/env bash
# Enforcement/wiring test for the agentic-recipe (capability-class) path (v5.12.0+).
#
# The agentic-recipe class (recipe-loader) was previously ORPHANED — no caller, no
# gate, no executor — so a verifier-carrying capability recipe never ran. v5.12.0 lands
# it: `references/agentic-recipe-resolution.md` is the orchestrator contract, `/research`
# is the Phase-1 caller + hard-gate-with-escape, and `/implement` (`## Sequence`) +
# `/review` (`## Verifier` as a gate) thread the adopted recipe downstream. The decision
# (and later the verifier outcome) persist to `_agentic-recipe.json` (gate audit, v1.5).
#
# This spec guards two things:
#   WIRING  — the protocol + its callers actually reference each other, so recipe-loader
#             cannot silently re-orphan (the exact failure this fixes).
#   BEHAVIOR— gate-audit-write.sh really accepts the new `agentic-recipe` gate type +
#             schema 1.5 and writes `_agentic-recipe.json`; an unknown gate type is still
#             rejected; a pre-existing type (recipe-load / schema 1.4) STILL works.
#
# Exit: 0 = all pass; 1 = a failure.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."
PROTO="$ROOT/references/agentic-recipe-resolution.md"
AUDIT_WRITE="$ROOT/scripts/gate-audit-write.sh"
RESEARCH="$ROOT/commands/research.md"
IMPLEMENT="$ROOT/commands/implement.md"
REVIEW="$ROOT/commands/review.md"
SCHEMA="$ROOT/references/gate-audit-schema.md"
COVERAGE="$ROOT/skills/recipe-loader/references/coverage-map-contract.md"
fail=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

# ── WIRING: protocol exists + names its resolver + audit primitive ──
for f in "$PROTO" "$AUDIT_WRITE" "$RESEARCH" "$IMPLEMENT" "$REVIEW"; do
  [ -f "$f" ] || bad "missing required file: $f"
done

grep -Fq -- 'recipe-loader' "$PROTO" \
  && pass "protocol references the recipe-loader resolver" \
  || bad  "agentic-recipe-resolution.md does NOT reference recipe-loader — resolver unwired"

grep -Fq -- 'gate-audit-write.sh' "$PROTO" && grep -Fq -- 'agentic-recipe' "$PROTO" \
  && pass "protocol wires gate-audit-write.sh + agentic-recipe (audit wired)" \
  || bad  "agentic-recipe-resolution.md does NOT wire the _agentic-recipe.json audit-write"

# The /research caller must reference the protocol (the gate's entry point is wired, not orphaned).
grep -Fq -- 'agentic-recipe-resolution' "$RESEARCH" \
  && pass "commands/research.md references agentic-recipe-resolution (caller wired)" \
  || bad  "commands/research.md does NOT reference agentic-recipe-resolution — gate re-orphaned"

# The idempotency short-circuit must be decision-aware: a `deferred` match (recorded by an
# unattended run) must RE-ENTER the gate on the next attended run, never be swallowed by bare
# `_agentic-recipe.json` existence. Guard the exact fix for the deferred-swallow defect.
if grep -Fq -- 'deferred' "$RESEARCH" && grep -Eq -- 're-enter|re-surface' "$RESEARCH"; then
  pass "research.md idempotency re-enters the gate on a deferred match (not swallowed)"
else
  bad  "research.md idempotency may swallow a deferred match (decision-aware short-circuit missing)"
fi

# Downstream threading: /implement follows the Sequence, /review runs the Verifier.
for cmd in implement review; do
  cf="$ROOT/commands/$cmd.md"
  if grep -Fq -- 'agentic-recipe-resolution' "$cf"; then
    pass "commands/$cmd.md references agentic-recipe-resolution (downstream threading wired)"
  else
    bad  "commands/$cmd.md does NOT reference agentic-recipe-resolution — downstream thread missing"
  fi
done

# ── BEHAVIOR: gate-audit-write accepts the new agentic-recipe gate type + schema 1.5 ──
PAYLOAD=$(jq -nc --arg tf "$TMP" '{
  schema_version:"1.5", gate_type:"agentic-recipe", fired_at:"2026-01-01T00:00:00Z",
  task_folder:$tf, user_choice:"a", bypass_reason:null,
  gate_specific:{capability:"seo-foundation", recipe_name:"seo_foundation_wiring",
    recipe_sha:"a1b2c3d4", provenance:"upstream", verified:true,
    decision:"adopted", reason:null,
    verifier:{ran:false, verdict:null, failed_checks:[]}}}')
if bash "$AUDIT_WRITE" "$TMP" agentic-recipe "$PAYLOAD" >/dev/null 2>&1 && [ -f "$TMP/_agentic-recipe.json" ]; then
  pass "gate-audit-write.sh accepts agentic-recipe + schema 1.5 → wrote _agentic-recipe.json"
else
  bad  "gate-audit-write.sh rejected agentic-recipe gate type or did not write _agentic-recipe.json"
fi

# guard: an unknown gate type is still rejected (the allowlist didn't go open)
if bash "$AUDIT_WRITE" "$TMP" not-a-real-gate "$PAYLOAD" >/dev/null 2>&1; then
  bad  "gate-audit-write.sh accepted a bogus gate type (allowlist regressed)"
else
  pass "gate-audit-write.sh still rejects an unknown gate type"
fi

# backward-compat: a pre-existing type (recipe-load / schema 1.4) STILL works.
RL_PAYLOAD=$(jq -nc --arg tf "$TMP" '{
  schema_version:"1.4", gate_type:"recipe-load", fired_at:"2026-01-01T00:00:00Z",
  task_folder:$tf, user_choice:"automatic", bypass_reason:null,
  gate_specific:{phase:"review", resolved_count:0, frameworks:[],
    bypass:{reason:"no_frameworks_defined"}}}')
if bash "$AUDIT_WRITE" "$TMP" recipe-load "$RL_PAYLOAD" >/dev/null 2>&1 && [ -f "$TMP/_recipe-load.json" ]; then
  pass "gate-audit-write.sh still accepts the pre-existing recipe-load + schema 1.4 (backward-compat)"
else
  bad  "gate-audit-write.sh regressed the pre-existing recipe-load gate type"
fi

# ── v5.12.1: the adopted body is PERSISTED to the task folder + the phantom path is GONE ──
# The 5.12.0 execute half told /implement + /review to Read a "navigator-served body_path" that the
# AGENTIC discovery path never emits (that's the PROCESS-recipe mechanism). The fix: /research persists
# the adopted body into the task folder (adopted-recipe.md) + records body_path; downstream reads THAT.

# (a) /research persists the body to a task-folder file AND records body_path.
if grep -Fq -- 'adopted-recipe.md' "$RESEARCH" && grep -Fq -- 'body_path' "$RESEARCH"; then
  pass "research.md persists the adopted body to <task_folder>/adopted-recipe.md + records body_path"
else
  bad  "research.md does NOT persist adopted-recipe.md / record body_path (adopted recipe unfollowable)"
fi

# (b) /implement AND /review read the PERSISTED task-folder body; the phantom string is GONE from the
#     agentic step of each. Scope the phantom grep to the literal "navigator-served `body_path`" so the
#     legitimate PROCESS-recipe `body_path` reads elsewhere in these files are NOT matched.
PHANTOM='navigator-served `body_path`'
for cmd in implement review; do
  cf="$ROOT/commands/$cmd.md"
  if grep -Fq -- 'adopted-recipe.md' "$cf"; then
    pass "commands/$cmd.md reads the persisted task-folder body (adopted-recipe.md)"
  else
    bad  "commands/$cmd.md does NOT read <task_folder>/adopted-recipe.md (still chasing a phantom path)"
  fi
  n=$(grep -cF -- "$PHANTOM" "$cf")
  if [ "$n" -eq 0 ]; then
    pass "commands/$cmd.md no longer references the phantom navigator-served body_path"
  else
    bad  "commands/$cmd.md still references the phantom 'navigator-served \`body_path\`' ($n hit(s))"
  fi
done

# (c) §5.13 of the gate-audit schema gained body_path (additive; schema stays v1.5).
SEC513="$(awk '/^### 5.13 /{f=1} /^## 6\. /{f=0} f' "$SCHEMA")"
if printf '%s' "$SEC513" | grep -Fq -- 'body_path'; then
  pass "gate-audit-schema §5.13 carries body_path (additive, v1.5)"
else
  bad  "gate-audit-schema §5.13 missing body_path — the persisted spine is unrecorded"
fi

# (d) the coverage-map contract carries recipe_name + recipe_sha on kind:recipe entries.
if grep -Fq -- 'recipe_name' "$COVERAGE" && grep -Fq -- 'recipe_sha' "$COVERAGE"; then
  pass "coverage-map-contract carries recipe_name + recipe_sha (durable adopt handle)"
else
  bad  "coverage-map-contract missing recipe_name/recipe_sha — orchestrator can't persist the body"
fi

echo
[ "$fail" -eq 0 ] && { echo "agentic-recipe-enforcement-spec: ALL PASS"; exit 0; } || { echo "agentic-recipe-enforcement-spec: FAILURES"; exit 1; }
