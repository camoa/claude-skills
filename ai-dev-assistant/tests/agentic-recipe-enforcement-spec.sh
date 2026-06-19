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

# ── BEHAVIOR: gate-audit-write accepts the agentic-recipe gate type + schema 1.5 with the
#    v5.13.0 recipes[] LIST shape (a 2-element multi-recipe payload), and round-trips it. ──
PAYLOAD=$(jq -nc --arg tf "$TMP" '{
  schema_version:"1.5", gate_type:"agentic-recipe", fired_at:"2026-01-01T00:00:00Z",
  task_folder:$tf, user_choice:"a", bypass_reason:null,
  gate_specific:{recipes:[
    {capability:"seo-foundation", recipe_name:"seo_foundation_wiring",
     recipe_sha:"a1b2c3d4", provenance:"upstream", verified:true,
     decision:"adopted", reason:null,
     body_path:($tf + "/adopted-recipe-seo-foundation-wiring-a1b2c3d4.md"),
     verifier:{ran:false, verdict:null, failed_checks:[]}},
    {capability:"responsive-image-wiring", recipe_name:"responsive_image_wiring",
     recipe_sha:"e5f6a7b8", provenance:"upstream", verified:true,
     decision:"adopted", reason:null,
     body_path:($tf + "/adopted-recipe-responsive-image-wiring-e5f6a7b8.md"),
     verifier:{ran:false, verdict:null, failed_checks:[]}}]}}')
if bash "$AUDIT_WRITE" "$TMP" agentic-recipe "$PAYLOAD" >/dev/null 2>&1 && [ -f "$TMP/_agentic-recipe.json" ]; then
  pass "gate-audit-write.sh accepts agentic-recipe + schema 1.5 → wrote _agentic-recipe.json"
else
  bad  "gate-audit-write.sh rejected agentic-recipe gate type or did not write _agentic-recipe.json"
fi
# round-trip the recipes[] LIST shape (the actual v5.13.0 payload, not the old single object).
if [ -f "$TMP/_agentic-recipe.json" ] \
   && [ "$(jq -r '.gate_specific.recipes | length' "$TMP/_agentic-recipe.json")" = "2" ] \
   && jq -e '[.gate_specific.recipes[].recipe_name] | index("seo_foundation_wiring") != null and index("responsive_image_wiring") != null' "$TMP/_agentic-recipe.json" >/dev/null; then
  pass "round-trip: _agentic-recipe.json carries a 2-element recipes[] with both recipe_names (v5.13.0 shape)"
else
  bad  "_agentic-recipe.json did NOT round-trip the 2-element recipes[] shape (false-green: still single-object?)"
fi
# read-merge-write preservation: /review sets element B's verifier; element A's decision half must survive.
MERGED="$TMP/_agentic-recipe.merged.json"
jq '.gate_specific.recipes[1].verifier = {ran:true, verdict:"pass", failed_checks:[]}' \
   "$TMP/_agentic-recipe.json" > "$MERGED" 2>/dev/null
if jq -e '.gate_specific.recipes[0].recipe_name == "seo_foundation_wiring"
          and .gate_specific.recipes[0].decision == "adopted"
          and .gate_specific.recipes[1].verifier.verdict == "pass"
          and (.gate_specific.recipes | length) == 2' "$MERGED" >/dev/null 2>&1; then
  pass "read-merge-write preserves element A's decision half while element B's verifier is set"
else
  bad  "read-merge-write dropped/clobbered an element's decision half (data-loss seam)"
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

# (a) /research persists the body to a per-recipe task-folder file AND records body_path.
if grep -Fq -- 'adopted-recipe-' "$RESEARCH" && grep -Fq -- 'body_path' "$RESEARCH"; then
  pass "research.md persists the adopted body to <task_folder>/adopted-recipe-<name>.md + records body_path"
else
  bad  "research.md does NOT persist adopted-recipe-<name>.md / record body_path (adopted recipe unfollowable)"
fi

# (b) /implement AND /review read the PERSISTED task-folder body; the phantom string is GONE from the
#     agentic step of each. Scope the phantom grep to the literal "navigator-served `body_path`" so the
#     legitimate PROCESS-recipe `body_path` reads elsewhere in these files are NOT matched.
PHANTOM='navigator-served `body_path`'
for cmd in implement review; do
  cf="$ROOT/commands/$cmd.md"
  if grep -Fq -- 'adopted-recipe-' "$cf"; then
    pass "commands/$cmd.md reads the persisted per-recipe task-folder body (adopted-recipe-<name>.md)"
  else
    bad  "commands/$cmd.md does NOT read <task_folder>/adopted-recipe-<name>.md (still chasing a phantom path)"
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

# ── v5.13.0: MULTI-recipe adoption per task (recipes[] list, per-recipe persist, competing, iterate) ──
# A task may match MULTIPLE agentic recipes: a complementary set across distinct aspects, or one chosen
# winner of a competing same-aspect match. The audit generalises from one object to a recipes[] list;
# each adopted recipe persists its OWN body; competing matches ALWAYS ASK; the gate iterates per entry;
# idempotency re-enters while ANY matched recipe is deferred.

# (e) §5.13 documents a recipes[] list with a multi-element example (≥2 elements).
SEC513="$(awk '/^### 5.13 /{f=1} /^## 6\. /{f=0} f' "$SCHEMA")"
if printf '%s' "$SEC513" | grep -Eq -- '"recipes"[[:space:]]*:[[:space:]]*\[' \
   && [ "$(printf '%s' "$SEC513" | grep -c -- '"recipe_name"')" -ge 2 ]; then
  pass "gate-audit-schema §5.13 documents a recipes[] list with a ≥2-element example (multi-recipe)"
else
  bad  "gate-audit-schema §5.13 is not a recipes[] list / lacks a 2-element example (still single-object)"
fi

# (f) the protocol + /research persist a PER-RECIPE filename (adopted-recipe-<name>.md).
for f in "$PROTO" "$RESEARCH"; do
  if grep -Fq -- 'adopted-recipe-<' "$f"; then
    pass "$(basename "$f") uses the per-recipe filename adopted-recipe-<...>.md (multi-recipe persist)"
  else
    bad  "$(basename "$f") does NOT use a per-recipe adopted-recipe-<...>.md filename"
  fi
done

# (g) /research step 2c handles competing same-aspect matches by ALWAYS ASKING (never auto-pick).
#     Anchor to recipe-specific tokens so the generic prior-art word "competing option" can't false-match.
if grep -Fq -- 'competing_not_selected' "$RESEARCH" \
   && grep -Eq -- 'SAME aspect|same aspect' "$RESEARCH" \
   && grep -Fiq -- 'always ask' "$RESEARCH"; then
  pass "research.md handles competing same-aspect matches with ALWAYS ASK (no auto-pick)"
else
  bad  "research.md does NOT make competing same-aspect matches always-ask (auto-pick risk)"
fi

# (h) the gate ITERATES every kind:recipe entry (not a single decision).
if grep -Eq -- 'each `kind:recipe`|every `kind:recipe`|per `kind:recipe`' "$PROTO" "$RESEARCH"; then
  pass "protocol/research iterate every kind:recipe entry (multi-recipe gate)"
else
  bad  "protocol/research do NOT iterate kind:recipe entries (still single-match gate)"
fi

# (i) downstream /implement + /review follow EACH adopted recipe (not just one).
for cmd in implement review; do
  cf="$ROOT/commands/$cmd.md"
  if grep -Eq -- 'for EACH|each .*adopted|each `recipes\[\]`' "$cf"; then
    pass "commands/$cmd.md follows EACH adopted recipe (multi-recipe downstream)"
  else
    bad  "commands/$cmd.md does NOT iterate adopted recipes (only follows one)"
  fi
done

# (j) idempotency RE-ENTERS the gate while ANY matched recipe is deferred (generalised across the set).
if grep -Fq -- 'every' "$RESEARCH" && grep -Fq -- 'deferred' "$RESEARCH" && grep -Eq -- 're-enter|re-surface' "$RESEARCH"; then
  pass "research.md idempotency re-enters while any matched recipe is deferred (set-generalised)"
else
  bad  "research.md idempotency not generalised across the recipe set (deferred-swallow risk)"
fi

# ── v5.13.0 latent-seam closes: collision-safe filename (-<sha8>) + per-entry re-entry ──

# (k) the persisted filename carries the recipe_sha slice (<sha8>) so two recipe_names that sanitise to
#     the same <safe_name> never overwrite each other. Format declared in the protocol + /research, and
#     the §5.13 JSON example shows a sha-suffixed body_path.
for f in "$PROTO" "$RESEARCH"; do
  if grep -Fq -- 'adopted-recipe-<safe_name>-<sha8>' "$f" && grep -Fq -- 'recipe_sha' "$f"; then
    pass "$(basename "$f") uses the collision-safe filename adopted-recipe-<safe_name>-<sha8>.md"
  else
    bad  "$(basename "$f") filename lacks the -<sha8> slice (silent body-overwrite risk on safe_name collision)"
  fi
done
if printf '%s' "$SEC513" | grep -Eq -- '"body_path"[^"]*"[^"]*adopted-recipe-[a-z0-9-]+-[0-9a-f]{8}\.md"'; then
  pass "gate-audit-schema §5.13 example body_path carries the -<sha8> slice"
else
  bad  "gate-audit-schema §5.13 example body_path is not sha-suffixed (filename format drifted)"
fi

# (l) re-entry is PER-ENTRY: an already-terminal recipe is carried forward unchanged (decision + an
#     already-run verifier preserved); only deferred/new entries are re-prompted. Guards the re-prompt
#     wart + the verifier-reset data-loss seam.
for f in "$PROTO" "$RESEARCH"; do
  if grep -Fiq -- 'per-entry' "$f" && grep -Eiq -- 'carry|preserv' "$f" && grep -Fq -- 'verifier' "$f"; then
    pass "$(basename "$f") re-entry is per-entry — carries terminal decisions + verifier forward"
  else
    bad  "$(basename "$f") re-entry not per-entry (re-prompts terminal recipes / resets verifier)"
  fi
done

# ── v5.13.0 paper-test hardening: verifier→overall_verdict, <sha8> hex-validation, untrusted body ──

# (m) FIX 1: /review folds the agentic verifier into gates_run[] so it reaches overall_verdict
#     (the sidecar alone must NOT gate). A verifier fail must flow to overall_verdict fail.
if grep -Fq -- 'agentic-verifier' "$REVIEW" && grep -Fq -- 'gates_run[]' "$REVIEW" \
   && grep -Fq -- 'overall_verdict' "$REVIEW"; then
  pass "review.md folds agentic-verifier into gates_run[] → overall_verdict (not sidecar-only)"
else
  bad  "review.md verifier is sidecar-only — a verifier fail would leave /review green (false PASS)"
fi
# the schema's review payload name enum carries agentic-verifier (so the audit shape stays valid).
if grep -Fq -- 'agentic-verifier' "$SCHEMA"; then
  pass "gate-audit-schema review gates_run[].name enum includes agentic-verifier"
else
  bad  "gate-audit-schema review name enum missing agentic-verifier (audit shape invalid)"
fi

# (n) FIX 2: <sha8> is hex-validated (^[0-9a-f]{8}$) everywhere the filename rule is stated, and a
#     non-hex/attacker-seeded sha is halt-and-escalated (path-traversal guard), with the F5 empty-safe_name
#     fallback (adopted-recipe-<sha8>.md). recipe_sha is untrusted index-line data.
for f in "$PROTO" "$RESEARCH" "$IMPLEMENT" "$REVIEW"; do
  if grep -Fq -- '^[0-9a-f]{8}$' "$f"; then
    pass "$(basename "$f") hex-validates <sha8> (^[0-9a-f]{8}$ — path-traversal guard)"
  else
    bad  "$(basename "$f") does NOT hex-validate <sha8> (untrusted recipe_sha → path escape)"
  fi
done
if grep -Fq -- '^[0-9a-f]{8}$' "$SCHEMA" \
   && grep -Fq -- 'adopted-recipe-<sha8>.md' "$PROTO" && grep -Fq -- 'adopted-recipe-<sha8>.md' "$RESEARCH"; then
  pass "schema notes the hex rule + protocol/research state the F5 empty-safe_name fallback"
else
  bad  "missing schema hex note or the F5 (adopted-recipe-<sha8>.md) fallback"
fi

# (o) FIX 4: untrusted-body caution restated in /implement + /review; coverage-map invariant 8 updated.
for cmd in implement review; do
  cf="$ROOT/commands/$cmd.md"
  if grep -Fiq -- 'untrusted upstream data' "$cf" && grep -Fq -- 'never `eval`/shell-parse' "$cf"; then
    pass "commands/$cmd.md restates the untrusted-body caution (follow as method, never eval)"
  else
    bad  "commands/$cmd.md missing the untrusted-body caution"
  fi
done
if grep -Fq -- 'adopted-recipe-<safe_name>-<sha8>.md' "$COVERAGE" && ! grep -Eq -- 'adopted-recipe\.md`' "$COVERAGE"; then
  pass "coverage-map-contract invariant 8 updated to the per-recipe sha-suffixed filename (stale doc fixed)"
else
  bad  "coverage-map-contract still references the stale single adopted-recipe.md filename"
fi

echo
[ "$fail" -eq 0 ] && { echo "agentic-recipe-enforcement-spec: ALL PASS"; exit 0; } || { echo "agentic-recipe-enforcement-spec: FAILURES"; exit 1; }
