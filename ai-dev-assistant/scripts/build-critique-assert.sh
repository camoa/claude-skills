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
  UNOBS=$(jq -c '(.unobserved // [])' <<<"$TDD")
  UNOBS_N=$(jq -r 'length' <<<"$UNOBS")
  TDD_REASON=$(jq -r '(.reason // "") | tostring' <<<"$TDD")
  [ "$TDD_REASON" = "null" ] && TDD_REASON=""
  set_ev tdd "$TDD"

  if [ "$RED_N" = "-1" ] || [ "$FIRSTRUN_N" = "-1" ] || ! jq -e 'has("unobserved")' <<<"$TDD" >/dev/null 2>&1; then
    add_msg "the tdd block omits red_observed, passed_first_run or unobserved[], so it cannot say what it did not watch"
    emit fail true "" 1
  fi

  if [ "$FIRSTRUN_N" -gt 0 ] && [ -z "$TDD_REASON" ]; then
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

  if [ "$UNOBS_N" -gt 0 ] && [ -z "$TDD_REASON" ]; then
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

  # ------------------------------------------------ the round budget (v5.35.0+)
  #
  # The rung can loop forever and nothing noticed. Live: one component took FOUR blocking
  # rounds, and rounds 2 and 3 were both caused by the repair that preceded them. Each round
  # was individually correct -- critics found real defects, the builder fixed them -- while the
  # sequence as a whole was not converging, and no artifact said so. The builder asked the
  # human whether to keep going, which is the right instinct arriving from nowhere: no rule
  # told it to, and in an unattended run there is nobody to ask.
  #
  # This does not cap quality or forbid a fifth round. It caps UNSUPERVISED iteration: past the
  # threshold, continuing is a decision somebody made and recorded, not a default. The builder
  # that has been wrong three times running is the least reliable judge of whether the fourth
  # attempt is different, which is the same reason the rung exists at all.
  # Two, not three. Measured on the run that produced this check: rounds 1 and 2 found real
  # behavioural defects no test could have caught. Rounds 3, 4 and 5 produced 58 findings and
  # not one of them concerned a defect that pre-existed the round-1 and round-2 repairs. The
  # value is front-loaded; the tail is the loop auditing its own repairs.
  ROUND_LIMIT=2
  # `rounds` must be a number to be compared. jq orders every string above every number, so a
  # bare `>=` reports `rounds: "3"` -- and `rounds: "a"` -- as over budget, and the message would
  # then claim rounds that never happened. A count that is not a number is a malformed record,
  # not a high one; it is caught here and named as such.
  BADROUNDS=$(jq -c \
    '[(.components // [])[] | select(has("rounds") and (.rounds != null) and ((.rounds | type) != "number")) | (.component // "unnamed")]' \
    <<<"$PAYLOAD" 2>/dev/null) || BADROUNDS='[]'
  if [ "$(jq -r 'length' <<<"$BADROUNDS")" -gt 0 ]; then
    set_ev malformed_rounds "$BADROUNDS"
    add_msg "a component records a non-numeric rounds count, so how many times it was critiqued cannot be read"
    emit fail true "" 1
  fi
  OVERBUDGET=$(jq -c --argjson lim "$ROUND_LIMIT" \
    '[(.components // [])[] | select(((.rounds // 1) | if type == "number" then . else 1 end) >= $lim) | (.component // "unnamed")]' \
    <<<"$PAYLOAD" 2>/dev/null) || OVERBUDGET='[]'
  OVER_N=$(jq -r 'length' <<<"$OVERBUDGET")
  set_ev over_budget_components "$OVERBUDGET"
  if [ "$OVER_N" -gt 0 ]; then
    # Two places are legitimate, and the second is the one a live build actually produced:
    # a top-level `escalation.reason`, or a `resolution` on the round it settled. The
    # per-round form is better -- a decision belongs with the round that provoked it -- and
    # this check was written to demand the other one before anyone looked at a real record.
    ESC=$(jq -r '((.escalation.reason // "") | tostring) as $top
                 | if $top != "" then $top
                   else ([(.rounds // [])[] | (.resolution // empty) | tostring]
                         | map(select(. != "")) | last // "")
                   end' <<<"$PAYLOAD")
    [ "$ESC" = "null" ] && ESC=""
    if [ -z "$ESC" ]; then
      add_msg "$OVER_N component(s) reached $ROUND_LIMIT or more critique rounds with no escalation recorded; say who decided to keep going and why"
      emit fail true "" 1
    fi
    add_msg "$OVER_N component(s) ran to $ROUND_LIMIT or more rounds; continuing was a recorded decision: $ESC"
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
  # TOUCHED_FILES is `review-change-set.sh`'s own `.files`, read from `$CHANGE_SET_FILE` --
  # already required on this path (see build_identity below) -- independently of whether that
  # later block validates it, so this check does not depend on a later block's success.
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
    REF_SITES=$(jq -c \
      '[(.findings // [])[]?
        | select((.severity // "") == "critical" or (.severity // "") == "concern")
        | (.where // [])[]? | (.file // empty)]' \
      "$REF_PATH" 2>/dev/null) || REF_SITES='[]'
    FINDING_SITES=$(jq -c -n --argjson a "$FINDING_SITES" --argjson b "$REF_SITES" \
      '($a + $b) | unique' 2>/dev/null) || FINDING_SITES='[]'
  done < <(jq -r '.[] | (.critique_ref // "") | tostring' <<<"$FS_COMPONENTS" 2>/dev/null)

  TOUCHED_SOURCE="undetermined"
  TOUCHED_FILES='[]'
  if [ -n "$CHANGE_SET_FILE" ] && [ -f "$CHANGE_SET_FILE" ] \
     && jq -e 'type == "object"' "$CHANGE_SET_FILE" >/dev/null 2>&1; then
    TOUCHED_FILES=$(jq -c '(.files // [])' "$CHANGE_SET_FILE" 2>/dev/null) || TOUCHED_FILES='[]'
    TOUCHED_SOURCE="determined"
  fi

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
          add_msg "scope compliance: touched file(s) named by no finding: $SCOPE_UNNAMED -- surfaced, not blocking"
          ;;
        in_scope)
          add_msg "scope compliance: every touched file is named by a finding or covered by an allow rule"
          ;;
        cannot_judge)
          if [ "$(jq -r 'length' <<<"$FINDING_SITES")" -eq 0 ]; then
            add_msg "scope compliance could not be judged: no finding named a site"
          else
            add_msg "scope compliance could not be judged: the touched-file set could not be determined"
          fi
          ;;
        *) add_msg "scope compliance returned an unrecognised action: $SCOPE_ACTION" ;;
      esac
    else
      set_ev_s scope_compliance "unreadable"
      add_msg "scope compliance could not be computed: repair-scope-check.sh produced no readable verdict"
    fi
  else
    set_ev_s scope_compliance "unavailable"
    add_msg "scope compliance could not be computed: repair-scope-check.sh not found"
  fi

  ROUNDS_ARR=$(jq -c '(.rounds // [])' <<<"$PAYLOAD" 2>/dev/null) || ROUNDS_ARR='[]'
  # A jq error on the deferral filter below must NOT read as "nothing found" -- it falls back
  # to this sentinel rather than to `[]`, and the sentinel is reported as unresolved.
  JQ_ERR="__jq_error__"

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
           | ((.finding // "unnamed") | tostring) ]' <<<"$ROUNDS_ARR" 2>/dev/null) || BAD_DEFERRALS="$JQ_ERR"
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
  DEFERRED_N=$(jq -r '[ .[] | (.deferred // []) | length ] | add // 0' <<<"$ROUNDS_ARR" 2>/dev/null) || DEFERRED_N=0
  if [ "$DEFERRED_N" -gt 0 ]; then
    set_ev deferred_findings "$DEFERRED_N"
    add_msg "$DEFERRED_N finding(s) deferred to a component not yet built; they carry forward rather than being answered speculatively"
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
