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
#     records: [{name, status, requirement, producer, step, written_by_phase}], warnings[] }
#
# status: present | carried | stale | unattributed | empty | missing
#   present      — the record names this phase
#   carried      — an earlier phase's record that this contract allows to be reused
#   stale        — an earlier phase's record where reuse is not allowed; counts as missing
#   unattributed — the record names no phase, so it cannot be tied to this one; counts as missing
#                  when required, because a record that cannot say who wrote it has not answered
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
# Review was left without a contract when design and implement got theirs, so the last phase in
# the lifecycle — the one that decides whether the work ships — answered `unknown` about its own
# records for a whole live round. Its two assertion gates read records an earlier phase wrote
# rather than writing them, which is what `carryable` is for: the mechanism challenge and the
# internal prior-art search are required to be present and are not required to be review's own.
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
      missing_required:([$r[]|select(.requirement=="required")
                            |select(.status|IN("present","carried")|not)]|length),
      records:$r, warnings:$w}'
  exit 0
}

if [ -z "$TASK_DIR" ] || [ ! -d "$TASK_DIR" ]; then
  add_warn "task_folder_not_a_directory"
  emit unknown '[]'
fi

# The contract, one line per record:
#   <name>|<required|conditional>|<producer>|<step>|<attribution>
#
# `attribution` says how a record is tied to the phase being checked:
#
#   (empty)   the record must name this phase. The default, and right for anything a phase
#             re-fires each time it runs.
#   carryable an EARLIER phase's record legitimately satisfies this one. Rare. The mechanism
#             challenge is: its backstop is specified to reuse an existing record when the
#             mechanisms hash still matches, so an earlier stamp is a correct outcome there and
#             a stale artifact anywhere else. Review's two assertion gates are the same shape —
#             they read what research wrote rather than writing their own.
#   implicit  only one phase ever writes this record, so its name identifies it the way
#             architecture.md identifies the design phase. `_review.json` cannot be anyone's but
#             review's. Demanding a phase field these payloads never carried would be inventing
#             a requirement rather than checking one.
# `conditional` records are reported for visibility and never counted against the verdict — a
# maintainer-mode offer that did not fire is not a missing record.
case "$PHASE" in
  research) CONTRACT='_pre-analysis.json|required|analysis-agent (description mode), written via gate-audit-write.sh|step 1|implicit
coverage-map.json|required|the recipe-loader skill|step 2c|implicit
_agentic-recipe.json|required|step 2c, written via gate-audit-write.sh|step 2c|implicit
_mechanism-challenge.json|required|the mechanism-challenge cascade, written via gate-audit-write.sh|step 2c|carryable
_dev-guides-load.json|required|dev-guides-detect.sh plus the guides-matcher agent|step 3
_playbook-load.json|required|playbook-load-deterministic.sh|step 4
_internal-prior-art.json|required|the internal-prior-art-finder skill|step 5a|implicit
research.md|required|the phase itself|step 6
_recipe-load.json|conditional|the process-recipe-loader skill, when frameworks are defined|step 6
_coverage-mapping.json|conditional|the coverage-mapping gate|step 6|implicit
_create-on-miss.json|conditional|the maintainer create-on-miss offer, on a genuine domain miss|step 3|carryable
_distill.json|conditional|the distill-agent, when the end-of-phase seam is accepted|end of phase' ;;
  design) CONTRACT='_phase-active.json|required|phase-active-write.sh with the task folder|step 0
_dev-guides-load.json|required|dev-guides-detect.sh plus the guides-matcher agent|step 2
_playbook-load.json|required|playbook-load-deterministic.sh|step 3
architecture.md|required|the architecture-drafter agent|step 5
_recipe-load.json|conditional|the process-recipe-loader skill, when frameworks are defined|step 2
_mechanism-challenge.json|required|the mechanism-challenge refresh, which the design step runs unconditionally|step 4|carryable
_create-on-miss.json|conditional|the maintainer create-on-miss offer, on a genuine domain miss|step 2|carryable
_distill.json|conditional|the distill-agent, when the end-of-phase seam is accepted|step 11' ;;
  implement) CONTRACT='_phase-active.json|required|phase-active-write.sh with the task folder|step 0
_dev-guides-load.json|required|dev-guides-detect.sh plus the guides-matcher agent|step 3
_playbook-load.json|required|playbook-load-deterministic.sh|step 4
implementation.md|required|the phase itself|step 7
_mechanism-challenge.json|required|the mechanism-challenge backstop, which runs the full challenge when the record is absent|step 6|carryable
_recipe-load.json|conditional|the process-recipe-loader skill, when frameworks are defined|step 3
_preconditions.json|conditional|the preconditions gate, when a framework implement recipe resolved|step 6b
_create-on-miss.json|conditional|the maintainer create-on-miss offer, on a genuine domain miss|step 3|carryable
_distill.json|conditional|the distill-agent, when the end-of-phase seam is accepted|end of phase' ;;
  review) CONTRACT='_phase-active.json|required|phase-active-write.sh with the task folder|step 0
_review.json|required|the review phase, written via gate-audit-write.sh|step 8|implicit
_spec.json|required|the spec-axis review gate|step 5.0d|implicit
_recipe-load.json|required|the process-recipe-loader skill|step 5
_mechanism-challenge.json|required|an earlier phase; review asserts the record rather than writing it|step 5.0c|carryable
_internal-prior-art.json|required|an earlier phase; review asserts the search ran and was recorded|step 5.0e|carryable
_agentic-recipe.json|conditional|the adopted-recipe verifier, when the task adopted one|step 5.0b|carryable
PR_BODY.md|conditional|step 11, written only when the verdict is green and neither --no-pr-body nor --dry-run is set|step 11' ;;
  *) add_warn "no_record_contract_for_phase:$PHASE"
     emit unknown '[]' ;;
esac

RECORDS='[]'
MISSING=0
# Presence was the whole test until v5.30.3, and presence is not the question this file asks.
# Every JSON record here is overwrite-on-fire and none is deleted between phases, so a file
# written three phases ago satisfied the contract of a phase that never ran the step. Observed
# live: `_mechanism-challenge.json` stamped `phase: design` counted as implementation's copy of
# the gate that command calls unskippable, and `_distill.json` from research counted for both
# later phases. The check could not tell a phase that did the work from a phase that inherited
# the file, which is the same failure it exists to catch one level up.
#
# So each record is attributed. A record naming this phase is `present`. A record naming another
# phase is `carried` where the contract allows reuse and `stale` where it does not. A record
# carrying no phase at all is `unattributed`: it may well be this phase's and nothing on disk
# says so, and for a required record that is not good enough.
record_phase() { # record_phase <file> -> the phase it names, or empty
  jq -r '(.gate_specific.phase // .phase // empty)' "$1" 2>/dev/null | head -1
}

while IFS='|' read -r NAME REQ PRODUCER STEP CARRY; do
  [ -z "$NAME" ] && continue
  STATUS="missing"
  WROTE=""
  if [ -s "$TASK_DIR/$NAME" ]; then
    case "$NAME" in
      *.json)
        WROTE=$(record_phase "$TASK_DIR/$NAME")
        if [ "$CARRY" = "implicit" ]; then
          # Only this phase writes it, so the filename is the attribution.
          STATUS="present"
        elif [ "$WROTE" = "$PHASE" ] && [ -n "$WROTE" ]; then
          STATUS="present"
        elif [ "$CARRY" = "carryable" ]; then
          # An earlier phase's copy satisfies this entry, so an unstamped one does too: the
          # contract already accepts a record this phase did not write.
          STATUS="carried"
        elif [ -z "$WROTE" ]; then
          STATUS="unattributed"
        else
          STATUS="stale"
        fi ;;
      # A phase artifact is named for its phase — architecture.md is the design phase's by
      # definition — so there is nothing to attribute and nothing to get wrong.
      *) STATUS="present" ;;
    esac
  elif [ -e "$TASK_DIR/$NAME" ]; then
    # An empty file is not a record. It parses as absent everywhere downstream, so calling it
    # present here would hide the problem one layer deeper.
    STATUS="empty"
  fi
  case "$STATUS" in
    present|carried) ;;
    *) [ "$REQ" = "required" ] && MISSING=$((MISSING + 1)) ;;
  esac
  RECORDS=$(jq -c --argjson a "$RECORDS" --arg n "$NAME" --arg s "$STATUS" --arg r "$REQ" \
                  --arg p "$PRODUCER" --arg st "$STEP" --arg w "$WROTE" \
    -n '$a + [{name:$n, status:$s, requirement:$r, producer:$p, step:$st,
               written_by_phase: (if $w == "" then null else $w end)}]')
done <<< "$CONTRACT"

# Every JSON record here is overwrite-on-fire. Auditing a phase after a later phase has run
# therefore finds that phase's records replaced, not absent, and the verdict has to be readable
# as that rather than as work never done.
STALE_LATER=$(printf '%s' "$RECORDS" | jq -r '[.[]|select(.status=="stale" and .requirement=="required")]|length')
if [ "${STALE_LATER:-0}" -gt 0 ]; then
  add_warn "records_overwritten_by_a_later_phase"
fi

if [ "$MISSING" -gt 0 ]; then emit incomplete "$RECORDS"; fi
emit complete "$RECORDS"
