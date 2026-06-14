#!/usr/bin/env bash
# recipe-declarations-audit.sh — report which gate declarations a process-recipe
# body carries for a given phase, and which expected ones are absent.
#
# This is the OBSERVABILITY counterpart to the fail-open gate posture: the gates
# degrade to the framework-neutral floor when a declaration is absent (deliberate
# agnostic default), but that degradation is otherwise silent. This kernel makes
# it visible — a recipe author (or CI in the dev-guides repo) runs it against a
# recipe body and sees, per phase, present vs absent declarations. It is the
# linter that answers "is my recipe complete for the ai-dev-assistant gates?".
#
# Authoritative declaration set: references/recipe-interface.md. Keep the per-phase
# table below in sync with that contract (tests/recipe-interface-spec.sh pins the
# tokens; tests/recipe-declarations-audit-spec.sh pins this kernel's behavior).
#
# Usage:
#   recipe-declarations-audit.sh --body <recipe.md> --phase <phase> [--framework <fw>]
#
#   --phase ∈ {research, design, implement, review, e2e-setup, visual-regression}
#
# Output: a single JSON object to stdout. INFORMATIONAL — exit 0 even when
# recommended declarations are absent (absence is a valid agnostic-floor choice,
# not a failure). Exit 2 only on a usage/IO error that prevents emitting JSON.
#
#   {
#     "schema_version": "1.0",
#     "phase": "review",
#     "framework": "drupal",                      # null if --framework omitted
#     "declarations": [
#       {"token": "## Change-impact globs", "kind": "heading",
#        "recommended": true, "status": "absent"},
#       {"token": "code_quality_extensions", "kind": "field",
#        "recommended": false, "status": "present"}
#     ],
#     "summary": {"expected": 2, "present": 1, "absent_recommended": 1}
#   }
#
# A phase with no gate-parsed declarations (research/design carry the body verbatim
# to an agent, nothing is grepped) returns declarations:[] with a note.

set -uo pipefail

BODY="" ; PHASE="" ; FRAMEWORK=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body)      BODY="${2:-}"; shift 2 ;;
    --phase)     PHASE="${2:-}"; shift 2 ;;
    --framework) FRAMEWORK="${2:-}"; shift 2 ;;
    *) echo "recipe-declarations-audit: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$BODY" ] || [ -z "$PHASE" ]; then
  echo "Usage: recipe-declarations-audit.sh --body <recipe.md> --phase <phase> [--framework <fw>]" >&2
  exit 2
fi
if [ ! -f "$BODY" ]; then
  echo "recipe-declarations-audit: body not found: $BODY" >&2
  exit 2
fi
case "$PHASE" in
  research|design|implement|review|e2e-setup|visual-regression) ;;
  *) echo "recipe-declarations-audit: unknown phase '$PHASE'" >&2; exit 2 ;;
esac

# Per-phase expected declarations. Each line: <token>\t<kind>\t<recommended:0|1>.
# Mirrors the "which recipe carries which" table in recipe-interface.md.
expected_for_phase() {
  case "$1" in
    review)
      # code-quality is one declaration; the gate greps the field, so check it.
      printf '%s\t%s\t%s\n' 'code_quality_extensions' 'field'   '0'
      printf '%s\t%s\t%s\n' '## Change-impact globs'  'heading' '1'
      ;;
    visual-regression)
      printf '%s\t%s\t%s\n' '## Screenshot capture'  'heading' '0'
      printf '%s\t%s\t%s\n' '## Change-impact globs'  'heading' '1'
      ;;
    implement|design)
      printf '%s\t%s\t%s\n' '## Routing hints' 'heading' '0'
      ;;
    e2e-setup)
      printf '%s\t%s\t%s\n' 'preflight_command' 'field' '1'
      ;;
    research)
      : # no gate-parsed declarations; body is followed verbatim by an agent
      ;;
    *)
      echo "recipe-declarations-audit: unknown phase '$1'" >&2
      exit 2
      ;;
  esac
}

DECL_JSON='[]'
present=0 ; expected=0 ; absent_recommended=0

while IFS=$'\t' read -r token kind recommended; do
  [ -z "$token" ] && continue
  expected=$((expected + 1))
  if grep -Fq -- "$token" "$BODY"; then
    status="present"; present=$((present + 1))
  else
    status="absent"
    [ "$recommended" = "1" ] && absent_recommended=$((absent_recommended + 1))
  fi
  rec_bool=$([ "$recommended" = "1" ] && echo true || echo false)
  DECL_JSON=$(jq -c \
    --arg t "$token" --arg k "$kind" --argjson r "$rec_bool" --arg s "$status" \
    '. + [{token:$t, kind:$k, recommended:$r, status:$s}]' <<<"$DECL_JSON")
done < <(expected_for_phase "$PHASE")

fw_json=$([ -n "$FRAMEWORK" ] && jq -nc --arg f "$FRAMEWORK" '$f' || echo null)

jq -nc \
  --arg phase "$PHASE" \
  --argjson framework "$fw_json" \
  --argjson decls "$DECL_JSON" \
  --argjson expected "$expected" \
  --argjson present "$present" \
  --argjson absent_recommended "$absent_recommended" \
  '{schema_version:"1.0", phase:$phase, framework:$framework,
    declarations:$decls,
    summary:{expected:$expected, present:$present, absent_recommended:$absent_recommended}}'
