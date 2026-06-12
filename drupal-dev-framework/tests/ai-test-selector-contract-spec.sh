#!/usr/bin/env bash
# Contract test for the ai-test-selector agent + its wiring into the
# change-impact dispatcher (tasks: ATC, WO-01 + WO-02).
#
# This is a doc-contract test: it asserts that the agent, schema, dispatch, VR
# command, and audit schema docs carry the required contract clauses. Guards
# against prose regressions that would silently re-break the selection wiring.
#
# Coverage:
#   wo-01 — agent frontmatter (read-only disallowedTools: Edit,Write + model: sonnet),
#            I/O contract, err-toward-inclusion, degraded fallback, schema doc present.
#   wo-02 — dispatch step 6.2a invokes selector for e2e+VR (NOT parity), shows
#            recommendation+selection together in step 6.3, --full-<gate>/
#            --skip-ai-selection override present, e2e --surfaces-json + VR registry
#            pre-filter wired in validate-visual-regression.md step 5, and
#            gate-audit-schema.md documents ai_surface_selection.
#
# Exit: 0 = all clauses present; 1 = a clause is missing / file not found.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."

AGENT="$ROOT/agents/ai-test-selector.md"
SCHEMA="$ROOT/references/ai-test-selector-schema.md"
DISPATCH="$ROOT/references/visual-review/change-impact-dispatch.md"
VR_CMD="$ROOT/commands/validate-visual-regression.md"
AUDIT_SCHEMA="$ROOT/references/gate-audit-schema.md"

fail=0

check_file() {
  if [ ! -f "$1" ]; then
    echo "FAIL: file not found: $1"
    fail=1
    return 1
  fi
  return 0
}

check() { # <description> <file> <grep -E pattern>
  if grep -Eq "$3" "$2"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1  (missing pattern: $3)"
    fail=1
  fi
}

# ── File presence ─────────────────────────────────────────────────────────────
echo "--- file presence ---"
for f in "$AGENT" "$SCHEMA" "$DISPATCH" "$VR_CMD" "$AUDIT_SCHEMA"; do
  check_file "$f"
done

# ── wo-01: Agent frontmatter — read-only ──────────────────────────────────────
echo "--- wo-01: agent frontmatter ---"

check "agent disallowedTools includes Edit and Write" "$AGENT" \
  'disallowedTools:.*Edit.*Write|disallowedTools:.*Write.*Edit'

check "agent model is sonnet" "$AGENT" \
  '^model: sonnet'

check "agent tools list present (Read/Grep/Glob/Bash)" "$AGENT" \
  '^tools:.*Read'

# ── wo-01: I/O contract ───────────────────────────────────────────────────────
echo "--- wo-01: I/O contract ---"

check "agent INPUT documents gate field" "$AGENT" \
  '"gate"'

check "agent INPUT documents diff_files field" "$AGENT" \
  '"diff_files"'

check "agent INPUT documents registry_path field" "$AGENT" \
  '"registry_path"'

check "agent INPUT documents spec_plans_dir field" "$AGENT" \
  '"spec_plans_dir"'

check "agent OUTPUT documents selected_surfaces" "$AGENT" \
  '"selected_surfaces"'

check "agent OUTPUT documents skipped_surfaces" "$AGENT" \
  '"skipped_surfaces"'

check "agent OUTPUT documents degraded field" "$AGENT" \
  '"degraded"'

check "agent OUTPUT documents selection_model" "$AGENT" \
  '"selection_model"'

# ── wo-01: Err-toward-inclusion ───────────────────────────────────────────────
echo "--- wo-01: err-toward-inclusion ---"

check "agent documents err-toward-inclusion rule" "$AGENT" \
  'ERR TOWARD INCLUSION|[Ee]rr.*[Tt]oward.*[Ii]nclusion'

check "agent: when uncertain SELECT the surface" "$AGENT" \
  '[Uu]ncertain.*SELECT|SELECT.*uncertain|uncertain.*select'

# ── wo-01: Degraded fallback ──────────────────────────────────────────────────
echo "--- wo-01: degraded fallback ---"

check "agent documents DEGRADED fallback" "$AGENT" \
  'DEGRADED|[Dd]egraded [Ff]allback'

check "agent: degraded sets selected_surfaces := candidate_surfaces" "$AGENT" \
  'selected_surfaces.*:=.*candidate_surfaces|selected_surfaces.*candidate_surfaces'

check "agent: degraded skipped_surfaces must be empty" "$AGENT" \
  'skipped_surfaces.*\[\]|degraded.*skipped_surfaces'

# ── wo-01: Schema doc documents output ────────────────────────────────────────
echo "--- wo-01: schema doc ---"

check "schema doc documents selected_surfaces field" "$SCHEMA" \
  'selected_surfaces'

check "schema doc has Degraded Semantics section" "$SCHEMA" \
  '[Dd]egraded [Ss]emantics'

check "schema doc documents skipped_surfaces reason contract" "$SCHEMA" \
  '[Rr]eason [Cc]ontract|skipped_surfaces.*reason'

check "schema doc: visual_parity out of scope" "$SCHEMA" \
  'visual_parity.*out of scope|visual_parity.*[Nn]on-[Gg]oal'

# ── wo-02: Dispatch — step 6.2a present ──────────────────────────────────────
echo "--- wo-02: dispatch step 6.2a ---"

check "dispatch has step 6.2a" "$DISPATCH" \
  '6\.2a|Step 6\.2a'

check "dispatch step 6.2a invokes ai-test-selector" "$DISPATCH" \
  'ai-test-selector'

check "dispatch invokes selector via Task tool" "$DISPATCH" \
  '[Tt]ask.*tool|Task tool'

# ── wo-02: e2e + VR selected; parity excluded ────────────────────────────────
echo "--- wo-02: gate scope (e2e+VR only, parity excluded) ---"

check "dispatch selector invoked for e2e gate" "$DISPATCH" \
  '"e2e".*selector|selector.*"e2e"|e2e.*ai_selection|ai_selection.*e2e'

check "dispatch selector invoked for visual_regression gate" "$DISPATCH" \
  'visual_regression.*select|select.*visual_regression|ai_selection.*visual_regression'

check "dispatch explicitly excludes visual_parity from AI selection" "$DISPATCH" \
  'visual_parity.*excluded.*AI|visual_parity.*reference-driven.*not.*diff-driven|NOT.*visual_parity.*select|visual_parity.*[Ee]xcluded'

# ── wo-02: Recommendation + selection shown together in step 6.3 ─────────────
echo "--- wo-02: step 6.3 shows recommendation+selection together ---"

check "dispatch step 6.3 shows AI-selected surfaces" "$DISPATCH" \
  'AI-selected|[Aa][Ii].*selected.*surface|selected.*candidate'

check "dispatch step 6.3 shows skipped surfaces with reasons (never silent)" "$DISPATCH" \
  '[Ss]kipped.*reason|reason.*[Ss]kipped|skipped surfaces with their reasons'

# ── wo-02: --full-<gate> / --skip-ai-selection override ──────────────────────
echo "--- wo-02: --full-<gate>/--skip-ai-selection override ---"

check "dispatch documents --full-e2e or --full-<gate> override" "$DISPATCH" \
  '\-\-full-e2e|\-\-full-visual-regression|\-\-full-<gate>'

check "dispatch documents --skip-ai-selection override" "$DISPATCH" \
  '\-\-skip-ai-selection'

check "dispatch: override runs full candidate set (conservative inclusion)" "$DISPATCH" \
  'full candidate set|conservative inclusion|full.*candidate'

# ── wo-02: e2e --surfaces-json consumption ────────────────────────────────────
echo "--- wo-02: e2e --surfaces-json ---"

check "dispatch wires e2e --surfaces-json" "$DISPATCH" \
  '\-\-surfaces-json'

check "dispatch: empty e2e selection is a clean skip (not failure)" "$DISPATCH" \
  'no affected e2e|empty.*skip|clean skip|empty.*selection.*skip'

# ── wo-02: VR registry pre-filter in validate-visual-regression.md step 5 ────
echo "--- wo-02: VR registry pre-filter ---"

check "VR command step 5 documents AI selection pre-filter" "$VR_CMD" \
  '[Aa][Ii].*select.*pre-filter|pre-filter|selected_surfaces'

check "VR command: dispatcher passes selected_surfaces to step 5" "$VR_CMD" \
  'selected_surfaces'

check "VR command: empty selection emits skipped verdict" "$VR_CMD" \
  'no affected visual_regression|selected_surfaces.*empty|empty.*skipped'

check "VR command dispatch-ready marker present (not altered)" "$VR_CMD" \
  'visual-review:dispatch-ready'

# ── wo-02: No --surfaces flag added to visual-regression-gate.sh ─────────────
echo "--- wo-02: visual-regression-gate.sh not modified ---"

check "VR command invokes visual-regression-gate.sh without --surfaces flag" "$VR_CMD" \
  'visual-regression-gate\.sh'

# ── wo-02: gate-audit-schema.md documents ai_surface_selection ────────────────
echo "--- wo-02: gate-audit-schema ---"

check "audit schema documents ai_surface_selection key" "$AUDIT_SCHEMA" \
  'ai_surface_selection'

check "audit schema ai_surface_selection documents selected_surfaces field" "$AUDIT_SCHEMA" \
  'selected_surfaces'

check "audit schema ai_surface_selection documents degraded field" "$AUDIT_SCHEMA" \
  'degraded'

check "audit schema ai_surface_selection absent when selector did not run" "$AUDIT_SCHEMA" \
  '[Aa]bsent.*selector|selector.*did not run|skip-ai-selection.*absent|[Aa]bsent.*dispatch'

check "audit schema visual_parity excluded from ai_surface_selection" "$AUDIT_SCHEMA" \
  'visual_parity.*excluded.*AI|visual_parity.*reference-driven'

# ── wo-02: headless/CI selector still runs (read-only) ───────────────────────
echo "--- wo-02: headless/CI selector runs ---"

check "dispatch: selector runs under --headless/--ci (read-only)" "$DISPATCH" \
  '[Hh]eadless.*selector.*run|selector.*still runs|[Hh]eadless.*read-only|headless.*selector'

if [ "$fail" -eq 0 ]; then
  echo ""
  echo "ALL PASS — ai-test-selector wo-01 + wo-02 contract present"
  exit 0
else
  echo ""
  echo "CONTRACT FAILED — one or more clauses missing"
  exit 1
fi
