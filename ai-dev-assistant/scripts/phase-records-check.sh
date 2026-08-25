#!/usr/bin/env bash
# phase-records-check.sh — did this phase produce the records it owes?
#
# THE FAILURE THIS EXISTS FOR. A session reads the protocol, understands it, and then does the work
# itself instead of invoking the skill the protocol names. The terminal output is excellent — often
# better than the skill would have produced, because the session has the whole task in context. What
# is missing is everything the skill was going to WRITE. Observed twice in two phases of one task:
# the recipe sweep was hand-rolled and recorded six keys that resolve to nothing, and step 5a's
# internal prior-art search was hand-rolled as a `git log`, which found a genuinely task-reframing
# commit and left no `_internal-prior-art.json`, no `research/` pointer, no disposition record, and
# never opened the code-map conversation that lives inside the skill.
#
# `/review` already fail-closes on several of these records being absent. That is the right posture
# and it is too late: the failure surfaces at Phase 4, about work done in Phase 1, with the context
# that would make it cheap to fix long gone. This check moves the same question to the end of the
# phase that owes the answer.
#
# It reports which records are missing AND WHO WAS SUPPOSED TO WRITE EACH ONE, because "missing
# _internal-prior-art.json" is a puzzle and "step 5a's internal-prior-art-finder skill did not run"
# is an instruction.
#
# Usage: phase-records-check.sh <task_folder> [--phase research]
#
# Emits ONE JSON object, exit 0 always:
#   { schema_version, phase, task_folder, verdict, missing_required,
#     records: [{name, status, requirement, producer, step}], warnings[] }
#
# verdict: complete | incomplete | unknown
#   unknown — the phase has no record contract encoded here. Never reported as complete: a phase
#             this script does not know about has not been checked, and saying otherwise would make
#             the check itself the kind of confident wrong answer it exists to catch.
#
# Research was the only phase with a contract until v5.30.1, so this check caught a skipped gate
# once and then went quiet. A live design phase ran it and got `unknown` — honestly reported, and
# useless: the one guardrail that had already found a real gap could not look at the phase that
# came next, or at implementation after it. An honest `unknown` on every phase but one is a check
# that has stopped checking. Design and implement now carry contracts too.
#
# Those two contracts were then derived by reading the command bodies rather than by watching a
# run, and the next live phase found what that missed. `/implement` calls the mechanism challenge
# "the unskippable catch" and writes its record either way, and the contract did not list the
# record at all, so a phase that skipped an unskippable gate still read `complete`. The design
# entry had it as conditional when its step is equally unconditional. Both are required now.
#
# `_pre-analysis.json` was listed for both and belongs to neither: the epic check those phases run
# branches and stays silent, and nothing in either command writes that record. A contract answers
# what THIS phase owes, so a record it never produces has no place in it.
set -uo pipefail

TASK_DIR="${1:-}"; PHASE="research"
shift 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --phase) PHASE="${2:-research}"; shift 2 || shift ;;
    *)       shift ;;
  esac
done

WARNINGS='[]'
add_warn(){ WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS" 2>/dev/null || printf '[]'); }

if ! command -v jq >/dev/null 2>&1; then
  printf '{"schema_version":"1.0","verdict":"unknown","warnings":["jq_missing"],"records":[]}\n'; exit 0
fi

emit(){ # emit <verdict> <records_json>
  jq -n --arg v "$1" --argjson r "$2" --arg p "$PHASE" --arg t "$TASK_DIR" --argjson w "$WARNINGS" \
    '{schema_version:"1.0", phase:$p, task_folder:(if $t=="" then null else $t end),
      verdict:$v,
      missing_required:([$r[]|select(.status=="missing" and .requirement=="required")]|length),
      records:$r, warnings:$w}'
  exit 0
}

if [ -z "$TASK_DIR" ] || [ ! -d "$TASK_DIR" ]; then
  add_warn "task_folder_not_a_directory"
  emit unknown '[]'
fi

# The contract, one line per record: <name>|<required|conditional>|<producer>|<step>
# `conditional` records are reported for visibility and never counted against the verdict — a
# maintainer-mode offer that did not fire is not a missing record.
case "$PHASE" in
  research) CONTRACT='_pre-analysis.json|required|analysis-agent (description mode), written via gate-audit-write.sh|step 1
coverage-map.json|required|the recipe-loader skill|step 2c
_agentic-recipe.json|required|step 2c, written via gate-audit-write.sh|step 2c
_mechanism-challenge.json|required|the mechanism-challenge cascade, written via gate-audit-write.sh|step 2c
_dev-guides-load.json|required|dev-guides-detect.sh plus the guides-matcher agent|step 3
_playbook-load.json|required|playbook-load-deterministic.sh|step 4
_internal-prior-art.json|required|the internal-prior-art-finder skill|step 5a
research.md|required|the phase itself|step 6
_recipe-load.json|conditional|the process-recipe-loader skill, when frameworks are defined|step 6
_coverage-mapping.json|conditional|the coverage-mapping gate|step 6
_create-on-miss.json|conditional|the maintainer create-on-miss offer, on a genuine domain miss|step 3
_distill.json|conditional|the distill-agent, when the end-of-phase seam is accepted|end of phase' ;;
  design) CONTRACT='_phase-active.json|required|phase-active-write.sh with the task folder|step 0
_dev-guides-load.json|required|dev-guides-detect.sh plus the guides-matcher agent|step 2
_playbook-load.json|required|playbook-load-deterministic.sh|step 3
architecture.md|required|the architecture-drafter agent|step 5
_recipe-load.json|conditional|the process-recipe-loader skill, when frameworks are defined|step 2
_mechanism-challenge.json|required|the mechanism-challenge refresh, which the design step runs unconditionally|step 4
_create-on-miss.json|conditional|the maintainer create-on-miss offer, on a genuine domain miss|step 2
_distill.json|conditional|the distill-agent, when the end-of-phase seam is accepted|step 11' ;;
  implement) CONTRACT='_phase-active.json|required|phase-active-write.sh with the task folder|step 0
_dev-guides-load.json|required|dev-guides-detect.sh plus the guides-matcher agent|step 3
_playbook-load.json|required|playbook-load-deterministic.sh|step 4
implementation.md|required|the phase itself|step 7
_mechanism-challenge.json|required|the mechanism-challenge backstop, which runs the full challenge when the record is absent|step 6
_recipe-load.json|conditional|the process-recipe-loader skill, when frameworks are defined|step 3
_create-on-miss.json|conditional|the maintainer create-on-miss offer, on a genuine domain miss|step 3
_distill.json|conditional|the distill-agent, when the end-of-phase seam is accepted|end of phase' ;;
  *) add_warn "no_record_contract_for_phase:$PHASE"
     emit unknown '[]' ;;
esac

RECORDS='[]'
MISSING=0
while IFS='|' read -r NAME REQ PRODUCER STEP; do
  [ -z "$NAME" ] && continue
  STATUS="missing"
  if [ -s "$TASK_DIR/$NAME" ]; then
    STATUS="present"
  elif [ -e "$TASK_DIR/$NAME" ]; then
    # An empty file is not a record. It parses as absent everywhere downstream, so calling it
    # present here would hide the problem one layer deeper.
    STATUS="empty"
  fi
  [ "$STATUS" != "present" ] && [ "$REQ" = "required" ] && MISSING=$((MISSING + 1))
  RECORDS=$(jq -c --argjson a "$RECORDS" --arg n "$NAME" --arg s "$STATUS" --arg r "$REQ" \
                  --arg p "$PRODUCER" --arg st "$STEP" \
    -n '$a + [{name:$n, status:$s, requirement:$r, producer:$p, step:$st}]')
done <<< "$CONTRACT"

if [ "$MISSING" -gt 0 ]; then emit incomplete "$RECORDS"; fi
emit complete "$RECORDS"
