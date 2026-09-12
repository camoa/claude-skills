#!/usr/bin/env bash
# research-actions.sh: the deterministic half of the research skill (ideal/research.md).
#
# The skill body holds the conversation: which searches to run, what to dispatch an agent to
# look for, and when enough has been found to stop. This script never searches anything and
# never judges a finding. Every fact it needs arrives already decided, as an argument, the same
# split scope-actions.sh and tool-actions.sh use. It writes one file per search under
# <task_folder>/research/, mints nothing (a finding carries no id of its own), renders that
# file's markdown, and runs the coverage check. Deciding whether research is done belongs to
# whoever calls this, never to this script.
#
# What reaches stdout is what reaches the orchestrator's context. Every action prints `key: value`
# summary lines and the paths it wrote, and never a record body or a finding's text. `check`
# writes check-research.sh's report to <task_folder>/research-check.json and prints its status,
# its line count and that path.
#
# Usage:
#   research-actions.sh read   <task_folder>
#   research-actions.sh start  <task_folder>
#   research-actions.sh record <task_folder> \
#                          --search <slug> --searched-for <text> --text <text> \
#                          --source <text> [--criteria-served <id[,id...]>]
#   research-actions.sh check  <task_folder>
#
# Depends on, shipped by the same part and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/research-render.sh   called by `record`, unmodified
#   ${CLAUDE_PLUGIN_ROOT}/scripts/check-research.sh    called by `check`, unmodified
#
# This script never runs the schema comparison itself. Every field it writes is validated before
# the write, so what it produces is shaped correctly by construction; a stale or hand-edited
# research file already on disk before this script's first call on a search is a fact
# check-research.sh reports, not one this script repairs.
#
# A research file is plain JSON at <task_folder>/research/<search>.json: no fences, no markdown
# (scripts/research-schema.json). Its fields are schemaVersion, search, searchedFor and
# findings; a finding
# holds text, source, lookedAt and criteriaServed. `record` writes that JSON, then renders
# <search>.md from it by calling research-render.sh, the same way scope-actions.sh writes
# alignment.json and then calls alignment-render.sh. Nothing reads <search>.md back: it is for
# the design stage to read, and it says so on itself.
#
# `criteriaServed` holds ids scope minted in alignment.json, not criterion text (ideal/scope.md,
# 'Why the id exists'; ideal/research.md, 'What a finding holds'). This script checks only that
# each id given has the shape of a criterion id, c<n> with no leading zero; whether that id
# actually names a criterion in this task's own contract is check-research.sh's job, listed in
# its own header, and is not repeated here.
#
# `lookedAt` is never taken as an argument. It is stamped by this script, as today's UTC date, at
# the moment a finding is recorded, the same way registry.sh stamps `lastAccessed`. A date typed
# by hand is a date that can be typed wrong or left stale; the finding's true date is the moment
# it was written down.
#
# Exit codes, each one and only one meaning:
#   0  did what was asked. For `read`, this includes an honest report that no contract exists yet
#      and that no research has started yet. For `check`, this is check-research.sh's own exit 0.
#   1  the given path does not exist, is not a folder, or holds no task.json: not a task folder
#      (ideal/scope.md, 'Scope runs against a task that already exists', the same rule a task
#      part applies to every stage that runs against one). This is the only meaning of exit 1
#      from this script, for every action, `check` included: check-research.sh's own exit 1
#      means something else, a research file is malformed, and it is remapped to 4 below so a
#      caller branching on 1 never confuses "not a task folder" with "a file is broken".
#   2  the target of this action is not present: `start` was asked to begin a task with no
#      alignment.json, or with one that will not parse or is not a contract (an object carrying
#      schemaVersion, goal, expectedResult, and criteria/nonGoals as arrays). Research reads the
#      contract's criteria to know what it is answering for (ideal/research.md, 'The criteria are
#      what stops research'), so it refuses to start without one rather than starting blind.
#   3  the script could not do its job: a missing, blank or malformed argument; an argument value
#      that is itself another option; a `--search` that is not lowercase letters, digits and
#      single hyphens; a `--criteria-served` entry that is not a valid criterion id shape; a
#      research file already on disk that is not valid JSON or is not a JSON object; a research
#      file already on disk whose searchedFor is absent, empty, not a string, or a different set
#      of words from the one this call gives (one search records one set of words, and this
#      script never rewrites the field on a file that already exists); the plugin
#      root could not be resolved; a write that failed; `record`'s own call to research-render.sh
#      failing to produce <search>.md; or `check`'s own call to check-research.sh failing to run
#      at all (check-research.sh's own exit 3, meaning it could not do its job either).
#   4  `check` ran and found a research file that cannot be read as this format: not valid JSON,
#      not an object, or a missing, malformed or unknown top-level field (check-research.sh's own
#      exit 1, remapped here so it never collides with this script's own exit 1, "not a task
#      folder").
#   5  `check` ran, every research file reads fine, but the coverage itself has a problem: a
#      criterion with no finding, a finding with no criterion, or a criteriaServed id naming no
#      criterion in the contract (check-research.sh's own exit 4).
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no regular
# expression interval quantifier anywhere, the same rule scope-actions.sh and check-alignment.sh
# state for the same reason (foundations.md, Honesty). An id's own shape is checked with a `case`
# glob (`c[1-9][0-9]*`), never a regular expression, the same way scope-actions.sh checks one.

set -uo pipefail  # not -e: several branches test a command's exit code on purpose.

if [ -n "${ZSH_VERSION:-}" ]; then
  setopt KSH_ARRAYS 2>/dev/null
fi

if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="$0"
else
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd -- "$(dirname -- "$SCRIPT_SOURCE")/../../.." >/dev/null 2>&1 && pwd -P)}"
if [ -z "$PLUGIN_ROOT" ] || [ ! -d "$PLUGIN_ROOT" ]; then
  printf 'research-actions: could not resolve the plugin root (CLAUDE_PLUGIN_ROOT is not set and the script'"'"'s own location could not be resolved)\n' >&2
  exit 3
fi
RESEARCH_RENDER_SCRIPT="${PLUGIN_ROOT}/scripts/research-render.sh"
CHECK_RESEARCH_SCRIPT="${PLUGIN_ROOT}/scripts/check-research.sh"

command -v jq >/dev/null 2>&1 || { printf 'research-actions: jq is required and was not found on PATH\n' >&2; exit 3; }

die1() { printf 'research-actions: %s\n' "$1" >&2; exit 1; }
die2() { printf 'research-actions: %s\n' "$1" >&2; exit 2; }
die3() { printf 'research-actions: %s\n' "$1" >&2; exit 3; }

usage() {
  cat <<'EOF' >&2
usage: research-actions.sh read   <task_folder>
       research-actions.sh start  <task_folder>
       research-actions.sh record <task_folder> --search <slug> --searched-for <text> \
                                   --text <text> --source <text> \
                                   [--criteria-served <id[,id...]>]
       research-actions.sh check  <task_folder>
EOF
}

# The four helpers every stage script needs before it touches a task folder live in one place
# (scripts/lib/task-helpers.sh): resolve_task_folder, looks_like_flag, is_blank, write_atomic.
TASK_HELPERS_LIB="${PLUGIN_ROOT}/scripts/lib/task-helpers.sh"
[ -f "$TASK_HELPERS_LIB" ] || die3 "cannot find the task-helper library at $TASK_HELPERS_LIB"
# shellcheck source=/dev/null
source "$TASK_HELPERS_LIB" || die3 "the task-helper library failed to load: $TASK_HELPERS_LIB"

# Prints "true" when the contract at $ALIGNMENT_FILE exists, is readable, parses as JSON, and is
# shaped like a contract (an object carrying schemaVersion, goal, expectedResult, and
# criteria/nonGoals as arrays). Prints "false" otherwise. Never dies: `read` uses this to report
# an honest state rather than fail, and `start` uses it to decide whether to refuse.
contract_ok() {
  [ -f "$ALIGNMENT_FILE" ] || { printf 'false'; return; }
  [ -r "$ALIGNMENT_FILE" ] || { printf 'false'; return; }
  jq empty "$ALIGNMENT_FILE" 2>/dev/null || { printf 'false'; return; }
  local shape
  shape="$(jq -r '
      if type != "object" then "no"
      elif (has("schemaVersion") | not) then "no"
      elif (has("goal") | not) then "no"
      elif (has("expectedResult") | not) then "no"
      elif ((.criteria | type) != "array") then "no"
      elif ((.nonGoals | type) != "array") then "no"
      else "yes"
      end
    ' "$ALIGNMENT_FILE" 2>/dev/null)"
  if [ "$shape" = "yes" ]; then printf 'true'; else printf 'false'; fi
}

# The criteria list from the contract, as [{id, text}], or "[]" when the contract cannot be read.
contract_criteria_json() {
  if [ "$(contract_ok)" != "true" ]; then
    printf '[]'
    return
  fi
  jq -c '[ (.criteria // [])[]? | {id: .id, text: .text, author: .author} ]' "$ALIGNMENT_FILE" 2>/dev/null || printf '[]'
}

# True (exit 0) when $1 is a valid criterion id shape, c<n> with no leading zero. The same case
# glob idiom scope-actions.sh uses for the same reason: a glob's `*` is not a regex `*`, so the
# digits are checked as their own string once the prefix is stripped.
is_criterion_id() {
  local id="$1" num
  case "$id" in
    c*) : ;;
    *) return 1 ;;
  esac
  num="${id#?}"
  case "$num" in
    ''|0*|*[!0-9]*) return 1 ;;
  esac
  return 0
}

# ------------------------------------------------------------------------------------------------
# read: the current state, never a failure just because nothing has run yet.
# ------------------------------------------------------------------------------------------------

do_read() {
  [ "$#" -eq 0 ] || die3 "read: unrecognized argument: $1"

  # Summary lines only. The skill routes on `contract:`, on `criteria-by-designer:` and on the
  # `search:` lines, and reads a file from its printed path when it needs the findings.
  local criteria_json contract_state research_state file_count decided f count
  criteria_json="$(contract_criteria_json)"
  contract_state="absent"
  [ "$(contract_ok)" = "true" ] && contract_state="present"
  decided="$(jq -r '(.decidedWithoutAPerson // []) | length' "$ALIGNMENT_FILE" 2>/dev/null)"
  [ -n "$decided" ] || decided=0
  echo "action: read"
  echo "task: $TASK_PATH"
  echo "contract: $contract_state"
  echo "contract-file: $ALIGNMENT_FILE"
  echo "criteria: $(printf '%s' "$criteria_json" | jq -r '[.[].id] | join(" ")')"
  echo "criteria-by-designer: $(printf '%s' "$criteria_json" | jq -r '[.[] | select(.author == "designer") | .id] | join(" ")')"
  echo "decided-without-a-person: $decided"

  research_state="not started"
  file_count=0
  if [ -d "$RESEARCH_DIR" ]; then
    research_state="started"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      count="$(jq -r 'if type == "object" then ((.findings // []) | length) else empty end' "$f" 2>/dev/null)"
      if [ -n "$count" ]; then
        file_count=$((file_count + 1))
        echo "search: $f findings=$count"
      else
        echo "unreadable: $f"
      fi
    done < <(find "$RESEARCH_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
  fi
  echo "research: $research_state"
  echo "research-dir: $RESEARCH_DIR"
  echo "searches: $file_count"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# start: makes sure the contract exists before research begins, and makes sure the research
# folder exists. Idempotent: running it again on a task already started changes nothing and is
# not refused, unlike scope's `init`, because no aggregate file here could be overwritten by a
# second call. Prints the ids of the criteria the conversation is answering for.
# ------------------------------------------------------------------------------------------------

do_start() {
  [ "$#" -eq 0 ] || die3 "start: unrecognized argument: $1"

  [ "$(contract_ok)" = "true" ] \
    || die2 "start: $ALIGNMENT_FILE not found, unreadable, or not a contract. Run the scope skill on this task first"

  mkdir -p "$RESEARCH_DIR" || die3 "start: could not create $RESEARCH_DIR"

  echo "STARTED: $RESEARCH_DIR"
  echo "contract-file: $ALIGNMENT_FILE"
  echo "criteria: $(contract_criteria_json | jq -r '[.[].id] | join(" ")')"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# record: appends one finding to <task_folder>/research/<search>.json, creating the file when it
# does not already exist, then renders <search>.md from it by calling research-render.sh.
# ------------------------------------------------------------------------------------------------

do_record() {
  local search="" searched_for="" text="" source_val="" criteria_served=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --search)
        [ $# -ge 2 ] || die3 "record: --search needs a value"
        looks_like_flag "$2" && die3 "record: --search needs a value, got the option $2 instead"
        search="$2"; shift 2 ;;
      --searched-for)
        [ $# -ge 2 ] || die3 "record: --searched-for needs a value"
        looks_like_flag "$2" && die3 "record: --searched-for needs a value, got the option $2 instead"
        searched_for="$2"; shift 2 ;;
      --text)
        [ $# -ge 2 ] || die3 "record: --text needs a value"
        looks_like_flag "$2" && die3 "record: --text needs a value, got the option $2 instead"
        text="$2"; shift 2 ;;
      --source)
        [ $# -ge 2 ] || die3 "record: --source needs a value"
        looks_like_flag "$2" && die3 "record: --source needs a value, got the option $2 instead"
        source_val="$2"; shift 2 ;;
      --criteria-served)
        [ $# -ge 2 ] || die3 "record: --criteria-served needs a value"
        looks_like_flag "$2" && die3 "record: --criteria-served needs a value, got the option $2 instead"
        criteria_served="$2"; shift 2 ;;
      *) die3 "record: unrecognized argument: $1" ;;
    esac
  done

  is_blank "$search" && die3 "record: --search is required and must not be blank"
  case "$search" in
    *[!a-z0-9-]*|-*|*-)
      die3 "record: --search must be lowercase letters, digits and single hyphens, got '$search'" ;;
  esac
  is_blank "$searched_for" && die3 "record: --searched-for is required and must not be blank. It holds the words this search searched for, and it is what bounds a finding that says nothing was found"
  is_blank "$text" && die3 "record: --text is required and must not be blank"
  is_blank "$source_val" && die3 "record: --source is required and must not be blank. Every finding names where it came from"

  # The list is split with tr and read line by line. An unquoted `for id in $list` under a comma
  # IFS splits in bash and not in zsh. zsh was handed the whole list as one id.
  local ids_json='[]'
  local id
  if [ -n "$criteria_served" ]; then
    while IFS= read -r id; do
      is_blank "$id" && die3 "record: --criteria-served has a blank id in '$criteria_served'"
      is_criterion_id "$id" \
        || die3 "record: --criteria-served id '$id' is not a valid criterion id shape (c<n>, no leading zero)"
      ids_json="$(printf '%s' "$ids_json" | jq --arg id "$id" '. + [$id]')"
    done < <(printf '%s\n' "$criteria_served" | tr ',' '\n')
  fi

  mkdir -p "$RESEARCH_DIR" || die3 "record: could not create $RESEARCH_DIR"

  local file="$RESEARCH_DIR/$search.json"
  local looked_at
  looked_at="$(date -u +%Y-%m-%d)"

  local finding_json
  finding_json="$(jq -n --arg text "$text" --arg source "$source_val" --arg lookedAt "$looked_at" \
      --argjson criteriaServed "$ids_json" \
      '{text: $text, source: $source, lookedAt: $lookedAt, criteriaServed: $criteriaServed}')"

  local doc
  if [ -f "$file" ]; then
    jq empty "$file" 2>/dev/null \
      || die3 "record: $file exists but is not valid JSON"
    # The search is the unit, so one search records one set of words. A broadened search is a
    # new search with its own name, not a widened record: merging the two would leave every
    # finding already in the file claiming a bound only some of them were found under. So this
    # script never writes searchedFor onto a file that already exists. It reads what is there and
    # refuses anything that does not match, and a missing field, an unreadable one, an empty one
    # and a conflicting one are four different facts with four different messages.
    local stored_type stored_searched_for
    stored_type="$(jq -r 'if has("searchedFor") then (.searchedFor | type) else "absent" end' "$file")"
    case "$stored_type" in
      string)
        stored_searched_for="$(jq -r '.searchedFor' "$file")"
        if [ -z "$stored_searched_for" ]; then
          die3 "record: $file records searchedFor as an empty string, so its findings state no bound. This script does not repair that: record this search again under a new --search name"
        fi
        if [ "$stored_searched_for" != "$searched_for" ]; then
          die3 "record: $file already records searchedFor as '$stored_searched_for', and this call gives '$searched_for'. One search records one set of words; give a new --search name for a different search"
        fi
        ;;
      absent)
        die3 "record: $file records no searchedFor at all, so the findings in it were found under a bound nobody wrote down. Stamping '$searched_for' on them here would claim a bound they were never found under; record this search again under a new --search name"
        ;;
      *)
        die3 "record: $file has a searchedFor that is a $stored_type, not a string. A field that cannot be read is not the same fact as one that is absent, and neither is repaired here; fix the file, or record this search again under a new --search name"
        ;;
    esac
    doc="$(jq --argjson f "$finding_json" '.findings = ((.findings // []) + [$f])' "$file")" \
      || die3 "record: could not add the new finding to $file"
  else
    doc="$(jq -n --arg search "$search" --arg searchedFor "$searched_for" --argjson f "$finding_json" \
        '{schemaVersion: 1, search: $search, searchedFor: $searchedFor, findings: [$f]}')"
  fi

  write_atomic "$file" "$doc"

  echo "RECORDED: $file"
  echo "search: $search"
  echo "criteriaServed: $(printf '%s' "$ids_json" | jq -r 'join(",")')"
  echo "findings: $(printf '%s' "$doc" | jq -r '.findings | length')"

  [ -f "$RESEARCH_RENDER_SCRIPT" ] \
    || die3 "record: cannot find research-render.sh at $RESEARCH_RENDER_SCRIPT"
  bash "$RESEARCH_RENDER_SCRIPT" "$TASK_PATH" "$search" >/dev/null
  local render_rc=$?
  [ "$render_rc" -eq 0 ] \
    || die3 "record: research-render.sh could not render $search.md (exit $render_rc)"
  echo "rendered: $RESEARCH_DIR/$search.md"

  exit 0
}

# ------------------------------------------------------------------------------------------------
# check: calls check-research.sh and remaps its exit code onto this script's own vocabulary, so
# exit 1 keeps one meaning across every action here (see the exit-code table above).
# ------------------------------------------------------------------------------------------------

do_check() {
  [ "$#" -eq 0 ] || die3 "check: unrecognized argument: $1"

  [ -f "$CHECK_RESEARCH_SCRIPT" ] \
    || die3 "check: cannot find check-research.sh at $CHECK_RESEARCH_SCRIPT"

  # The report goes to a file and the summary to stdout, so the conversation holds the verdict and
  # a path rather than the whole report.
  local rc verdict lines
  bash "$CHECK_RESEARCH_SCRIPT" "$TASK_PATH" >"$CHECK_FILE"
  rc=$?
  case "$rc" in
    0) verdict=0 ;;
    1) verdict=4 ;;
    3) verdict=3 ;;
    4) verdict=5 ;;
    *) die3 "check: check-research.sh exited with an unexpected code $rc" ;;
  esac
  lines="$(wc -l <"$CHECK_FILE" | tr -d '[:space:]')"
  echo "action: check"
  echo "status: $verdict"
  echo "lines: $lines"
  echo "report: $CHECK_FILE"
  if [ "$verdict" -ne 0 ]; then
    echo "open: $(jq -r '
      [ ("criteria with no finding: " + ((.coverage.criteriaWithNoFinding // []) | map(.id) | join(" "))
          | select(endswith(": ") | not)),
        ("findings with no criterion: " + ((.coverage.findingsWithNoCriterion // []) | length | tostring)
          | select(endswith(": 0") | not)),
        ("unknown criterion ids: " + ((.coverage.unknownCriteriaIds // []) | map(.id) | unique | join(" "))
          | select(endswith(": ") | not)),
        ("files with issues: " + ((.fileIssueCount // 0) | tostring) | select(endswith(": 0") | not))
      ] | join("; ")' "$CHECK_FILE" 2>/dev/null)"
  fi
  exit "$verdict"
}

# ------------------------------------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------------------------------------

ACTION="${1:-}"
if [ "$ACTION" = "-h" ] || [ "$ACTION" = "--help" ]; then
  usage
  exit 0
fi
[ -n "$ACTION" ] || { usage; die3 "no action given"; }
shift

TASK_FOLDER_ARG="${1:-}"
[ -n "$TASK_FOLDER_ARG" ] || { usage; die3 "$ACTION: a task folder is required"; }
shift

TASK_PATH="$(resolve_task_folder "$TASK_FOLDER_ARG" "$ACTION")"
RESOLVE_RC=$?
[ "$RESOLVE_RC" -eq 0 ] || exit "$RESOLVE_RC"
ALIGNMENT_FILE="$TASK_PATH/alignment.json"
RESEARCH_DIR="$TASK_PATH/research"
CHECK_FILE="$TASK_PATH/research-check.json"

case "$ACTION" in
  read)    do_read    "$@" ;;
  start)   do_start   "$@" ;;
  record)  do_record  "$@" ;;
  check)   do_check   "$@" ;;
  *) usage; die3 "unknown action: $ACTION" ;;
esac
