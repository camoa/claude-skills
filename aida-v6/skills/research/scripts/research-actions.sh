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
# Usage:
#   research-actions.sh [--run-mode <interactive|autonomous>] read   <task_folder>
#   research-actions.sh [--run-mode <interactive|autonomous>] start  <task_folder>
#   research-actions.sh [--run-mode <interactive|autonomous>] record <task_folder> \
#                          --search <slug> --text <text> --source <text> \
#                          [--criteria-served <id[,id...]>]
#   research-actions.sh [--run-mode <interactive|autonomous>] check  <task_folder>
#
# --run-mode changes nothing this script does today. It is accepted, and rejected when it is
# neither interactive nor autonomous, for the same reason tool-actions.sh accepts it on every
# action: a caller passes one run mode for a whole invocation, and a flag some actions ignore is
# a smaller surface than two ways of invoking the same script. Research never blocks and never
# asks (ideal/research.md, 'Research never blocks'), so no action here branches on it; a later
# action may, and the flag is already in place for that day.
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
# (scripts/research-schema.json). Its fields are schemaVersion, search and findings; a finding
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
#      research file already on disk that is not valid JSON or is not a JSON object; the plugin
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

RUN_MODE="interactive"
if [ "${1:-}" = "--run-mode" ]; then
  [ $# -ge 2 ] || { printf 'research-actions: --run-mode needs a value\n' >&2; exit 3; }
  RUN_MODE="$2"
  shift 2
fi
case "$RUN_MODE" in
  interactive|autonomous) ;;
  *) printf 'research-actions: run mode must be interactive or autonomous, got %s\n' "$RUN_MODE" >&2; exit 3 ;;
esac

command -v jq >/dev/null 2>&1 || { printf 'research-actions: jq is required and was not found on PATH\n' >&2; exit 3; }

die1() { printf 'research-actions: %s\n' "$1" >&2; exit 1; }
die2() { printf 'research-actions: %s\n' "$1" >&2; exit 2; }
die3() { printf 'research-actions: %s\n' "$1" >&2; exit 3; }

usage() {
  cat <<'EOF' >&2
usage: research-actions.sh read   <task_folder>
       research-actions.sh start  <task_folder>
       research-actions.sh record <task_folder> --search <slug> --text <text> --source <text> \
                                   [--criteria-served <id[,id...]>]
       research-actions.sh check  <task_folder>
EOF
}

# ------------------------------------------------------------------------------------------------
# Small helpers shared by more than one action below. Ported from scope-actions.sh, which states
# the reasoning for each in its own header.
# ------------------------------------------------------------------------------------------------

resolve_task_folder() {
  local arg="$1" who="$2" p
  [ -n "$arg" ] || die3 "$who: a task folder is required"
  p="$(cd "$arg" 2>/dev/null && pwd -P)" || die1 "$who: task folder not found: $arg"
  [ -f "$p/task.json" ] || die1 "$who: $p has no task.json; this is not a task folder"
  printf '%s' "$p"
}

looks_like_flag() {
  case "$1" in
    --*) return 0 ;;
    *) return 1 ;;
  esac
}

is_blank() {
  case "$1" in
    *[![:space:]]*) return 1 ;;
  esac
  return 0
}

# The temporary file is created beside the target, in the same directory, so mv is a rename
# within one filesystem rather than a copy across two, and a failure partway never leaves a
# half-written file at $target (this is scope-actions.sh's own write_atomic, generalised to take
# the target's own directory instead of assuming TASK_PATH, since a research file lives one level
# down in $RESEARCH_DIR).
write_atomic() {
  local target="$1" content="$2" dir tmp
  dir="$(dirname -- "$target")"
  tmp="$(mktemp "${dir}/.$(basename -- "$target").XXXXXX")" \
    || die3 "could not create a temporary file in $dir"
  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; die3 "could not write $tmp"; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; die3 "could not write $target"; }
}

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
  jq -c '[ (.criteria // [])[]? | {id: .id, text: .text} ]' "$ALIGNMENT_FILE" 2>/dev/null || printf '[]'
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

  local criteria_json contract_exists files_json research_exists f entry ftype
  criteria_json="$(contract_criteria_json)"
  contract_exists="$(contract_ok)"

  files_json="[]"
  research_exists=false
  if [ -d "$RESEARCH_DIR" ]; then
    research_exists=true
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if ! jq empty "$f" 2>/dev/null; then
        entry="$(jq -n --arg path "$f" '{path: $path, parsed: false, note: "not valid JSON"}')"
      else
        ftype="$(jq -r 'type' "$f" 2>/dev/null)"
        if [ "$ftype" != "object" ]; then
          entry="$(jq -n --arg path "$f" --arg t "$ftype" '{path: $path, parsed: false, note: ("valid JSON but a " + $t + ", not an object")}')"
        else
          entry="$(jq --arg path "$f" '{path: $path, parsed: true, search: (.search // null), findingCount: ((.findings // []) | length)}' "$f" 2>/dev/null)"
          [ -n "$entry" ] || entry="$(jq -n --arg path "$f" '{path: $path, parsed: false, note: "could not be read"}')"
        fi
      fi
      files_json="$(printf '%s' "$files_json" | jq --argjson e "$entry" '. + [$e]')"
    done < <(find "$RESEARCH_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
  fi

  jq -n \
    --arg taskPath "$TASK_PATH" \
    --arg alignmentFile "$ALIGNMENT_FILE" \
    --argjson contractExists "$contract_exists" \
    --argjson criteria "$criteria_json" \
    --arg researchDir "$RESEARCH_DIR" \
    --argjson researchStarted "$research_exists" \
    --argjson files "$files_json" \
    '{taskPath: $taskPath, alignmentFile: $alignmentFile, contractExists: $contractExists,
      criteria: $criteria, researchDir: $researchDir, researchStarted: $researchStarted,
      files: $files}'
  exit 0
}

# ------------------------------------------------------------------------------------------------
# start: makes sure the contract exists before research begins, and makes sure the research
# folder exists. Idempotent: running it again on a task already started changes nothing and is
# not refused, unlike scope's `init`, because no aggregate file here could be overwritten by a
# second call. Prints the criteria the conversation is answering for.
# ------------------------------------------------------------------------------------------------

do_start() {
  [ "$#" -eq 0 ] || die3 "start: unrecognized argument: $1"

  [ "$(contract_ok)" = "true" ] \
    || die2 "start: $ALIGNMENT_FILE not found, unreadable, or not a contract. Run the scope skill on this task first"

  mkdir -p "$RESEARCH_DIR" || die3 "start: could not create $RESEARCH_DIR"

  echo "STARTED: $RESEARCH_DIR"
  contract_criteria_json
  printf '\n'
  exit 0
}

# ------------------------------------------------------------------------------------------------
# record: appends one finding to <task_folder>/research/<search>.json, creating the file when it
# does not already exist, then renders <search>.md from it by calling research-render.sh.
# ------------------------------------------------------------------------------------------------

do_record() {
  local search="" text="" source_val="" criteria_served=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --search)
        [ $# -ge 2 ] || die3 "record: --search needs a value"
        looks_like_flag "$2" && die3 "record: --search needs a value, got the option $2 instead"
        search="$2"; shift 2 ;;
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
  is_blank "$text" && die3 "record: --text is required and must not be blank"
  is_blank "$source_val" && die3 "record: --source is required and must not be blank. Every finding names where it came from"

  local ids_json='[]'
  if [ -n "$criteria_served" ]; then
    local old_ifs="$IFS" id
    IFS=','
    for id in $criteria_served; do
      IFS="$old_ifs"
      is_blank "$id" && die3 "record: --criteria-served has a blank id in '$criteria_served'"
      is_criterion_id "$id" \
        || die3 "record: --criteria-served id '$id' is not a valid criterion id shape (c<n>, no leading zero)"
      ids_json="$(printf '%s' "$ids_json" | jq --arg id "$id" '. + [$id]')"
      IFS=','
    done
    IFS="$old_ifs"
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
    doc="$(jq --argjson f "$finding_json" '.findings = ((.findings // []) + [$f])' "$file")" \
      || die3 "record: could not add the new finding to $file"
  else
    doc="$(jq -n --arg search "$search" --argjson f "$finding_json" \
        '{schemaVersion: 1, search: $search, findings: [$f]}')"
  fi

  write_atomic "$file" "$doc"

  echo "RECORDED: $file"
  printf '%s\n' "$finding_json"

  [ -f "$RESEARCH_RENDER_SCRIPT" ] \
    || die3 "record: cannot find research-render.sh at $RESEARCH_RENDER_SCRIPT"
  bash "$RESEARCH_RENDER_SCRIPT" "$TASK_PATH" "$search"
  local render_rc=$?
  [ "$render_rc" -eq 0 ] \
    || die3 "record: research-render.sh could not render $search.md (exit $render_rc)"

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

  bash "$CHECK_RESEARCH_SCRIPT" "$TASK_PATH"
  local rc=$?
  case "$rc" in
    0) exit 0 ;;
    1) exit 4 ;;
    3) exit 3 ;;
    4) exit 5 ;;
    *) die3 "check: check-research.sh exited with an unexpected code $rc" ;;
  esac
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

case "$ACTION" in
  read)    do_read    "$@" ;;
  start)   do_start   "$@" ;;
  record)  do_record  "$@" ;;
  check)   do_check   "$@" ;;
  *) usage; die3 "unknown action: $ACTION" ;;
esac
