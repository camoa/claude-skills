#!/usr/bin/env bash
# ledger-index.sh — index the project's own task record as a prior-art search corpus.
#
# The cheap half of internal prior art. Every task this framework completes already states, in plain
# language and at capability altitude, what it built. That corpus is the thing that answers "have we
# already solved this?" — and until now nothing ever read it back.
#
# Usage: ledger-index.sh <project_folder>
#
# Scans <project_folder>/implementation_process/{completed,in_progress}/, plus one level of epic
# children (<epic>/{completed,in_progress}/<child>/). Per task, takes the capability statement from
# alignment.md (via alignment-read.sh, never a second parser) and falls back to task.md's Goal.
#
# Emits ONE JSON object to stdout:
#   { tasks: [ { name, state, path, goal, expected_result, criteria[], recommendation,
#                components[], pending_duplicate, source, truncated } ],
#     counts: { completed, in_progress, total },
#     warnings: [ ... ] }
#
# Defensive posture, copied from project-state-read.sh: ALWAYS emits JSON, ALWAYS exits 0 on a
# recoverable state, and every problem surfaces in warnings[]. Zero tasks found is a warning, not a
# failure — upstream turns it into a skip_reason. A kernel that cannot say "there was nothing to
# search" honestly is how a fabricated clean result gets made.
#
# Untrusted input: task folder names and file contents are attacker-writable in any repo that takes
# contributions. Names are never shell-evaluated; every value reaches JSON through jq --arg.
#
# Token economy: this emits a per-task SUMMARY, never file contents. Goals are capped and truncation
# is flagged, so the orchestrator's context cost stays flat as the ledger grows.
set -uo pipefail

GOAL_MAX=600

PROJECT_DIR=""
WITH_CRITERIA=false
MATCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --with-criteria) WITH_CRITERIA=true ;;
    --match) MATCH="${2:-}"; shift ;;
    -*) : ;;                       # unknown flags are ignored, never fatal
    *)  [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$1" ;;
  esac
  shift
done
SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
ALIGNMENT_READ_SH="$SCRIPT_DIR/alignment-read.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/fm-helpers.sh"

WARNINGS='[]'
add_warn(){ WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS"); }

emit(){ # emit <tasks-json> [total_before_filter]
  jq -n --argjson tasks "$1" --argjson warnings "$WARNINGS" \
        --arg filter "$MATCH" --argjson before "${2:-0}" \
    '{
       schema_version: "1.0",
       filter: (if $filter == "" then null else $filter end),
       tasks: $tasks,
       counts: {
         completed:   ($tasks | map(select(.state == "completed"))   | length),
         in_progress: ($tasks | map(select(.state == "in_progress")) | length),
         total:       ($tasks | length),
         total_before_filter: $before
       },
       warnings: $warnings
     }'
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  printf '{"schema_version":"1.0","tasks":[],"counts":{"completed":0,"in_progress":0,"total":0},"warnings":["jq_missing"]}\n'
  exit 0
fi

if [ -z "$PROJECT_DIR" ]; then add_warn "no_project_folder_given"; emit '[]'; fi
if [ ! -d "$PROJECT_DIR" ]; then add_warn "project_folder_not_found:$PROJECT_DIR"; emit '[]'; fi

IP_DIR="$PROJECT_DIR/implementation_process"
if [ ! -d "$IP_DIR" ]; then
  add_warn "implementation_process_not_a_directory"
  emit '[]'
fi

# section_body and first_para now live in fm-helpers.sh (sourced above) — moved from here so
# stub-detect.sh's stub_verdict shares the same extractor instead of a third copy being written.

# json1 <varname> <task-name> — true when the named variable holds EXACTLY ONE valid JSON
# document. Guards every --argjson value. `jq empty` alone is not enough: it accepts an
# empty string, and it accepts a stream of several documents, both of which --argjson
# rejects. A failure here is warned about, never swallowed.
json1(){
  local vn="$1" tn="$2" v
  eval "v=\$$vn"
  [ -n "$v" ] || { add_warn "empty_json_fragment:$tn.$vn"; return 1; }
  [ "$(jq -s 'length' 2>/dev/null <<<"$v")" = "1" ] || { add_warn "malformed_json_fragment:$tn.$vn"; return 1; }
  return 0
}

index_task(){ # index_task <task_dir> <state>
  local d="$1" state="$2"
  local name; name="$(basename "$d")"
  [ -f "$d/task.md" ] || return 0

  local goal="" expected="" criteria='[]' source="" truncated=false stub=false
  local recommendation="" components='[]' pending=""

  # Capability statement: alignment.md via the existing reader, never a second parser.
  if [ -f "$d/alignment.md" ] && [ -x "$ALIGNMENT_READ_SH" ]; then
    local ar; ar="$(bash "$ALIGNMENT_READ_SH" "$d" 2>/dev/null)"
    if jq -e . >/dev/null 2>&1 <<<"$ar"; then
      goal="$(jq -r '.sections.task_level.goal // ""' <<<"$ar")"
      expected="$(jq -r '.sections.task_level.expected_result // ""' <<<"$ar")"
      criteria="$(jq -c '[.sections.task_level.success_criteria[]?.text] // []' <<<"$ar" 2>/dev/null || printf '[]')"
      [ -n "$goal" ] && source="alignment.md"
    else
      add_warn "alignment_unreadable:$name"
    fi
  fi

  # Fallback: task.md's Goal. A task without a contract must still enter the corpus.
  if [ -z "$goal" ]; then
    goal="$(first_para "$(section_body "$d/task.md" '^##+ goal')")"
    [ -n "$goal" ] && source="task.md"
  fi
  [ -z "$goal" ] && { goal=""; source="none"; add_warn "no_goal:$name"; }

  # Optional enrichment, both cheap and both allowed to be absent.
  if [ -f "$d/research.md" ]; then
    recommendation="$(first_para "$(section_body "$d/research.md" '^##+ recommendation')")"
  fi
  if [ -f "$d/architecture.md" ]; then
    # NEVER use `pipeline || fallback` under `set -o pipefail`: a grep that matches
    # nothing makes the whole pipeline exit non-zero even when the final jq SUCCEEDED,
    # so the fallback fires ON TOP of the good value and the variable ends up holding
    # two JSON documents. --argjson then rejects it and the task vanishes silently.
    # Capture first, test the captured text, never the pipeline's status.
    local rows
    rows="$(grep -hoE '^\| [0-9]+ \| `[^`]+`' "$d/architecture.md" 2>/dev/null | sed -E 's/.*`([^`]+)`.*/\1/' | head -20)" || rows=""
    if [ -n "$rows" ]; then
      components="$(printf '%s\n' "$rows" | jq -R . | jq -sc . 2>/dev/null)"
    fi
  fi
  # Fail-safe: whatever happened above, these MUST be exactly one JSON document or the
  # task is dropped by --argjson. A drop is always recorded, never silent.
  json1 components "$name" || components='[]'
  json1 criteria   "$name" || criteria='[]' 

  # Pending-duplicate marker: what stops the NEXT task adding a third implementation.
  pending="$(grep -m1 -E '^\*\*Pending duplicate:\*\*' "$d/task.md" 2>/dev/null \
    | sed -E 's/^\*\*Pending duplicate:\*\*[[:space:]]*//' | sed -e 's/[[:space:]]*$//')"

  # A stub goal is framework scaffold text, not a capability. It is IDENTICAL across every
  # task that never got scoped, so an unmarked stub matches everything — worse than matching
  # nothing. Mark it and index it; the search filters on the flag.
  case "$goal" in
    *"To be authored via"*|*"to be defined"*|*"_stub_"*|*"TBD"*) stub=true ;;
  esac
  [ -z "$goal" ] && stub=true

  # Token economy: summarise, never inline.
  if [ "${#goal}" -gt "$GOAL_MAX" ]; then
    goal="${goal:0:$GOAL_MAX}"
    truncated=true
  fi

  jq -n --arg name "$name" --arg state "$state" --arg path "$d" \
        --arg goal "$goal" --arg expected "$expected" --argjson criteria "$criteria" \
        --arg recommendation "$recommendation" --argjson components "$components" \
        --arg pending "$pending" --arg source "$source" --argjson truncated "$truncated" \
        --argjson stub "$stub" --argjson withcrit "$WITH_CRITERIA" \
    '{name:$name, state:$state, path:$path, goal:$goal, stub:$stub,
      expected_result:(if $expected=="" then null else $expected end)}
     + (if $withcrit then {criteria:$criteria} else {} end)
     + {
      recommendation:(if $recommendation=="" then null else $recommendation end),
      components:$components,
      pending_duplicate:(if $pending=="" then null else $pending end),
      source:$source, truncated:$truncated}'
}

TASKS='[]'
append_task(){ # append_task <task-json> <task-name>
  if [ -z "$1" ] || [ "$(jq -s 'length' 2>/dev/null <<<"$1")" != "1" ]; then
    add_warn "task_dropped:${2:-unknown}"   # loud, always. a silent drop is a false clean.
    return 0
  fi
  TASKS=$(jq -c --argjson t "$1" '. + [$t]' <<<"$TASKS")
}

scan_state_dir(){ # scan_state_dir <dir> <state> <allow_epic_descent>
  local dir="$1" state="$2" descend="$3"
  [ -d "$dir" ] || return 0
  local d
  # -print0 + read -d '' so a name with whitespace or metacharacters is one literal value.
  while IFS= read -r -d '' d; do
    if [ -f "$d/task.md" ]; then
      append_task "$(index_task "$d" "$state")" "$(basename "$d")"
    elif [ "$descend" = "yes" ] && [ -d "$d/implementation_process" ]; then
      scan_state_dir "$d/implementation_process/completed"   completed   no
      scan_state_dir "$d/implementation_process/in_progress" in_progress no
    elif [ "$descend" = "yes" ]; then
      # Epic folder shape: <epic>/{completed,in_progress}/<child>/
      scan_state_dir "$d/completed"   completed   no
      scan_state_dir "$d/in_progress" in_progress no
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
}

scan_state_dir "$IP_DIR/completed"   completed   yes
scan_state_dir "$IP_DIR/in_progress" in_progress yes

# Stable ordering so two runs over one tree are byte-identical and diffable.
TASKS=$(jq -c 'sort_by(.name)' <<<"$TASKS")

TOTAL_BEFORE=$(jq -r 'length' <<<"$TASKS")
[ "$TOTAL_BEFORE" = "0" ] && add_warn "no_tasks_found"

# Aspect filter, applied HERE rather than by the reader. By the time a reader could filter, it has
# already paid for every task in context — which is the cost this exists to bound. A stub goal is
# never matchable: its scaffold text is identical across every unscoped task, so matching it would
# pull in unrelated work.
if [ -n "$MATCH" ]; then
  TASKS=$(jq -c --arg m "$MATCH" '
    [ .[] | select(.stub != true)
          | select( ((.goal // "") + " " + (.expected_result // "") + " " + (.recommendation // ""))
                    | ascii_downcase | contains($m | ascii_downcase) ) ]' <<<"$TASKS")
  [ "$(jq -r 'length' <<<"$TASKS")" = "0" ] && add_warn "filter_matched_nothing:$MATCH"
fi

emit "$TASKS" "$TOTAL_BEFORE"
