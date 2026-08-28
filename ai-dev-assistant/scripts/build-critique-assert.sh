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
# Usage: build-critique-assert.sh <task_folder> [--change-set-empty]
#
#   --change-set-empty  the caller resolved an empty change set (`/review` step 4's
#                       `empty_reason: no_changes_anywhere`). Only consulted when there is no
#                       record at all: nothing changed, so there was nothing to critique.
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
shift 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --change-set-empty) CHANGE_SET_EMPTY=1 ;;
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

  DECLARED=$(jq -r '(.components_declared // -1)' <<<"$PAYLOAD")
  CRITIQUED=$(jq -r '(.components_critiqued // -1)' <<<"$PAYLOAD")
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
    add_msg "$CRITIQUED of $DECLARED component(s) critiqued; $UNCRIT_N left uncritiqued with reasons"
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
  ROUND_LIMIT=3
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
  CON_BASE=$(jq -r '(.baseline // "") | tostring' <<<"$CON")
  CON_CHANGED=$(jq -c '(.changed // [])' <<<"$CON")
  CON_N=$(jq -r 'length' <<<"$CON_CHANGED")
  CON_REASON=$(jq -r '(.reason // "") | tostring' <<<"$CON")
  [ "$CON_REASON" = "null" ] && CON_REASON=""
  set_ev contract "$CON"

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
