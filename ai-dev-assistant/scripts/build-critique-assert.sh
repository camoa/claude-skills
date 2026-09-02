#!/usr/bin/env bash
# build-critique-assert.sh — was this task's build ever challenged by something other than
# the context that built it?
#
# THE DEFECT THIS EXISTS FOR. v5.33.0 added a build-critique rung to `/implement` and three
# things looked like they enforced it. None could fail. `phase-records-check.sh` carried a
# `_build-critique.json` row marked `conditional`, and that script counts conditional rows
# for visibility only, so a phase that skipped the rung entirely still returned
# `{"verdict":"complete","missing_required":0}`. The condition the row named — "when the
# build ran in-session rather than through /run-work-orders" — was prose, and nothing read
# it, even though the discriminator sits on disk. And no downstream command named the record
# at all, so a record saying `verdict: "critical"` had zero effect on whether the task
# shipped. The rung was real; its enforcement was a description of enforcement.
#
# This script is the part that can fail. It answers one question from disk — was the build
# challenged, and did the challenge come back clean — and it answers it for BOTH build paths,
# because a task reaches `/review` by either:
#
#   in-session   `/implement` built it and owes `<task>/_build-critique.json`
#   work-orders  `/run-work-orders` built it and owes `<task>/work-orders/wo-NN._critique.json`
#                per work-order, and legitimately has no `_build-critique.json`
#
# A build with NEITHER record was not challenged. That is the failure, not a skip, and it is
# the one case a "could not tell" reading would wave through — which is exactly how the gap
# above stayed open. There is deliberately no path here from "no evidence" to `pass`.
#
# Usage: build-critique-assert.sh <task_folder> [--change-set-empty] [--change-set-file <path>]
#
#   --change-set-empty  the caller resolved an empty change set (`/review` step 4's
#                       `empty_reason: no_changes_anywhere`). Only consulted when there is no
#                       record at all: nothing changed, so there was nothing to critique.
#   --change-set-file   the JSON `review-change-set.sh` emitted at `/review` step 4. Required on
#                       the in-session path (v5.35.5+), where it answers the question no check
#                       here asked before: is this record about the code being reviewed? The
#                       caller passes its own resolved change set rather than this script
#                       re-deriving one, so the gate cannot judge a change set the reviewer is
#                       not looking at.
#
# Emits ONE JSON object on stdout:
#   { schema_version, task_folder, build_path, verdict, unresolved, bypass_reason,
#     evidence{...}, messages[] }
#
# build_path: in-session | work-orders | none
# verdict:    pass | fail | bypassed | skipped
#
# Exit codes:
#   0 — pass, skipped (benign), or bypassed (an override the operator recorded)
#   1 — fail, including every unresolved state (fail-closed)
#   2 — usage: no task folder, or not a directory
set -uo pipefail

# shellcheck source=./accept-verdict.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/accept-verdict.sh"

TASK_DIR="${1:-}"
CHANGE_SET_EMPTY=0
CHANGE_SET_FILE=""
shift 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --change-set-empty) CHANGE_SET_EMPTY=1 ;;
    --change-set-file) shift; CHANGE_SET_FILE="${1:-}" ;;
    *) ;;
  esac
  shift
done

MESSAGES='[]'
add_msg() { MESSAGES=$(jq -c --arg m "$1" '. + [$m]' <<<"$MESSAGES" 2>/dev/null || printf '[]'); }

EVIDENCE='{}'
set_ev() { EVIDENCE=$(jq -c --arg k "$1" --argjson v "$2" '.[$k] = $v' <<<"$EVIDENCE" 2>/dev/null || printf '{}'); }
set_ev_s() { EVIDENCE=$(jq -c --arg k "$1" --arg v "$2" '.[$k] = $v' <<<"$EVIDENCE" 2>/dev/null || printf '{}'); }

emit() { # emit <verdict> <unresolved true|false> <bypass_reason or empty> <exit code>
  jq -n --arg t "$TASK_DIR" --arg p "$BUILD_PATH" --arg v "$1" --argjson u "$2" \
        --arg b "$3" --argjson e "$EVIDENCE" --argjson m "$MESSAGES" \
    '{schema_version:"1.0",
      task_folder:(if $t=="" then null else $t end),
      build_path:$p, verdict:$v, unresolved:$u,
      bypass_reason:(if $b=="" then null else $b end),
      evidence:$e, messages:$m}'
  exit "$4"
}

# has_tdd_problem <problems-json> <problem string>
# Membership in what `tdd_block_problems` returned. A lookup, not a judgement -- the judging is
# already done by the time this is called, and it is done in one place for both build paths.
has_tdd_problem() { jq -e --arg p "$2" 'index($p) != null' <<<"$1" >/dev/null 2>&1; }

# wo_frontmatter_status <work-order.md>
# The `status:` value in the leading `---` frontmatter block, lowercased, or empty when the file
# has no frontmatter or no status line. Deliberately not a YAML parse: this reads one line of a
# file this repo writes itself, and a YAML dependency for that is a dependency the gate would
# then fail closed on when it is missing.
wo_frontmatter_status() {
  awk '
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
    /^---[[:space:]]*$/ { exit }
    /^status:/ {
      sub(/^status:[[:space:]]*/, "")
      gsub(/[[:space:]"]/, "")
      print tolower($0)
      exit
    }
  ' "$1" 2>/dev/null
}

BUILD_PATH="none"

if [ -z "$TASK_DIR" ] || [ ! -d "$TASK_DIR" ]; then
  printf '{"schema_version":"1.0","task_folder":null,"build_path":"none","verdict":"fail","unresolved":true,"bypass_reason":null,"evidence":{},"messages":["task_folder_not_a_directory"]}\n'
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  # A check that could not run has cleared nothing. Reporting that as a pass is the shape of
  # failure this whole file is about.
  printf '{"schema_version":"1.0","build_path":"none","verdict":"fail","unresolved":true,"bypass_reason":null,"evidence":{},"messages":["jq_missing"]}\n'
  exit 1
fi

REC="$TASK_DIR/_build-critique.json"
WO_DIR="$TASK_DIR/work-orders"

# ---------------------------------------------------------------- the in-session record

if [ -e "$REC" ]; then
  BUILD_PATH="in-session"
  if [ ! -s "$REC" ]; then
    # An empty file parses as absent everywhere downstream. Calling it present here would
    # bury the problem one layer deeper.
    set_ev_s build_critique_record "empty"
    add_msg "_build-critique.json is an empty file, so the rung recorded nothing"
    emit fail true "" 1
  fi
  if ! jq -e 'type == "object"' "$REC" >/dev/null 2>&1; then
    set_ev_s build_critique_record "unreadable"
    add_msg "_build-critique.json does not parse as a JSON object"
    emit fail true "" 1
  fi
  set_ev_s build_critique_record "present"

  PAYLOAD=$(jq -c '(.gate_specific // .)' "$REC" 2>/dev/null || printf '{}')
  BYPASS=$(jq -r '(.bypass_reason // .gate_specific.bypass_reason // "") | tostring' "$REC" 2>/dev/null)
  [ "$BYPASS" = "null" ] && BYPASS=""
  RV=$(jq -r '(.verdict // "") | tostring' <<<"$PAYLOAD")
  set_ev_s record_verdict "$RV"

  BLOCKING=$(jq -c '[(.components // [])[] | select(.blocking == true) | (.component // "unnamed")]' <<<"$PAYLOAD")
  set_ev blocking_components "$BLOCKING"
  BLOCKING_N=$(jq -r 'length' <<<"$BLOCKING")

  # Both count fields reach this record in two shapes, and both are honest: a number, or the
  # list of component names whose length IS the number. A live record wrote the list form, and
  # every arithmetic test below then compared a pretty-printed JSON array against an integer --
  # bash printed `integer expression expected` to stderr and evaluated the test FALSE. The
  # casualty was the check directly beneath: a build that declared seven components and
  # critiqued none could not fail it. Same shape as the `rounds`-as-string defect: a check
  # keyed on a field whose type it assumed rather than established.
  #
  # A shape that is neither collapses to -1, which the omission check below already treats as
  # a record that cannot say what it did not look at.
  as_count() { # as_count <json value>
    jq -r 'if type == "number" then .
           elif type == "array" then length
           else -1 end' <<<"${1:-null}" 2>/dev/null || printf '%s' -1
  }
  DECLARED=$(as_count "$(jq -c '(.components_declared // null)' <<<"$PAYLOAD")")
  CRITIQUED=$(as_count "$(jq -c '(.components_critiqued // null)' <<<"$PAYLOAD")")
  UNCRIT_N=$(jq -r '(.uncritiqued // []) | length' <<<"$PAYLOAD")
  set_ev components_declared "$DECLARED"
  set_ev components_critiqued "$CRITIQUED"
  set_ev uncritiqued_count "$UNCRIT_N"

  ALIGN=$(jq -r '(.alignment.verdict // "") | tostring' <<<"$PAYLOAD")
  set_ev_s alignment_verdict "$ALIGN"
  if [ "$ALIGN" = "fail" ]; then
    # Surfaced, never the reason this gate fails. `/review` runs its own Spec axis (step
    # 5.0d) over the current change set, and that is the pass entitled to judge whether the
    # criteria are met NOW. Failing here as well would block on a Phase 3 finding that the
    # rest of Phase 3 may already have fixed, and would report one problem twice.
    add_msg "the Phase 3 alignment axis came back fail; the Spec gate judges it against the current change set"
  fi

  # An operator override is a decision someone made and recorded. Surface it; never absorb it.
  if [ -n "$BYPASS" ]; then
    add_msg "the build-critique record carries a recorded bypass: $BYPASS"
    emit bypassed false "$BYPASS" 0
  fi

  if [ "$RV" = "critical" ] || [ "$BLOCKING_N" -gt 0 ]; then
    add_msg "the build critique blocked: verdict=$RV, $BLOCKING_N blocking component(s)"
    add_msg "address the findings and re-run the rung, or record an explicit bypass_reason in the record"
    emit fail false "" 1
  fi

  if [ "$RV" = "unresolved" ]; then
    add_msg "the build critique came back unresolved, so nothing was cleared"
    emit fail true "" 1
  fi

  if [ "$DECLARED" = "-1" ] || [ "$CRITIQUED" = "-1" ] || ! jq -e 'has("uncritiqued")' <<<"$PAYLOAD" >/dev/null 2>&1; then
    # The counts are what make a partial run legible. A record that critiqued three of seven
    # components and recorded only its three green rows cannot say what it did not look at,
    # and reads exactly like a complete one.
    add_msg "the record omits components_declared, components_critiqued or uncritiqued[], so it cannot say what it did not look at"
    emit fail true "" 1
  fi

  if [ "$RV" = "skipped" ]; then
    SKIP_REASON=$(jq -r '(.reason // .skip_reason // .alignment.reason // "") | tostring' <<<"$PAYLOAD")
    [ "$SKIP_REASON" = "null" ] && SKIP_REASON=""
    if [ -z "$SKIP_REASON" ]; then
      # `skipped` is legitimate for an empty phase range or a task with no architecture file,
      # and each of those carries its reason. Without one it is indistinguishable from "the
      # critics did not run", which the contract says is `unresolved`.
      add_msg "verdict skipped with no reason recorded; the contract allows skipped only for an empty phase range or no architecture file, each carrying its reason"
      emit fail true "" 1
    fi
    add_msg "the rung recorded a legitimate skip: $SKIP_REASON"
    emit skipped false "" 0
  fi

  if [ "$CRITIQUED" -le 0 ] && [ "$DECLARED" -gt 0 ]; then
    add_msg "$DECLARED component(s) declared and none critiqued, so the build was not challenged"
    emit fail true "" 1
  fi

  if [ "$UNCRIT_N" -gt 0 ]; then
    # This line used to say "left uncritiqued with reasons" and nothing checked that a single
    # one carried a reason. The claim was in the message, not in the code -- the same shape as
    # every defect this rung was built to catch. An entry naming a component and saying nothing
    # about why it was skipped is what a build produces when it decided not to critique
    # something and would rather not say so. That decision is legitimate; leaving it unstated
    # is what makes a partial run read like a complete one.
    UNREASONED=$(jq -c \
      '[(.uncritiqued // [])[]
        | if type == "object"
          then select(((.reason // "") | tostring | gsub("^\\s+|\\s+$"; "")) == "")
               | (.component // "unnamed")
          else tostring end]' \
      <<<"$PAYLOAD" 2>/dev/null) || UNREASONED='[]'
    UNREASONED_N=$(jq -r 'length' <<<"$UNREASONED" 2>/dev/null) || UNREASONED_N=0
    if [ "$UNREASONED_N" -gt 0 ]; then
      set_ev unreasoned_uncritiqued "$UNREASONED"
      add_msg "$UNREASONED_N uncritiqued component(s) carry no reason: $UNREASONED"
      add_msg "say why each was not critiqued; an unexplained gap is indistinguishable from one nobody noticed"
      emit fail true "" 1
    fi
    add_msg "$CRITIQUED of $DECLARED component(s) critiqued; $UNCRIT_N left uncritiqued, each with a reason"
  fi

  # ------------------------------------------------------- the RED observation (v5.34.0+)
  #
  # TDD's RED step is an observation: a test run before the implementation existed and seen
  # to fail. Until v5.34.0 the framework asserted it in three prose locations and recorded it
  # in none, so "I wrote the test first" and "I watched it fail" produced byte-identical
  # artifacts. Every gate that looked like it checked did not: the whole-tree TDD gate
  # invoked its runner with no action and scored the usage text, `--changed` mode runs the
  # tests only after the implementation exists so it can prove GREEN-now and never
  # RED-before, and git commit ordering is both unimplemented and structurally blind to this
  # framework's own build shape, where test and implementation land inside one checkpoint
  # range.
  #
  # It rides this record rather than getting a gate of its own because this record already
  # hard-blocks, is already written per component, and already refuses to go from "could not
  # tell" to pass. A second enforcement path where one works is how the previous round's
  # `conditional` row happened.
  if ! jq -e 'has("tdd")' <<<"$PAYLOAD" >/dev/null 2>&1; then
    set_ev_s tdd "absent"
    add_msg "the record carries no tdd block, so it cannot say whether any test was seen to fail before the code existed"
    emit fail true "" 1
  fi
  TDD=$(jq -c '.tdd' <<<"$PAYLOAD")
  RED_N=$(jq -r '(.red_observed // -1)' <<<"$TDD")
  FIRSTRUN_N=$(jq -r '(.passed_first_run // -1)' <<<"$TDD")
  RATIFIED_N=$(jq -r '(.ratified // -1)' <<<"$TDD")
  UNOBS=$(jq -c '(.unobserved // [])' <<<"$TDD")
  UNOBS_N=$(jq -r 'length' <<<"$UNOBS")
  TDD_REASON=$(jq -r '(.reason // "") | tostring' <<<"$TDD")
  [ "$TDD_REASON" = "null" ] && TDD_REASON=""
  set_ev tdd "$TDD"

  # Every blocking decision about this block comes from ONE function, `tdd_block_problems` in
  # accept-verdict.sh, and the delegated branch at the bottom of this file calls the same one.
  # The counts above stay because the NON-blocking lines below say them out loud, and saying a
  # number is not judging it.
  TDD_PROBLEMS=$(tdd_block_problems "$TDD")
  if [ "$TDD_PROBLEMS" = "$JQ_ERR" ]; then
    add_msg "the tdd block could not be read, so it cannot say what was watched failing before the code existed"
    emit fail true "" 1
  fi

  if has_tdd_problem "$TDD_PROBLEMS" "omits red_observed" \
     || has_tdd_problem "$TDD_PROBLEMS" "omits passed_first_run" \
     || has_tdd_problem "$TDD_PROBLEMS" "omits unobserved[]"; then
    add_msg "the tdd block omits red_observed, passed_first_run or unobserved[], so it cannot say what it did not watch"
    emit fail true "" 1
  fi

  # ------------------------------------------------------- the ratified count (v5.46.0+)
  #
  # `red_observed` counts tests run before the implementation existed and seen to fail. That
  # evidence cannot tell a test-first test from one authored while reading the implementation
  # and then run against a reverted tree: both fail at their own assertion for the reason they
  # name, and both were recorded as `observed`. The ordering of RUNS is what the count saw; the
  # ordering of KNOWLEDGE is what separates them.
  #
  # `ratified` is the value that separates them: a test that passed the moment it was written
  # because the code it describes already existed. It is not `passed_first_run`, which means the
  # test is wrong and owes a reason. Ratification is legitimate and common -- characterization
  # and regression tests are written this way on purpose -- so it NEVER blocks and owes no
  # reason. It is required, counted and said aloud, because a count folded into a test-first
  # claim is the state this block exists to end.
  #
  # Absence is fail-closed for the same reason its three siblings are: a record with no
  # `ratified` key reads identically to a phase that ratified nothing, and those are different
  # answers. Measured on one build: 19 assertions across two fixes, 11 red and 8 green on
  # arrival, and nothing anywhere was counting the 8.
  if has_tdd_problem "$TDD_PROBLEMS" "omits ratified"; then
    add_msg "the tdd block omits ratified, so it cannot say how many tests passed on arrival because the code they describe already existed"
    emit fail true "" 1
  fi
  add_msg "$RATIFIED_N test(s) ratified code that already existed, against $RED_N seen to fail first"
  if [ "$RATIFIED_N" -gt 0 ] && [ "$RATIFIED_N" -ge "$RED_N" ]; then
    # Never blocking. Surfaced, because a number nobody sees is the same as no number.
    add_msg "this suite is ratifying more than it is constraining: $RATIFIED_N ratified against $RED_N red"
  fi

  if has_tdd_problem "$TDD_PROBLEMS" "passed_first_run > 0 with no reason recorded"; then
    # Two different things pass on their first run and only one is a defect.
    #
    # A test written test-first that passes immediately is the blocking violation
    # `tdd-companion` names: it is not evidence the behaviour works, it is evidence the test
    # does not test it. A characterization or regression test deliberately written against
    # code that already exists passes on its first run BY DESIGN, and is worth having --
    # locking in behaviour, or reproducing a defect a critic just found.
    #
    # The first release of this block failed both, with no reason path. That would have forced
    # a live build to record a violation for tests that were not violations, which teaches a
    # builder that the honest answer is the expensive one. Say which kind it was; the gate
    # checks that the question was answered, not that the answer is true.
    add_msg "$FIRSTRUN_N test(s) passed on their first run with no reason recorded; say whether the test is wrong or was written deliberately against existing code"
    emit fail true "" 1
  fi
  if [ "$FIRSTRUN_N" -gt 0 ]; then
    add_msg "$FIRSTRUN_N test(s) passed on their first run: $TDD_REASON"
  fi

  if has_tdd_problem "$TDD_PROBLEMS" "unobserved[] non-empty with no reason recorded"; then
    # Recording `unobserved` is legal. Leaving it unexplained is not: with no reason it reads
    # identically to a run where nobody thought about it, which is the state this whole block
    # exists to make visible.
    add_msg "$UNOBS_N criterion/criteria recorded unobserved with no reason; say why nobody watched them fail"
    emit fail true "" 1
  fi
  if [ "$UNOBS_N" -gt 0 ]; then
    add_msg "$UNOBS_N criterion/criteria were built without a watched RED: $TDD_REASON"
  fi
  add_msg "$RED_N criterion/criteria were seen to fail before their implementation existed"

  # ------------------------------------------- the repair accept verdict (v5.42.0+)
  #
  # This replaces the round budget, which counted repair rounds and demanded a recorded
  # decision once a component reached two of them. A count was never the closing condition;
  # it was a proxy for one. The question that decides whether a component is done is whether
  # its repair was accepted, and a component can reach that answer on round one or fail to
  # reach it on round four. Keying the demand to the count asked a converged component to
  # justify itself and asked nothing of an unconverged one that stopped early.
  #
  # `[a]ddress` still loops as it always did. What changed is what the record answers to. A
  # repaired component carries `accept {action, suite, decided_by, reason}` on its row, where
  # action is accepted | not_accepted | cannot_judge, and anything other than `accepted` is a
  # component that shipped on somebody's decision rather than on a verdict. That decision is
  # read from exactly where the escalation demand read it before, unchanged: a top-level
  # `escalation.reason`, or the `resolution` on the round that settled it.
  #
  # A repaired component with no `accept` key at all is `unresolved`, not clean. Without that
  # half the field is advisory and a builder routes around it by omission, which is the defect
  # this repo has already found at five layers. The same answer covers a record that cannot
  # say whether a component was repaired at all: a rounds count that is not a number is a
  # malformed record, named as one rather than read as a component nobody touched.
  #
  # ALL FOUR FIELDS ARE READ, not just `action`. A verdict recording an action and nothing else
  # is the advisory shape this block exists to end, and it is not how the two neighbouring
  # checks in this file behave: `closing_fixes` demands `verified_by` and a non-blank `reason`,
  # and a deferral is rejected short any of its three fields. `suite` and `decided_by` are
  # closed enums `scripts/repair-accept-check.sh` always emits, so an absent or off-enum one is
  # a transcription that lost the thing the verdict rests on, and `reason` is what says which
  # of the kernel's reasons drove the action. An unreadable field is `unresolved`, the answer
  # this file gives every other could-not-tell.
  #
  # WHAT THIS CANNOT SEE. `accept.suite` is a scalar the builder wrote down, not a suite this
  # script ran; a self-reported `suite: green` and a green suite are byte-identical here. One
  # live record shows why that matters -- phpcs, phpstan and phpunit all passed over a repaired
  # tree that still carried two criticals a later critic found. The suite is a floor, not a
  # proof. This block checks that the verdict was recorded, and that a non-acceptance was
  # somebody's stated decision. It cannot check that either one is true.
  #
  # KNOWN CEILING, inherited from the escalation read this replaced and not introduced here.
  # `ESC` below is computed ONCE from the whole payload, so one recorded decision clears every
  # unaccepted component in the record: ten components ending `not_accepted` are satisfied by a
  # single sentence written about one of them, and the message then prints that one reason
  # beside the count of ten. Section 4 of the design says this read is kept "unchanged", so
  # narrowing it to per-component is a separate change with its own record. It is named here
  # and in `references/build-critique.md` so a builder does not read the per-round `resolution`
  # form as a per-component demand.
  #
  # THE CEILING THAT MAKES THE OTHERS MOOT, and it is the one to fix first. Whether a component
  # was repaired is read from the record's OWN `rounds` count and `rounds[]` entries. A build
  # that repairs a component and writes `rounds: 1` with no `rounds[]` entry owes no verdict and
  # passes clean, so every demand above rests on the builder having recorded that it repaired
  # anything. That is inherited unchanged from the round budget this replaced, which read the
  # same field the same way, and `agents/wo-critic.md` already names the weakness in its own
  # words: a builder that runs four rounds and writes a count of one defeats it. Closing it
  # needs a repair signal the builder does not author, which no artifact in this rung currently
  # produces. Named rather than papered over: the three ceilings above are about a verdict that
  # may be untrue, and this one is about a verdict that may never be demanded at all.
  #
  # The reads below run malformed-first: a verdict that cannot be read and a repair nobody
  # recorded are both `unresolved`, and both would otherwise fall through to the decision
  # demand and clear on an escalation reason written for something else.
  # An action outside the enum is a verdict nobody can read. It is not the same as
  # `not_accepted`: a typo and a refusal are different states, and picking one of them here
  # would be the guess this file refuses everywhere else.
  BAD_ACTION=$(accept_bad_action_components "$PAYLOAD")
  if [ "$BAD_ACTION" = "$JQ_ERR" ]; then
    set_ev_s accept_check "unreadable"
    add_msg "the accept action enum could not be read, so whether any repair was accepted is unknown"
    emit fail true "" 1
  fi
  if [ "$(jq -r 'length' <<<"$BAD_ACTION")" -gt 0 ]; then
    set_ev malformed_accept "$BAD_ACTION"
    add_msg "a component records an accept verdict that is not accepted, not_accepted or cannot_judge, so whether its repair was accepted cannot be read"
    emit fail true "" 1
  fi

  # `suite` gets its own read because the whole account of what this verdict is worth rests on
  # it: `accepted` means a green suite raised no objection, and a verdict that cannot say which
  # suite result it weighed is a verdict about nothing. Absent and off-enum are one answer here
  # -- both leave the value unreadable, and neither is `not_run`, which is a real result a
  # builder states on purpose.
  BAD_SUITE=$(accept_bad_suite_components "$PAYLOAD")
  if [ "$BAD_SUITE" = "$JQ_ERR" ]; then
    set_ev_s accept_check "unreadable"
    add_msg "the accept suite field could not be read, so what suite result each verdict weighed is unknown"
    emit fail true "" 1
  fi
  if [ "$(jq -r 'length' <<<"$BAD_SUITE")" -gt 0 ]; then
    set_ev malformed_accept_suite "$BAD_SUITE"
    add_msg "a component records an accept verdict with no readable suite; record suite green, red or not_run, because a verdict that cannot say what suite result it weighed says nothing"
    emit fail true "" 1
  fi

  # The remaining two fields of the contract. `decided_by` names which of the two facts settled
  # the action -- the suite, the test motion, or neither -- and it is a closed enum the kernel
  # emits on every run. `reason` is the sentence carrying why; a blank one collapses a stated
  # decision into a recorded shrug, which is why the two checks further down this file reject a
  # blank `closing_fixes.reason` and a blank `why_now_is_wrong` on a deferral.
  BAD_BASIS=$(accept_bad_basis_components "$PAYLOAD")
  if [ "$BAD_BASIS" = "$JQ_ERR" ]; then
    set_ev_s accept_check "unreadable"
    add_msg "the accept decided_by and reason fields could not be read, so what drove each action is unknown"
    emit fail true "" 1
  fi
  if [ "$(jq -r 'length' <<<"$BAD_BASIS")" -gt 0 ]; then
    set_ev malformed_accept_basis "$BAD_BASIS"
    add_msg "a component records an accept verdict with no readable decided_by or a blank reason; record decided_by suite_and_motion, motion or none, and say in reason what drove the action"
    emit fail true "" 1
  fi

  # Whether a component was repaired is read from `checkpoint_repaired` on its row, the sha
  # captured inside the `[a]ddress` block in commands/implement.md and nowhere else. A value
  # that is neither a sha string nor null says a repair state was written down and cannot be
  # read, and is reported as unresolved rather than folded into the clean set.
  #
  # IT USED TO BE READ TWO WAYS, from a `rounds` count above one on the row and from a
  # top-level `rounds[]` entry naming the component. Both counted rounds, and a component now
  # gets at most one critic round. The count was also the weaker reading while it worked: on
  # the last record built under it, `rounds>1` named 2 of 14 components and 13 of 14 carried a
  # repaired checkpoint.
  UNREADABLE_REPAIR=$(accept_unreadable_repair_components "$PAYLOAD")
  if [ "$UNREADABLE_REPAIR" = "$JQ_ERR" ]; then
    set_ev_s accept_check "unreadable"
    add_msg "the component repair checkpoints could not be read, so which components were repaired is unknown"
    emit fail true "" 1
  fi
  if [ "$(jq -r 'length' <<<"$UNREADABLE_REPAIR")" -gt 0 ]; then
    set_ev unreadable_repair_state "$UNREADABLE_REPAIR"
    add_msg "a component records a checkpoint_repaired that is neither a sha nor null, and no accept verdict, so whether it was repaired cannot be established; that is unresolved, not clean"
    emit fail true "" 1
  fi

  NO_ACCEPT=$(accept_missing_verdict_components "$PAYLOAD")
  if [ "$NO_ACCEPT" = "$JQ_ERR" ]; then
    set_ev_s accept_check "unreadable"
    add_msg "the set of components carrying no accept verdict could not be read, so whether a repair went unrecorded is unknown"
    emit fail true "" 1
  fi
  NOACC_N=$(jq -r 'length' <<<"$NO_ACCEPT")
  if [ "$NOACC_N" -gt 0 ]; then
    set_ev unrecorded_accept "$NO_ACCEPT"
    add_msg "$NOACC_N repaired component(s) carry no accept verdict: $NO_ACCEPT"
    add_msg "record accept {action, suite, decided_by, reason} on every component that was repaired; a repair nobody accepted is not a repair that passed"
    emit fail true "" 1
  fi

  UNACCEPTED=$(accept_unaccepted_components "$PAYLOAD")
  if [ "$UNACCEPTED" = "$JQ_ERR" ]; then
    set_ev_s accept_check "unreadable"
    add_msg "the set of components ending on a non-acceptance could not be read, so whether any component shipped unaccepted is unknown"
    emit fail true "" 1
  fi
  UNACC_N=$(jq -r 'length' <<<"$UNACCEPTED")
  set_ev unaccepted_components "$UNACCEPTED"
  if [ "$UNACC_N" -gt 0 ]; then
    # Two places are legitimate, and the second is the one a live build actually produced:
    # a top-level `escalation.reason`, or a `resolution` on the round it settled. The
    # per-round form is better -- a decision belongs with the round that provoked it -- and
    # the check this read comes from demanded the other one before anyone looked at a real
    # record.
    #
    # BOTH HALVES TRIM, the same `gsub("^\\s+|\\s+$";"")` BAD_BASIS applies forty lines above and
    # the deferral and closing-fixes checks apply below. This is the field that clears every
    # unaccepted component in the record on one string, so a decision of `" "` clearing them all
    # was the loosest read in the block sitting on the widest blast radius. Trimmed for the
    # comparison AND for what gets reported: the message prints the reason back, and a decision
    # padded with newlines reads as a decision nobody wrote.
    ESC=$(accept_escalation_reason "$PAYLOAD")
    if [ "$ESC" = "$JQ_ERR" ]; then
      # This read is the one place an empty result and a jq error already differed, and the
      # difference ran the wrong way: an unreadable `escalation` or `rounds[]` produced an
      # empty ESC, which the branch below reports as "no decision recorded". That accuses a
      # record of a thing it may not have done, and hides the thing it did do, which is fail
      # to parse. Unreadable is its own answer here as everywhere else in this block.
      set_ev_s accept_check "unreadable"
      add_msg "the recorded decision could not be read, so whether a non-acceptance was somebody's stated decision is unknown"
      emit fail true "" 1
    fi
    [ "$ESC" = "null" ] && ESC=""
    if [ -z "$ESC" ]; then
      add_msg "$UNACC_N component(s) ended on an accept verdict other than accepted with no decision recorded; say who decided to ship them and why"
      emit fail true "" 1
    fi
    add_msg "$UNACC_N component(s) ended on an accept verdict other than accepted; shipping them was a recorded decision: $ESC"
  fi

  # -------------------------------------------------- deferred findings (v5.35.0+)
  #
  # PREMATURE FIXES. A critic correctly reported that a method had no production caller --
  # true, and unfixable, because the caller was a component three steps later in the build
  # order. With no way to defer it, the builder answered by writing a spec for the absent
  # caller. That answer produced the next round's critical, whose answer produced the round
  # after that. Three of the four unfixable findings were self-generated by trying to close
  # the first one.
  #
  # Not machine-checkable as "was this premature" -- only as "did you say so". A finding that
  # cannot be resolved yet says what it is waiting on, and stops blocking.
  #
  # (The companion checks that used to live here, judging by self-report whether a repair grew
  # or strayed past what a finding asked for, are gone. `scripts/repair-scope-check.sh` answers
  # the scope half instead, by comparing the finding's `where[]` against the touched-file set
  # rather than asking the builder to grade its own repair. See `finding_contract` design D6.)

  # ------------------------------------------------- scope compliance (v5.40.0+, finding_contract D6)
  #
  # The kernel is `scripts/repair-scope-check.sh`; this is its only caller. It compares two sets --
  # every file a critical/concern finding's `where[]` names, against every file this change set
  # touched -- and surfaces (never blocks: `blocks` is always false) a touched file named by no
  # finding, the same way most of this record surfaces rather than halts.
  #
  # FINDING_SITES is read from `components[].critique_ref`, which is not a reliable pointer: on
  # real records it is null, a path relative to the task folder, an absolute path, or free prose
  # ("paper test, structured 3-phase, 18 fixtures run against the real script" -- not a path at
  # all). Every ref is resolved and read defensively; one that is not a readable JSON object
  # contributes nothing. That is not folded into a clean scope -- it feeds the same empty set the
  # kernel already reads as `cannot_judge`, so an unresolvable pointer surfaces as "could not
  # judge", never as `in_scope`. As of this build, every real record in the corpus predates
  # `where[]` (schema_version absent), so `cannot_judge` is the honest, expected answer today; the
  # wiring is live for the day a critic starts writing it.
  #
  # TOUCHED_FILES is the repair's own `git diff --name-status` where the rung wrote one, and
  # `review-change-set.sh`'s `.files` from `$CHANGE_SET_FILE` -- already required on this path (see
  # build_identity below) -- only as a fallback. Read independently of whether that later block
  # validates it, so this check does not depend on a later block's success. See the subject note
  # below for why the two are not interchangeable.
  FS_COMPONENTS=$(jq -c '(.components // [])' <<<"$PAYLOAD" 2>/dev/null) || FS_COMPONENTS='[]'
  FINDING_SITES='[]'
  while IFS= read -r ref; do
    if [ -z "$ref" ] || [ "$ref" = "null" ]; then continue; fi
    case "$ref" in
      /*) REF_PATH="$ref" ;;
      *)  REF_PATH="$TASK_DIR/$ref" ;;
    esac
    [ -f "$REF_PATH" ] || continue
    jq -e 'type == "object"' "$REF_PATH" >/dev/null 2>&1 || continue
    # BOTH envelope shapes, because `critique_ref` points at either. The aggregate
    # `<component>.critique.json` that `references/gate-audit-schema.md:884` names keeps findings
    # under `.critics[].findings`; a single critic's own file keeps them at the top level. Reading
    # only the top level -- which is how this shipped -- found nothing on every aggregate envelope,
    # so FINDING_SITES stayed empty and the whole check answered `cannot_judge` on records that DID
    # name sites. `(.critics[]?, .)` reads both and unions them.
    REF_SITES=$(jq -c \
      '[(.critics[]?, .)
        | (.findings // [])[]?
        | select((.severity // "") == "critical" or (.severity // "") == "concern")
        | (.where // [])[]? | (.file // empty)]' \
      "$REF_PATH" 2>/dev/null) || REF_SITES='[]'
    FINDING_SITES=$(jq -c -n --argjson a "$FINDING_SITES" --argjson b "$REF_SITES" \
      '($a + $b) | unique' 2>/dev/null) || FINDING_SITES='[]'
  done < <(jq -r '.[] | (.critique_ref // "") | tostring' <<<"$FS_COMPONENTS" 2>/dev/null)

  # THE SUBJECT. Two file sets are available here and they answer different questions. The rung
  # writes `build-critique/<component>.repair.txt` at every `[a]ddress` -- `git diff --name-status`
  # over the REPAIR's own range -- and that is what D6 asks about: did this repair stray past what
  # the finding named. `review-change-set.sh`'s `.files` is the whole task change set, every
  # component and every build in it, so comparing that against one round's finding sites reports
  # the entire task as unnamed. Prefer the repair diffs; fall back to the change set when the task
  # recorded no repair, and record which subject was compared, because a scope verdict read without
  # knowing what it compared is not a readable verdict.
  #
  # THE `determined` CLAIM IS EARNED, NEVER ASSUMED. A change-set object with no `files` key passes
  # `type == "object"` while `(.files // [])` yields `[]`, and stamping that `determined` -- which
  # is how this shipped -- handed the kernel an empty touched set it answered `in_scope`, with the
  # message "every touched file is named by a finding", over a comparison nobody made. The header
  # of `repair-scope-check.sh` names this exact caller mistake as the reason
  # `--touched-files-source` exists. The key PRESENT and holding an array of strings is
  # `determined`, empty array included: a change set that genuinely recorded zero files is a fact.
  # Key absent, wrong type, or unreadable is `undetermined`, which the kernel answers
  # `cannot_judge`.
  TOUCHED_SOURCE="undetermined"
  TOUCHED_FILES='[]'
  TOUCHED_SUBJECT="none"

  REPAIR_FILES=()
  while IFS= read -r rf; do
    [ -n "$rf" ] && REPAIR_FILES+=("$rf")
  done < <(find "$TASK_DIR/build-critique" -maxdepth 1 -type f -name '*.repair.txt' 2>/dev/null | sort)

  if [ "${#REPAIR_FILES[@]}" -gt 0 ]; then
    TOUCHED_SUBJECT="repair_diff"
    # A ZERO-BYTE repair diff is not a repair that touched nothing. `git diff` writes its error to
    # stderr after the shell redirect has already created the file, so a range handed a checkpoint
    # LABEL instead of a sha leaves exactly this -- the failure `repair-accept-check.sh`'s header
    # records shipping in commands/implement.md. One unreadable diff means the repair set was not
    # established, so the whole subject is undetermined rather than partially compared.
    RF_EMPTY=0
    for rf in "${REPAIR_FILES[@]}"; do [ -s "$rf" ] || RF_EMPTY=1; done
    if [ "$RF_EMPTY" -eq 0 ]; then
      # name-status is "STATUS<TAB>path", and "R###<TAB>old<TAB>new" for a rename or copy. Every
      # field after the status is a path the repair touched, so both ends of a rename count.
      TOUCHED_FILES=$(awk -F'\t' 'NF>1{for(i=2;i<=NF;i++) if($i!="") print $i}' "${REPAIR_FILES[@]}" 2>/dev/null \
        | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique' 2>/dev/null) || TOUCHED_FILES=""
      if [ -n "$TOUCHED_FILES" ]; then
        TOUCHED_SOURCE="determined"
      else
        TOUCHED_FILES='[]'
      fi
    fi
  elif [ -n "$CHANGE_SET_FILE" ] && [ -f "$CHANGE_SET_FILE" ]; then
    TOUCHED_SUBJECT="task_change_set"
    if jq -e 'type == "object" and has("files")
              and (.files | type == "array" and all(.[]; type == "string"))' \
         "$CHANGE_SET_FILE" >/dev/null 2>&1 \
       && TOUCHED_FILES=$(jq -c '.files' "$CHANGE_SET_FILE" 2>/dev/null); then
      TOUCHED_SOURCE="determined"
    else
      TOUCHED_FILES='[]'
    fi
  fi
  set_ev_s scope_subject "$TOUCHED_SUBJECT"

  SCOPE_SCRIPT="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/repair-scope-check.sh"
  if [ -f "$SCOPE_SCRIPT" ]; then
    SCOPE_OUT=$(bash "$SCOPE_SCRIPT" --finding-sites "$FINDING_SITES" \
      --touched-files "$TOUCHED_FILES" --touched-files-source "$TOUCHED_SOURCE" 2>/dev/null) \
      || SCOPE_OUT=""
    if [ -n "$SCOPE_OUT" ] && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$SCOPE_OUT"; then
      set_ev scope_compliance "$SCOPE_OUT"
      SCOPE_ACTION=$(jq -r '.action' <<<"$SCOPE_OUT")
      case "$SCOPE_ACTION" in
        out_of_scope)
          SCOPE_UNNAMED=$(jq -r '.unnamed | join(", ")' <<<"$SCOPE_OUT")
          add_msg "scope compliance ($TOUCHED_SUBJECT): touched file(s) named by no finding: $SCOPE_UNNAMED -- surfaced, not blocking"
          ;;
        in_scope)
          add_msg "scope compliance ($TOUCHED_SUBJECT): every touched file is named by a finding or covered by an allow rule"
          ;;
        cannot_judge)
          if [ "$(jq -r 'length' <<<"$FINDING_SITES")" -eq 0 ]; then
            add_msg "scope compliance could not be judged: no finding named a site"
          else
            add_msg "scope compliance could not be judged: the touched-file set could not be determined (subject: $TOUCHED_SUBJECT)"
          fi
          ;;
        *) add_msg "scope compliance returned an unrecognised action: $SCOPE_ACTION" ;;
      esac
      # The inverse set, reported whatever the action was (v5.47.0+). `unnamed` says the repair
      # went somewhere no finding asked for; this says it did not go somewhere a finding did.
      # A round-2 critic used to answer that question, and it ranked "did less" as the CRITICAL
      # of the three shapes it looked for, because the defect the remedy named is still there.
      # A component now gets one critic round, so that reader is gone and this is what replaced
      # it. Emitted here rather than left in evidence: `out_of_range[]` shipped as a field with
      # no reader while the schema called it the channel to /review, and that is the same shape.
      SCOPE_UNADDR=$(jq -r '(.unaddressed // []) | join(", ")' <<<"$SCOPE_OUT")
      if [ -n "$SCOPE_UNADDR" ]; then
        add_msg "scope compliance ($TOUCHED_SUBJECT): finding site(s) the repair never touched: $SCOPE_UNADDR -- the remedy may be part-applied; surfaced, not blocking"
      fi
    else
      set_ev_s scope_compliance "unreadable"
      add_msg "scope compliance could not be computed: repair-scope-check.sh produced no readable verdict"
    fi
  else
    set_ev_s scope_compliance "unavailable"
    add_msg "scope compliance could not be computed: repair-scope-check.sh not found"
  fi

  # Deferrals live on the component row since v5.47.0. They were parked on a `rounds[]` entry,
  # and a component now gets at most one critic round, so no such entry is written and a reader
  # pointed at that array would find nothing on every record. The fallback is the sentinel, not
  # '[]': an unreadable payload here used to read as "I looked and found no deferrals", which is
  # a silent pass in a block whose whole job is to refuse one.
  DEFER_ARR=$(jq -c '(.components // [])' <<<"$PAYLOAD" 2>/dev/null) || DEFER_ARR="$JQ_ERR"
  # `JQ_ERR` is the same sentinel the accept block above uses, defined once beside the first
  # read that needs it. The deferral filter below falls back to it rather than to `[]`, and
  # the sentinel is reported as unresolved.

  # A deferral carries three things and all three are required in `agents/wo-critic.md`,
  # `references/build-critique.md`, `references/gate-audit-schema.md` and `commands/implement.md`:
  # the finding, what it waits on, and why answering it now would be wrong. Until v5.36.0 this
  # check read the first two and never the third, so `why_now_is_wrong` was required in four
  # documents and enforced nowhere.
  #
  # It is not decoration. The deferral exists because answering a finding before its blocker is
  # built produces a speculative fix, and on the build this rule came from three of the four
  # unanswerable findings were generated by trying to close the first one. `why_now_is_wrong` is
  # the sentence that distinguishes a finding genuinely blocked on absent code from one the
  # builder simply did not want to address, and a blank one collapses that distinction.
  BAD_DEFERRALS=$(jq -c \
    '[ .[] | (.deferred // [])[]
           | select((((.blocked_on // "") | tostring) | gsub("^\\s+|\\s+$";"")) == ""
                    or (((.finding // "") | tostring) | gsub("^\\s+|\\s+$";"")) == ""
                    or (((.why_now_is_wrong // "") | tostring) | gsub("^\\s+|\\s+$";"")) == "")
           | ((.finding // "unnamed") | tostring) ]' <<<"$DEFER_ARR" 2>/dev/null) || BAD_DEFERRALS="$JQ_ERR"
  if [ "$BAD_DEFERRALS" = "$JQ_ERR" ]; then
    set_ev_s deferral_check "unreadable"
    add_msg "the deferred findings could not be read, so whether each names what it waits on and why now is wrong is unknown"
    emit fail true "" 1
  fi
  BD_N=$(jq -r 'length' <<<"$BAD_DEFERRALS")
  if [ "$BD_N" -gt 0 ]; then
    set_ev malformed_deferrals "$BAD_DEFERRALS"
    add_msg "$BD_N deferred finding(s) are missing the finding, the component they wait on, or why answering now would be wrong; a deferral short any of the three is a finding nobody will return to"
    emit fail true "" 1
  fi
  DEFERRED_N=$(jq -r '[ .[] | (.deferred // []) | length ] | add // 0' <<<"$DEFER_ARR" 2>/dev/null) || DEFERRED_N=0
  if [ "$DEFERRED_N" -gt 0 ]; then
    set_ev deferred_findings "$DEFERRED_N"
    add_msg "$DEFERRED_N finding(s) deferred to a component not yet built; they carry forward rather than being answered speculatively"
  fi

  # ------------------- findings suppressed as out of range (v5.45.0+, finding_contract c5)
  #
  # `wo-critique-aggregate.sh` drops a finding whose every site falls outside the component's own
  # range out of the severity that decides `blocking` -- it opens no repair round -- and collects it
  # into the envelope's top-level `out_of_range[]`. `references/gate-audit-schema.md` states that
  # that array is "the channel by which such a finding reaches /review; a consumer that does not
  # read it will see the finding vanish rather than move." THIS IS THE CONSUMER at the other end of
  # that sentence. It shipped without one, which made the sentence a description of a channel with
  # nothing listening -- a kernel with no caller, the same defect `command-body-lengths.sh`'s own
  # comment records this body fixing for `repair-scope-check.sh` one component earlier.
  #
  # It surfaces and never blocks, exactly as `deferred_findings` above does. An out-of-range finding
  # is a real finding about real code, just not about the slice this component was asked to change,
  # and the reviewer is the one who decides where it goes. Suppressing the round and then saying
  # nothing would be the finding vanishing.
  #
  # AN UNREADABLE REF IS NOT ZERO. The refs are walked exactly the way FINDING_SITES walks them
  # above, and one that does not resolve to a readable JSON object contributes nothing -- so a count
  # on its own would read "nothing was suppressed" on a record whose pointers are all broken. The
  # unreadable ones are counted separately and said out loud, which is the same posture as the
  # kernel's own `range_check.status:"not_run"`: nobody looked is not the same answer as nothing
  # was found. A readable envelope with no `out_of_range` key claims nothing either way -- every
  # record written before the field existed is that shape -- so it adds to neither count.
  OOR_N=0
  OOR_UNREADABLE=0
  OOR_SITES='[]'
  while IFS= read -r ref; do
    if [ -z "$ref" ] || [ "$ref" = "null" ]; then continue; fi
    case "$ref" in
      /*) REF_PATH="$ref" ;;
      *)  REF_PATH="$TASK_DIR/$ref" ;;
    esac
    if [ ! -f "$REF_PATH" ] || ! jq -e 'type == "object"' "$REF_PATH" >/dev/null 2>&1; then
      OOR_UNREADABLE=$(( OOR_UNREADABLE + 1 )); continue
    fi
    REF_OOR=$(jq -c '[ (.out_of_range // [])[]? | select(type == "object") ]' "$REF_PATH" 2>/dev/null) || REF_OOR="$JQ_ERR"
    if [ "$REF_OOR" = "$JQ_ERR" ]; then
      OOR_UNREADABLE=$(( OOR_UNREADABLE + 1 )); continue
    fi
    OOR_N=$(( OOR_N + $(jq -r 'length' <<<"$REF_OOR") ))
    REF_OOR_SITES=$(jq -c '[ .[] | (.where // [])[]? | (.file // empty) ]' <<<"$REF_OOR" 2>/dev/null) || REF_OOR_SITES='[]'
    OOR_SITES=$(jq -c -n --argjson a "$OOR_SITES" --argjson b "$REF_OOR_SITES" \
      '($a + $b) | unique' 2>/dev/null) || OOR_SITES='[]'
  done < <(jq -r '.[] | (.critique_ref // "") | tostring' <<<"$FS_COMPONENTS" 2>/dev/null)

  if [ "$OOR_N" -gt 0 ]; then
    set_ev out_of_range_findings "$OOR_N"
    set_ev out_of_range_sites "$OOR_SITES"
    add_msg "$OOR_N finding(s) were recorded out of the component's own range and opened no repair round; they are handed here rather than dropped, sited at: $(jq -r 'join(", ")' <<<"$OOR_SITES")"
  fi
  if [ "$OOR_UNREADABLE" -gt 0 ]; then
    set_ev out_of_range_unreadable_refs "$OOR_UNREADABLE"
    add_msg "$OOR_UNREADABLE component critique_ref(s) could not be read, so whether a finding was suppressed as out of range is unknown, not zero"
  fi

  # ----------------------- the repair AFTER the last critique pass (v5.35.3+)
  #
  # The rung critiques a build and then the findings get repaired -- and on the path where the
  # repair is the last thing that happens, nothing critiques it. Under per-component rounds the
  # next round sees the repair. Under a single closing pass there is no next round, so the code
  # that ships is not the code any critic read.
  #
  # This is not hypothetical and it is not rare. One live record invented
  # `rung_resolution.closing_fixes_not_critiqued: true` because the situation existed and this
  # schema had no field for it; that ad-hoc key appears nowhere in this plugin and nothing has
  # ever read it. On the build that produced this rule, six fixes landed after all three lenses
  # returned -- including a CRITICAL in the branch that decides whether published content gets
  # unpublished, whose fix was written by the same agent that wrote the bug. The orchestrator
  # dispatched a fresh-eyes verifier by hand, correctly, and nothing in the framework asked it
  # to.
  #
  # `applied: 0` is a real answer and passes. What fails is a repair the critics never saw with
  # nobody named as having checked it, because the author of a fix is the one person who cannot
  # independently confirm it.
  if ! jq -e 'has("closing_fixes")' <<<"$PAYLOAD" >/dev/null 2>&1; then
    set_ev_s closing_fixes "absent"
    add_msg "the record cannot say whether anything was changed after the last critique pass"
    add_msg "add closing_fixes {applied, verified_by, reason}; applied:0 is an answer"
    emit fail true "" 1
  fi
  CF=$(jq -c '.closing_fixes' <<<"$PAYLOAD")
  set_ev closing_fixes "$CF"
  CF_N=$(jq -r 'if (.applied | type) == "number" then .applied else -1 end' <<<"$CF" 2>/dev/null) || CF_N=-1
  if [ "$CF_N" = "-1" ]; then
    add_msg "closing_fixes.applied is missing or not a number, so the record cannot say how much shipped uncritiqued"
    emit fail true "" 1
  fi
  if [ "$CF_N" -gt 0 ]; then
    CF_BY=$(jq -r '((.verified_by // "") | tostring | gsub("^\\s+|\\s+$"; ""))' <<<"$CF" 2>/dev/null) || CF_BY=""
    CF_WHY=$(jq -r '((.reason // "") | tostring | gsub("^\\s+|\\s+$"; ""))' <<<"$CF" 2>/dev/null) || CF_WHY=""
    if [ -z "$CF_BY" ]; then
      add_msg "$CF_N fix(es) landed after the last critique pass and nobody is named as having checked them"
      add_msg "name who verified the repair in verified_by, or record author/none with a reason"
      emit fail true "" 1
    fi
    # The honest answer to "who checked this?" is usually MIXED, and the first real use of this
    # field said so: two fixes read by a fresh context, four resting on the author's own tests.
    # An exact match on author|none|self missed that entirely -- a mixed answer fell to the
    # free-text branch and skipped the reason requirement, so the check could not fire on the
    # most truthful thing a build can write. Match the word anywhere instead.
    #
    # It over-triggers on a phrasing like "a fresh context, not the author", and that is the
    # right side to err on: the cost is one sentence, and the alternative is a rule that passes
    # whenever the answer is complicated.
    if printf '%s' "$CF_BY" | grep -qiE '(^|[^[:alnum:]])(author|self|none|nobody|unverified)([^[:alnum:]]|$)'; then
      if [ -z "$CF_WHY" ]; then
        add_msg "$CF_N closing fix(es) name the author, or nobody, among their verifiers, with no reason recorded"
        add_msg "the author of a fix cannot independently confirm it; say which fixes that covers and why no fresh context read them"
        emit fail true "" 1
      fi
      add_msg "$CF_N closing fix(es) were not all independently verified ($CF_BY): $CF_WHY"
    else
      add_msg "$CF_N closing fix(es) landed after the critics and were verified by $CF_BY"
    fi
  fi

  # ------------------- can each criterion be verified by anything shipped? (v5.35.2+)
  #
  # `criteria_not_implemented` says a criterion has no code behind it yet. It was also being
  # used for a different fact it cannot express: a criterion that no test at the level this
  # design chose can verify AT ALL. Seen live: a criterion asserting a count of the site's
  # actual content, against a test strategy that selected kernel tests, which run on an empty
  # database and cannot observe it at any level of effort. Nothing surfaced that until a critic
  # was briefed by hand at the end of the build, which is the most expensive moment to learn it
  # and the furthest from the design decision that caused it.
  #
  # The two facts have opposite remedies -- one is "write the code", the other is "the plan for
  # proving this is wrong" -- so they get separate fields. `criteria_unverifiable` is required
  # whenever the alignment axis actually ran: an empty array is the positive claim that every
  # criterion has something shipped that could verify it, which is an answer. Silence is not.
  if [ "$ALIGN" != "" ] && [ "$ALIGN" != "skipped" ]; then
    if ! jq -e '.alignment | has("criteria_unverifiable")' <<<"$PAYLOAD" >/dev/null 2>&1; then
      add_msg "the alignment block does not say whether any success criterion is unverifiable at the test levels this design chose"
      add_msg "add criteria_unverifiable[] (empty asserts every criterion has something that could prove it)"
      emit fail true "" 1
    fi
    CU_BAD=$(jq -c \
      '[(.alignment.criteria_unverifiable // [])[]
        | if type != "object" then {criterion:(tostring), why:"not an object"}
          elif (((.criterion // "") | tostring | gsub("^\\s+|\\s+$"; "")) == "")
            then {criterion:"unnamed", why:"no criterion named"}
          elif (((.reason // "") | tostring | gsub("^\\s+|\\s+$"; "")) == "")
            then {criterion:(.criterion | tostring), why:"no reason"}
          elif (((.what_would_verify // "") | tostring | gsub("^\\s+|\\s+$"; "")) == "")
            then {criterion:(.criterion | tostring), why:"does not say what would verify it"}
          else empty end]' \
      <<<"$PAYLOAD" 2>/dev/null) || CU_BAD='[]'
    CU_BAD_N=$(jq -r 'length' <<<"$CU_BAD" 2>/dev/null) || CU_BAD_N=0
    if [ "$CU_BAD_N" -gt 0 ]; then
      set_ev malformed_unverifiable "$CU_BAD"
      add_msg "$CU_BAD_N unverifiable-criterion entr(ies) are incomplete: $CU_BAD"
      add_msg "each needs criterion, reason, and what_would_verify; naming the gap without naming the fix leaves it where it was found"
      emit fail true "" 1
    fi
    CU_N=$(jq -r '(.alignment.criteria_unverifiable // []) | length' <<<"$PAYLOAD" 2>/dev/null) || CU_N=0
    if [ "$CU_N" -gt 0 ]; then
      set_ev criteria_unverifiable "$CU_N"
      add_msg "$CU_N criterion(a) cannot be verified at the test levels this design chose; each records what would verify it"
    fi
  fi

  # ------------------------------------------- was the component ever RUN? (v5.35.2+)
  #
  # Every gate this rung fires can pass over code that has never been executed. Seen live: a
  # Drush command class shipped with phpcs clean, phpstan clean and 58 kernel tests green,
  # while its attribute discovery, option parsing and output were entirely unproven -- because
  # installing the module to exercise the command would also have armed a cron hook that
  # unpublishes site content. Declining to run it was the right call. The defect is that the
  # decision lived in a chat window and the record said nothing, so `/review` would have gone
  # green over a component nobody had run.
  #
  # This is deliberately NOT a demand that everything be executed. Static-only verification is
  # legitimate and sometimes the only safe option. What is refused is leaving it unsaid: a row
  # that cannot say whether its code ever ran is the same "could not tell" this gate refuses
  # everywhere else.
  RUNTIME_BAD=$(jq -c \
    '[(.components // [])[]
      | (.component // "unnamed") as $n
      | (.runtime // null) as $r
      | if $r == null then {component:$n, why:"no runtime field"}
        elif ($r | type) != "string" then {component:$n, why:"runtime is not a string"}
        elif ($r == "executed") then empty
        elif ($r == "static_only" or $r == "not_run") then
          (if (((.runtime_reason // "") | tostring | gsub("^\\s+|\\s+$"; "")) == "")
           then {component:$n, why:("runtime " + $r + " with no runtime_reason")}
           else empty end)
        else {component:$n, why:("unknown runtime value: " + $r)}
        end]' \
    <<<"$PAYLOAD" 2>/dev/null) || RUNTIME_BAD='[]'
  RUNTIME_BAD_N=$(jq -r 'length' <<<"$RUNTIME_BAD" 2>/dev/null) || RUNTIME_BAD_N=0
  if [ "$RUNTIME_BAD_N" -gt 0 ]; then
    set_ev runtime_unstated "$RUNTIME_BAD"
    add_msg "$RUNTIME_BAD_N critiqued component(s) cannot say whether their code was ever run: $RUNTIME_BAD"
    add_msg "each row needs runtime: executed | static_only | not_run, and a runtime_reason for the last two"
    emit fail true "" 1
  fi
  STATIC_N=$(jq -r '[(.components // [])[] | select((.runtime // "") != "executed")] | length' <<<"$PAYLOAD" 2>/dev/null) || STATIC_N=0
  if [ "$STATIC_N" -gt 0 ]; then
    set_ev components_not_executed "$STATIC_N"
    add_msg "$STATIC_N critiqued component(s) were verified without being executed; the reason is recorded on each row"
  fi

  # ------------------------------------------------- the contract baseline (v5.34.0+)
  #
  # `meets-ac` and the alignment axis both judge the change against `alignment.md` and
  # `architecture/`. The builder can edit those. Without a baseline the scope question
  # resolves against whatever the document says now, which may be text written to describe
  # the code it is meant to authorise. Seen live: a critic ruled an addition "blessed only by
  # design-doc text that self-declares added at Phase 3", and caught it only because the
  # builder had annotated its own edit. Editing the contract mid-build is legitimate and
  # sometimes forced. Editing it invisibly is not, so a change needs a reason, and a build
  # that never captured a baseline cannot answer the question at all.
  if ! jq -e 'has("contract")' <<<"$PAYLOAD" >/dev/null 2>&1; then
    set_ev_s contract "absent"
    add_msg "the record carries no contract block, so it cannot say whether the design it was judged against changed during the build"
    emit fail true "" 1
  fi
  CON=$(jq -c '.contract' <<<"$PAYLOAD")
  # Two spellings, both legitimate, and the second is what a live build wrote: `baseline` may
  # carry the STATE (captured|late) or the PATH to the baseline directory, with the state in
  # `baseline_status` alongside it. That split is reasonable -- where it is, and what it is worth
  # -- and this check originally read only the first, so a record that captured a baseline and
  # honestly labelled it `late` failed as though none had been taken. Prefer the explicit status
  # key; fall back to `baseline` when it holds a state rather than a path.
  CON_BASE=$(jq -r '((.baseline_status // "") | tostring) as $st
                    | if $st != "" then $st
                      else ((.baseline // "") | tostring) end' <<<"$CON")
  case "$CON_BASE" in
    captured|late) ;;
    */*) # a path in `baseline` with no `baseline_status` says where but never what
      CON_BASE="unstated" ;;
  esac
  CON_CHANGED=$(jq -c '(.changed // [])' <<<"$CON")
  CON_N=$(jq -r 'length' <<<"$CON_CHANGED")
  CON_REASON=$(jq -r '(.reason // "") | tostring' <<<"$CON")
  [ "$CON_REASON" = "null" ] && CON_REASON=""
  set_ev contract "$CON"

  # Re-derive rather than trust. `changed` describes something this plugin can measure, and it
  # was reaching the record as a field an agent wrote. Seen live: a record asserting
  # `changed: []` and, in the same object, a reason arguing at length that the empty diff was
  # "true and meaningless" -- while `contract-baseline.sh diff` on that same folder returned
  # `status: changed` and named two architecture files a later round had rewritten. Both the
  # count and the argument built on it were wrong, and the check downstream of them (a change
  # needs a reason) could not fire because the count it keys on said zero.
  #
  # So the count comes from disk. When the baseline is missing or the sibling script cannot
  # run, this records `unavailable` and says so rather than inventing agreement -- the gate's
  # own question is whether the build was challenged, and a broken install is not an answer
  # to it either way.
  CB_SCRIPT="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/contract-baseline.sh"
  CON_RECHECK="unavailable"
  DISK_DIFF='[]'
  if [ -f "$CB_SCRIPT" ]; then
    CB_OUT=$(bash "$CB_SCRIPT" diff "$TASK_DIR" 2>/dev/null) || CB_OUT=""
    if [ -n "$CB_OUT" ] && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$CB_OUT"; then
      case "$(jq -r '(.status // "") | tostring' <<<"$CB_OUT")" in
        changed|unchanged)
          CON_RECHECK="measured"
          DISK_DIFF=$(jq -c '((.changed // []) + (.added // []) + (.removed // [])) | sort' <<<"$CB_OUT")
          ;;
        *) CON_RECHECK="unresolved" ;;
      esac
    fi
  fi
  set_ev_s contract_recheck "$CON_RECHECK"
  if [ "$CON_RECHECK" = "measured" ]; then
    set_ev contract_changed_on_disk "$DISK_DIFF"
    CLAIMED=$(jq -c 'sort' <<<"$CON_CHANGED" 2>/dev/null) || CLAIMED='[]'
    if [ "$CLAIMED" != "$DISK_DIFF" ]; then
      add_msg "the record says the contract files $CLAIMED changed during the build; the baseline on disk says $DISK_DIFF"
      add_msg "re-run contract-baseline.sh diff and record what it returns, with a reason for each file"
      emit fail true "" 1
    fi
    # From here the measured set is what the reason requirement keys on, so a record cannot
    # under-report its way past it.
    CON_CHANGED="$DISK_DIFF"
    CON_N=$(jq -r 'length' <<<"$CON_CHANGED")
  fi

  # `late` is the migration state: a task already building when this mechanism landed cannot
  # produce an honest baseline, because the contract has already moved under it. Failing it
  # forever punishes a task for predating the check, and passing it silently would certify the
  # very amendments the baseline exists to expose. So it passes only with a reason, exactly like
  # a recorded contract change, and the record says plainly what the baseline is worth.
  if [ "$CON_BASE" = "late" ]; then
    if [ -z "$CON_REASON" ]; then
      add_msg "the contract baseline was taken after the build had begun and carries no reason; say why it could not be captured at phase start"
      emit fail true "" 1
    fi
    add_msg "the contract baseline post-dates the start of this build, so it records the contract as the build left it: $CON_REASON"
  elif [ "$CON_BASE" != "captured" ]; then
    add_msg "no contract baseline was captured at phase start, so whether the design changed under the build cannot be determined"
    emit fail true "" 1
  fi
  if [ "$CON_N" -gt 0 ] && [ -z "$CON_REASON" ]; then
    add_msg "$CON_N contract file(s) changed during the build with no reason recorded; say what was wrong with the design"
    emit fail true "" 1
  fi
  if [ "$CON_N" -gt 0 ]; then
    add_msg "$CON_N contract file(s) were amended during the build: $CON_REASON"
  fi

  # ------------------------------------------------ is this record about the code being reviewed?
  #
  # Every check above asks whether the record is internally consistent. None asks whether it
  # describes the build in front of the reviewer, and until v5.35.5 nothing did. The record
  # carried per-component checkpoint ranges as free-text prose that nothing parsed.
  #
  # `/review`'s remediate branch guarantees the gap rather than risking it. `[r]` means exit, fix,
  # re-run — fixing is the point — so every remediation produces a build the record predates.
  # Observed live: three gates failed, the operator chose [r], eleven files changed including a
  # deleted branch and a new fixture shape, and the re-run would have read the same record and
  # passed. The one gate that asks "was this build challenged by something other than the context
  # that built it?" would have answered yes about the previous build.
  #
  # `files_digest` is a sha256 over the sorted file list the critics were handed. The comparison
  # is deliberately over the file SET and not over content: a file whose content changed after the
  # critique is caught by `head`, and a set comparison stays meaningful when the change is
  # uncommitted, which at review time it usually is.
  #
  # A record with no `build_identity` cannot say which build it describes. That is unresolved, not
  # a pass — the same posture as every other could-not-tell in this file. There is no grandfather
  # clause for records written before the field existed: a record that cannot answer the question
  # is exactly the state this check exists to surface, and its age does not make it able to answer.
  BI=$(jq -c '(.build_identity // null)' <<<"$PAYLOAD" 2>/dev/null) || BI=null
  if [ "$BI" = "null" ]; then
    set_ev_s build_identity "absent"
    add_msg "the record does not say which build it describes, so whether the critics saw this code cannot be determined"
    add_msg "record build_identity {head, files_digest, files} at the close of the rung; see references/build-critique.md"
    emit fail true "" 1
  fi

  REC_HEAD=$(jq -r '(.head // "")' <<<"$BI" 2>/dev/null) || REC_HEAD=""
  REC_DIGEST=$(jq -r '(.files_digest // "")' <<<"$BI" 2>/dev/null) || REC_DIGEST=""
  if [ -z "$REC_HEAD" ] || [ -z "$REC_DIGEST" ]; then
    set_ev_s build_identity "incomplete"
    add_msg "build_identity is present but missing head or files_digest, so it identifies no build"
    emit fail true "" 1
  fi

  # The caller resolved the change set at step 4 and passes it here rather than this script
  # re-deriving it. Two reasons: the resolution rules live in review-change-set.sh and must not be
  # reimplemented, and a gate that judges a change set the reviewer did not use is judging
  # something nobody is looking at.
  if [ -z "$CHANGE_SET_FILE" ]; then
    set_ev_s build_identity "uncompared"
    add_msg "no change set was passed, so the record could not be checked against the code under review"
    add_msg "call this script with --change-set-file <path to review-change-set.sh output>"
    emit fail true "" 1
  fi
  if [ ! -f "$CHANGE_SET_FILE" ]; then
    set_ev_s build_identity "uncompared"
    add_msg "the change set file does not exist: $CHANGE_SET_FILE"
    emit fail true "" 1
  fi

  NOW_HEAD=$(jq -r '(.head // "")' "$CHANGE_SET_FILE" 2>/dev/null) || NOW_HEAD=""
  NOW_DIGEST=$(printf '%s' "$(jq -r '((.files // []) | sort | join("\n"))' "$CHANGE_SET_FILE" 2>/dev/null)" \
    | sha256sum 2>/dev/null | cut -d' ' -f1) || NOW_DIGEST=""
  if [ -z "$NOW_HEAD" ] || [ -z "$NOW_DIGEST" ]; then
    set_ev_s build_identity "uncompared"
    add_msg "the change set file could not be read for a head and a file list: $CHANGE_SET_FILE"
    emit fail true "" 1
  fi

  if [ "$REC_HEAD" != "$NOW_HEAD" ] || [ "$REC_DIGEST" != "$NOW_DIGEST" ]; then
    set_ev_s build_identity "stale"
    REC_FILES=$(jq -c '(.files // [])' <<<"$BI" 2>/dev/null) || REC_FILES='[]'
    NOW_FILES=$(jq -c '((.files // []) | sort)' "$CHANGE_SET_FILE" 2>/dev/null) || NOW_FILES='[]'
    UNSEEN=$(jq -rc --argjson r "$REC_FILES" '. - $r | join(", ")' <<<"$NOW_FILES" 2>/dev/null) || UNSEEN=""
    add_msg "the critics reviewed a different build than the one under review; this record does not describe this code"
    [ -n "$UNSEEN" ] && add_msg "file(s) in the change set that no critic saw: $UNSEEN"
    [ "$REC_HEAD" != "$NOW_HEAD" ] && add_msg "record head $REC_HEAD, change set head $NOW_HEAD"
    add_msg "re-run the build-critique rung over the delta, then write the record again"
    emit fail true "" 1
  fi

  set_ev_s build_identity "matches"

  add_msg "the build was challenged in-session: $CRITIQUED component critique(s), verdict $RV"
  emit pass false "" 0
fi

# ---------------------------------------------------------- the work-order build path
#
# No `_build-critique.json`. That is legitimate for exactly one reason: the build went
# through `/run-work-orders`, which challenges each work-order with `wo-critic` and writes
# `wo-NN._critique.json` instead. Read that off disk rather than believing a sentence about
# which path was taken.

set_ev_s build_critique_record "absent"

CRITIQUES=""
HALTS=""
WOS=""
if [ -d "$WO_DIR" ]; then
  CRITIQUES=$(find "$WO_DIR" -maxdepth 1 -name 'wo-*_critique.json' -type f 2>/dev/null | sort)
  HALTS=$(find "$WO_DIR" -maxdepth 1 -name 'wo-*.HALT' -type f 2>/dev/null | sort)
  WOS=$(find "$WO_DIR" -maxdepth 1 -name 'wo-*.md' -type f 2>/dev/null | sort)
fi
count_lines() { if [ -z "$1" ]; then printf '0'; else printf '%s\n' "$1" | grep -c .; fi; }
CRIT_N=$(count_lines "$CRITIQUES")
HALT_N=$(count_lines "$HALTS")
WO_N=$(count_lines "$WOS")
set_ev work_orders "$WO_N"
set_ev work_order_critiques "$CRIT_N"
set_ev halt_markers "$HALT_N"

if [ "$CRIT_N" -gt 0 ]; then
  BUILD_PATH="work-orders"
  BLOCKED='[]'
  UNREADABLE='[]'
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # `// ` cannot be used to default this: jq treats `false` as null-ish, so
    # `.blocking // "absent"` reports every clean critique as unevaluated.
    B=$(jq -r 'if has("blocking") then (.blocking | tostring) else "absent" end' "$f" 2>/dev/null || printf 'absent')
    case "$B" in
      true)  BLOCKED=$(jq -c --arg n "$(basename "$f")" '. + [$n]' <<<"$BLOCKED") ;;
      false) ;;
      # An absent, null or unparseable `blocking` is `not_evaluated`, which
      # references/critique-envelope.md treats as blocking. A critique that did not evaluate
      # cleared nothing.
      *)     UNREADABLE=$(jq -c --arg n "$(basename "$f")" '. + [$n]' <<<"$UNREADABLE") ;;
    esac
  done <<< "$CRITIQUES"
  set_ev blocking_work_orders "$BLOCKED"
  set_ev unevaluated_work_orders "$UNREADABLE"

  if [ "$HALT_N" -gt 0 ]; then
    add_msg "$HALT_N work-order HALT marker(s) present, so a critique blocked and was never resolved"
    emit fail false "" 1
  fi
  if [ "$(jq -r 'length' <<<"$BLOCKED")" -gt 0 ]; then
    add_msg "blocking work-order critique(s): $(jq -r 'join(", ")' <<<"$BLOCKED")"
    emit fail false "" 1
  fi
  if [ "$(jq -r 'length' <<<"$UNREADABLE")" -gt 0 ]; then
    add_msg "work-order critique(s) with no evaluated blocking field: $(jq -r 'join(", ")' <<<"$UNREADABLE")"
    emit fail true "" 1
  fi
  # ---------------------------------------- the delegated path owes a TDD record too (v5.48.0+)
  #
  # Until this version `tdd` was demanded of `_build-critique.json` and of nothing else, so a
  # /run-work-orders build satisfied this gate on its critique files alone and owed no statement
  # about whether any test was watched failing before the code existed. The rung that enforces
  # test-first was reachable only on the path where the main context does the building, while
  # the orchestration rules route real builds to delegated agents. Measured on a live build:
  # three components built, reviewed and merged with no TDD record of any kind, every downstream
  # check satisfied, because each one reads a record nobody was asked to write.
  #
  # The unit of the record is the WORK-ORDER, not the phase. A delegated builder returns one and
  # the loop collects it into `wo-NN.run.json` via wo-run-state.sh; the orchestrator aggregates
  # rather than authoring on the builder's behalf. Absence is `unresolved`, the same answer the
  # in-session branch gives a record with no `tdd` key: nobody looked is not nothing was wrong.
  # THE SUBJECT SET IS THE WORK-ORDERS, NOT THE CRITIQUE FILES. The first cut of this block
  # iterated `$CRITIQUES`, so a compiled work-order carrying no `wo-NN._critique.json` was never
  # examined at all. Measured on a three-work-order fixture, one critiqued and two with nothing
  # on disk beside their `.md`: `verdict: pass`, `work_orders_without_tdd: []`, and the record's
  # own evidence saying `work_orders: 3`. A check whose subject set is the evidence it is looking
  # for cannot report the evidence missing.
  #
  # NOT EVERY COMPILED WORK-ORDER OWES A RECORD. One that was never dispatched built nothing, and
  # demanding a TDD statement of it would make the honest answer the expensive one. The rule is
  # decidable from disk and is a UNION on purpose:
  #
  #   owes a record IFF `wo-NN.run.json` exists,
  #                  OR `wo-NN._critique.json` exists,
  #                  OR the frontmatter `status:` is NOT one of `ready` / `blocked`
  #
  # The status half is stated as an EXCLUSION because the state machine in `wo-compile.sh`
  # (`blocked→ready→in_progress→{done,needs_rework}→ready`) has exactly two statuses a work-order
  # can hold without ever having been dispatched: `blocked` and `ready`. Every other status is
  # reached by the atom's own `ready→in_progress` flip, which happens BEFORE it mutates code. The
  # first cut named `done` alone, which excluded `in_progress` (the loop crashed after the flip)
  # and `needs_rework` (a failing verdict sent it back) -- both built something, and both were
  # skipped in silence rather than named. Listing the two that owe nothing cannot rot as the
  # enum grows; listing the three that owe something can.
  #
  # A run record means the loop dispatched it. A critique means it was BUILT: `wo-critic` reads a
  # diff and the gate envelopes, so it cannot have run over something nobody built. A status past
  # `ready` means the atom flipped it and started. Each of the three catches a lost-record shape
  # the others miss, which is why the subject set is their union and not any one of them. A
  # work-order matching none is one nobody dispatched, and it owes nothing: demanding a TDD
  # statement of a build that never happened makes the honest answer the expensive one.
  #
  # The critique disjunct was missing from the first cut of this rule, which is how a fixture
  # carrying a critique and no run record went from failing to passing without anyone choosing
  # that.
  #
  # THE ID SET IS THE UNION OF THREE GLOBS, NOT THE `.md` LIST. Iterating `wo-*.md` fixes the
  # original defect (a work-order with no critique was never examined) and opens its mirror: a
  # `wo-NN._critique.json` whose `.md` is gone becomes invisible, and the gate returns `pass` on a
  # record whose own evidence says one critic ran and zero work-orders owed anything. Measured:
  # `work_orders: 0, work_order_critiques: 1, work_orders_owing_tdd: 0, verdict: pass`. A subject
  # set drawn from ONE artifact can always be emptied by deleting that artifact, so it is drawn
  # from all three that name a work-order.
  WO_NO_TDD='[]'
  WO_BAD_TDD='[]'
  WO_TDD_SUBJECTS=0
  WO_IDS=$( { printf '%s\n' "$WOS" | sed -n 's#.*/\(wo-[^/]*\)\.md$#\1#p'
              find "$WO_DIR" -maxdepth 1 -name 'wo-*.run.json' -type f 2>/dev/null \
                | sed -n 's#.*/\(wo-[^/]*\)\.run\.json$#\1#p'
              printf '%s\n' "$CRITIQUES" | sed -n 's#.*/\(wo-[^/]*\)\._critique\.json$#\1#p'
            } | grep . | sort -u )
  while IFS= read -r WO_ID; do
    [ -z "$WO_ID" ] && continue
    f="$WO_DIR/$WO_ID.md"
    RUN_JSON="$WO_DIR/$WO_ID.run.json"
    WO_ST=""
    [ -f "$f" ] && WO_ST=$(wo_frontmatter_status "$f")
    if [ ! -f "$RUN_JSON" ] \
       && [ ! -f "$WO_DIR/$WO_ID._critique.json" ] \
       && { [ -z "$WO_ST" ] || [ "$WO_ST" = "ready" ] || [ "$WO_ST" = "blocked" ]; }; then
      continue
    fi
    WO_TDD_SUBJECTS=$((WO_TDD_SUBJECTS + 1))
    if [ ! -f "$RUN_JSON" ] || ! jq -e 'has("tdd")' "$RUN_JSON" >/dev/null 2>&1; then
      WO_NO_TDD=$(jq -c --arg n "$WO_ID" '. + [$n]' <<<"$WO_NO_TDD")
      continue
    fi
    # ONE JUDGE, TWO PATHS. `tdd_block_problems` is the same function the in-session branch
    # blocks on above, so this record either satisfies both paths or neither. The comment this
    # replaces claimed that property while the code checked four has() calls and nothing else,
    # and a block with `passed_first_run: 5` and no reason passed here and failed there.
    WO_TDD_PROBLEMS=$(tdd_block_problems "$(jq -c '.tdd' "$RUN_JSON" 2>/dev/null || printf 'null')")
    if [ "$WO_TDD_PROBLEMS" = "$JQ_ERR" ]; then
      WO_TDD_PROBLEMS='["the tdd block could not be read"]'
    fi
    if [ "$(jq -r 'length' <<<"$WO_TDD_PROBLEMS")" -gt 0 ]; then
      WO_BAD_TDD=$(jq -c --arg n "$WO_ID" --argjson p "$WO_TDD_PROBLEMS" \
        '. + [{work_order:$n, problems:$p}]' <<<"$WO_BAD_TDD")
    fi
  done <<< "$WO_IDS"
  # Both keys are set unconditionally. An evidence key that appears only on failure cannot be
  # read as "checked and clean", and `work_orders_owing_tdd` is here so a reader can tell an
  # empty list that means nothing was wrong from one that means nothing was a subject.
  set_ev work_orders_owing_tdd "$WO_TDD_SUBJECTS"
  set_ev work_orders_without_tdd "$WO_NO_TDD"
  set_ev work_orders_bad_tdd "$WO_BAD_TDD"
  if [ "$(jq -r 'length' <<<"$WO_NO_TDD")" -gt 0 ]; then
    add_msg "work-order(s) with no tdd block in their run record: $(jq -r 'join(", ")' <<<"$WO_NO_TDD")"
    add_msg "a delegated build owes the same statement an in-session build owes: what was watched failing before the code existed, and what was not"
    emit fail true "" 1
  fi
  if [ "$(jq -r 'length' <<<"$WO_BAD_TDD")" -gt 0 ]; then
    add_msg "work-order tdd block(s) the in-session branch would also refuse: $(jq -r '[.[] | .work_order + " (" + (.problems | join("; ")) + ")"] | join(", ")' <<<"$WO_BAD_TDD")"
    emit fail true "" 1
  fi

  add_msg "the build was challenged through /run-work-orders: $CRIT_N work-order critique(s), none blocking"
  emit pass false "" 0
fi

if [ "$WO_N" -gt 0 ]; then
  BUILD_PATH="work-orders"
  add_msg "$WO_N compiled work-order(s) and no wo-NN._critique.json for any of them, so no work-order was challenged"
  add_msg "run /ai-dev-assistant:run-work-orders, or build in-session so the /implement build-critique rung writes _build-critique.json"
  emit fail true "" 1
fi

if [ "$CHANGE_SET_EMPTY" = "1" ]; then
  # Nothing changed anywhere, so there was nothing for a critic to look at. This is the one
  # benign absence, and it is the caller's finding, not a guess made here.
  add_msg "no changes anywhere in the change set, so there was nothing to critique"
  emit skipped false "" 0
fi

add_msg "no build-critique record and no work-order critique, so nothing outside the builder ever looked at this build"
add_msg "re-run the /implement build-critique rung, or record an explicit bypass_reason in _build-critique.json"
emit fail true "" 1
