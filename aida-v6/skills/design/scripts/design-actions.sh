#!/usr/bin/env bash
# design-actions.sh: the deterministic half of the design skill (ideal/design.md).
#
# The skill body holds the conversation: which recipe to follow, how a work order is sized, which
# criteria a proposed order should serve and own, and whether a person has confirmed a claimed
# ownership. This script never decides any of that. Every fact it needs arrives already decided,
# as an argument, the same split scope-actions.sh and research-actions.sh use. It writes one file
# per work order under <task_folder>/design/, mints an id, renders that file's markdown, and runs
# the design check. Deciding whether design is done belongs to whoever calls this, never to this
# script.
#
# Usage:
#   design-actions.sh [--run-mode <interactive|autonomous>] read       <task_folder>
#   design-actions.sh [--run-mode <interactive|autonomous>] start      <task_folder>
#   design-actions.sh [--run-mode <interactive|autonomous>] create     <task_folder> \
#                        --title <text> [--criteria-served <id[,id...]>] \
#                        [--criteria-owned <id[,id...]>] [--non-goals <id[,id...]>] \
#                        [--depends-on <id[,id...]>] [--interface <text>] [--reasoning <text>] \
#                        [--diff-budget <text>]
#   design-actions.sh [--run-mode <interactive|autonomous>] update     <task_folder> \
#                        --id <woId> [--title <text>] [--criteria-served <id[,id...]>] \
#                        [--criteria-owned <id[,id...]>] [--non-goals <id[,id...]>] \
#                        [--depends-on <id[,id...]>] [--interface <text>] [--reasoning <text>] \
#                        [--diff-budget <text>]
#   design-actions.sh [--run-mode <interactive|autonomous>] add-owned-file <task_folder> \
#                        --id <woId> --path <path>
#   design-actions.sh [--run-mode <interactive|autonomous>] add-done-when  <task_folder> \
#                        --id <woId> --text <text>
#   design-actions.sh [--run-mode <interactive|autonomous>] add-test       <task_folder> \
#                        --id <woId> --level <text> --description <text>
#   design-actions.sh [--run-mode <interactive|autonomous>] render     <task_folder> --id <woId>
#   design-actions.sh [--run-mode <interactive|autonomous>] check      <task_folder>
#   design-actions.sh [--run-mode <interactive|autonomous>] close      <task_folder>
#
# --run-mode is accepted on every action and changes nothing this script does today, the same
# stance research-actions.sh takes for the same reason: a caller passes one run mode for a whole
# invocation, and a flag some actions ignore is a smaller surface than two ways of invoking the
# same script. Design's own approval step, where an interactive run asks whether a claimed
# ownership is true and an autonomous run instead records that completeness was not judged
# (ideal/design.md, "Serving a criterion is not completing it"), is a conversation the skill body
# holds; nothing here needs the run mode to hold it.
#
# Depends on, shipped by the same part and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/design-render.sh      called by `create`, `update` and `render`
#   ${CLAUDE_PLUGIN_ROOT}/scripts/check-design.sh       called by `check` and `close`
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/records-hash.sh   sourced; its records_hash_for is called by
#                                                        `close`, and by implement-actions.sh's own
#                                                        `start`, so the two always agree on the
#                                                        same number for the same files.
#
# This script never runs the schema comparison itself. Every field it writes is validated before
# the write, so what it produces is shaped correctly by construction; a stale or hand-edited work
# order file already on disk before this script's first call on it is a fact check-design.sh
# reports, not one this script repairs.
#
# A work order file is plain JSON at <task_folder>/design/<id>.json: no fences, no markdown
# (scripts/design-schema.json). `create` mints `id`, then writes schemaVersion, title,
# criteriaServed, criteriaOwned, nonGoals, dependsOn, ownedFiles, interface, tests, doneWhen,
# reasoning and diffBudget in one call; ownedFiles, tests and doneWhen start empty and grow one
# entry at a time through their own add- actions, the same append-one-at-a-time shape
# research-actions.sh's own `record` uses, because a test or a done-when sentence is free text
# that cannot safely be packed into one comma-separated argument the way an id list can.
#
# An id is minted by scanning this task's own design/ folder for the highest wo<n> already
# present and taking the next number. There is no counter file recording a high-water mark the
# way alignment.json's nextCriterionId does for a criterion. A work order is not expected to be
# deleted and re-minted the way a criterion is revised mid-conversation (ideal/design.md names no
# delete path), so this script does not build one; the gap this leaves, named plainly rather than
# hidden, is that deleting the highest-numbered work order by hand and then minting again would
# reuse its id. Fix that by adding a counter, kept beside nextCriterionId's own precedent, the day
# a real task needs to delete a work order.
#
# `close` records what design closed on (ideal/implementation.md, "Freezing, and what a freeze is
# for"). It runs check-design.sh against the live files first, and writes
# <task_folder>/design-closed.json only when that run exits 0. The record holds schemaVersion, the
# UTC date, and one hash, computed by scripts/lib/records-hash.sh over alignment.json and every
# design/*.json together, in work order id order (scripts/design-closed-schema.json). It sits at
# the task's own root, beside task.json and alignment.json, never inside design/, because a record
# inside the folder it hashes would hash itself. Implementation reads this file and refuses to
# freeze anything when the hash it re-derives from the live files disagrees with the hash recorded
# here; closing again after a further change, which this action always allows, is the supported
# way to make the two agree again.
#
# Exit codes, each one and only one meaning:
#   0  did what was asked. For `read`, this includes an honest report that no contract exists yet
#      and that no work orders exist yet. For `check`, this is check-design.sh's own exit 0. For
#      `close`, this is check-design.sh's own exit 0 followed by a write of design-closed.json.
#   1  the given path does not exist, is not a folder, or holds no task.json: not a task folder
#      (ideal/scope.md, "Scope runs against a task that already exists"). This is the only meaning
#      of exit 1 from this script, for every action, `check` included: check-design.sh's own exit
#      1 means something else, a work order file is malformed, and it is remapped to 4 below so a
#      caller branching on 1 never confuses "not a task folder" with "a file is broken".
#   2  the target of this action is not present: `start` was asked to begin a task with no
#      alignment.json, or with one that will not parse or is not a contract; or `update`,
#      `add-owned-file`, `add-done-when`, `add-test` or `render` were given an --id naming no
#      work order file in this task's design/ folder.
#   3  the script could not do its job: a missing, blank or malformed argument; an argument value
#      that is itself another option; a `--id` that is not a valid work order id shape; a
#      `--criteria-served`, `--criteria-owned`, `--non-goals` or `--depends-on` entry that is not
#      a valid id shape in its own space; a work order file already on disk that is not valid
#      JSON or is not a JSON object; the plugin root could not be resolved; a write that failed;
#      `create`'s, `update`'s or `render`'s own call to design-render.sh failing to produce
#      <id>.md; `check`'s or `close`'s own call to check-design.sh failing to run at all
#      (check-design.sh's own exit 3, meaning it could not do its job either); the records-hash
#      library could not be sourced; or `close`'s own call to records_hash_for failing, once
#      design has already closed clean, to produce a hash.
#   4  `check` ran and found a work order file that cannot be read as this format: not valid
#      JSON, not an object, or a missing, malformed or unknown top-level field (check-design.sh's
#      own exit 1, remapped here so it never collides with this script's own exit 1, "not a task
#      folder"). `close` refuses for the same reason, on the live files, before writing anything.
#   5  `check` ran, every work order file reads fine, but a content or cross-order check has a
#      problem: a criterion with no serving order, a criterion owned by zero or by more than one
#      work order, an order serving no criterion, an order missing a required test, a dependency
#      cycle, an order that reaches no owner, overlapping owned files, or an id naming nothing
#      real (check-design.sh's own exit 4). `close` refuses for the same reason, on the live
#      files, before writing anything.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no regular
# expression interval quantifier anywhere, the same rule research-actions.sh and
# check-alignment.sh state for the same reason (foundations.md, Honesty). An id's own shape is
# checked with a `case` glob (`wo[1-9]*`, `c[1-9]*` or `n[1-9]*`), never a regular expression, the
# same way research-actions.sh checks a criterion id's own shape.

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
  printf 'design-actions: could not resolve the plugin root (CLAUDE_PLUGIN_ROOT is not set and the script'"'"'s own location could not be resolved)\n' >&2
  exit 3
fi
DESIGN_RENDER_SCRIPT="${PLUGIN_ROOT}/scripts/design-render.sh"
CHECK_DESIGN_SCRIPT="${PLUGIN_ROOT}/scripts/check-design.sh"
RECORDS_HASH_LIB="${PLUGIN_ROOT}/scripts/lib/records-hash.sh"

RUN_MODE="interactive"
if [ "${1:-}" = "--run-mode" ]; then
  [ $# -ge 2 ] || { printf 'design-actions: --run-mode needs a value\n' >&2; exit 3; }
  RUN_MODE="$2"
  shift 2
fi
case "$RUN_MODE" in
  interactive|autonomous) ;;
  *) printf 'design-actions: run mode must be interactive or autonomous, got %s\n' "$RUN_MODE" >&2; exit 3 ;;
esac

command -v jq >/dev/null 2>&1 || { printf 'design-actions: jq is required and was not found on PATH\n' >&2; exit 3; }

die1() { printf 'design-actions: %s\n' "$1" >&2; exit 1; }
die2() { printf 'design-actions: %s\n' "$1" >&2; exit 2; }
die3() { printf 'design-actions: %s\n' "$1" >&2; exit 3; }
die4() { printf 'design-actions: %s\n' "$1" >&2; exit 4; }
die5() { printf 'design-actions: %s\n' "$1" >&2; exit 5; }

[ -f "$RECORDS_HASH_LIB" ] || die3 "cannot find the records-hash library at $RECORDS_HASH_LIB"
# shellcheck source=/dev/null
source "$RECORDS_HASH_LIB" || die3 "the records-hash library failed to load: $RECORDS_HASH_LIB"

usage() {
  cat <<'EOF' >&2
usage: design-actions.sh read           <task_folder>
       design-actions.sh start          <task_folder>
       design-actions.sh create         <task_folder> --title <text> \
                                         [--criteria-served <id[,id...]>] \
                                         [--criteria-owned <id[,id...]>] \
                                         [--non-goals <id[,id...]>] [--depends-on <id[,id...]>] \
                                         [--interface <text>] [--reasoning <text>] \
                                         [--diff-budget <text>]
       design-actions.sh update         <task_folder> --id <woId> [--title <text>] \
                                         [--criteria-served <id[,id...]>] \
                                         [--criteria-owned <id[,id...]>] \
                                         [--non-goals <id[,id...]>] [--depends-on <id[,id...]>] \
                                         [--interface <text>] [--reasoning <text>] \
                                         [--diff-budget <text>]
       design-actions.sh add-owned-file <task_folder> --id <woId> --path <path>
       design-actions.sh add-done-when  <task_folder> --id <woId> --text <text>
       design-actions.sh add-test       <task_folder> --id <woId> --level <text> \
                                         --description <text>
       design-actions.sh render         <task_folder> --id <woId>
       design-actions.sh check          <task_folder>
       design-actions.sh close          <task_folder>
EOF
}

# ------------------------------------------------------------------------------------------------
# Small helpers shared by more than one action below. Ported from research-actions.sh and
# scope-actions.sh, which state the reasoning for each in their own headers.
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

write_atomic() {
  local target="$1" content="$2" dir tmp
  dir="$(dirname -- "$target")"
  tmp="$(mktemp "${dir}/.$(basename -- "$target").XXXXXX")" \
    || die3 "could not create a temporary file in $dir"
  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; die3 "could not write $tmp"; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; die3 "could not write $target"; }
}

# Prints "true" when the contract at $ALIGNMENT_FILE exists, is readable, parses as JSON, and is
# shaped like a contract. Never dies: `read` uses this to report an honest state rather than
# fail, and `start` uses it to decide whether to refuse.
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

contract_criteria_json() {
  if [ "$(contract_ok)" != "true" ]; then
    printf '[]'
    return
  fi
  jq -c '[ (.criteria // [])[]? | {id: .id, text: .text} ]' "$ALIGNMENT_FILE" 2>/dev/null || printf '[]'
}

contract_non_goals_json() {
  if [ "$(contract_ok)" != "true" ]; then
    printf '[]'
    return
  fi
  jq -c '[ (.nonGoals // [])[]? | {id: .id, text: .text} ]' "$ALIGNMENT_FILE" 2>/dev/null || printf '[]'
}

# True (exit 0) when $1 has the shape of an id in the space named by $2 ("wo", "c" or "n"):
# that prefix, then a digit 1-9, then zero or more digits. The same case-glob idiom
# research-actions.sh uses for a criterion id, extended here to the three id spaces this script
# reads or writes: wo<n> for a work order, c<n> for a criterion, n<n> for a non-goal.
id_shape_ok() {
  local id="$1" space="$2" num
  case "$space" in
    wo) case "$id" in wo*) : ;; *) return 1 ;; esac; num="${id#wo}" ;;
    c)  case "$id" in c*)  : ;; *) return 1 ;; esac; num="${id#c}" ;;
    n)  case "$id" in n*)  : ;; *) return 1 ;; esac; num="${id#n}" ;;
    *) return 1 ;;
  esac
  case "$num" in
    ''|0*|*[!0-9]*) return 1 ;;
  esac
  return 0
}

# Splits $1 on commas into $ID_LIST_JSON, a JSON array of strings, checking each entry is
# non-blank and has the shape of an id in space $2 ("wo", "c" or "n"). Prints nothing; the caller
# reads $ID_LIST_JSON. An empty $1 yields "[]".
parse_id_list() {
  local raw="$1" space="$2" who="$3" old_ifs id
  ID_LIST_JSON='[]'
  [ -n "$raw" ] || return 0
  old_ifs="$IFS"
  IFS=','
  for id in $raw; do
    IFS="$old_ifs"
    is_blank "$id" && die3 "$who: has a blank id in '$raw'"
    id_shape_ok "$id" "$space" \
      || die3 "$who: id '$id' is not a valid ${space}<n> id shape (no leading zero)"
    ID_LIST_JSON="$(printf '%s' "$ID_LIST_JSON" | jq --arg id "$id" '. + [$id]')"
    IFS=','
  done
  IFS="$old_ifs"
}

# The work order file for a given id, or empty when it does not exist. Never dies.
wo_file_for() {
  printf '%s/design/%s.json' "$TASK_PATH" "$1"
}

wo_exists() {
  local f
  f="$(wo_file_for "$1")"
  [ -f "$f" ]
}

render_wo() {
  local id="$1"
  [ -f "$DESIGN_RENDER_SCRIPT" ] \
    || die3 "cannot find design-render.sh at $DESIGN_RENDER_SCRIPT"
  bash "$DESIGN_RENDER_SCRIPT" "$TASK_PATH" "$id"
  local rc=$?
  [ "$rc" -eq 0 ] || die3 "design-render.sh could not render $id.md (exit $rc)"
}

# ------------------------------------------------------------------------------------------------
# read: the current state, never a failure just because nothing has run yet.
# ------------------------------------------------------------------------------------------------

do_read() {
  [ "$#" -eq 0 ] || die3 "read: unrecognized argument: $1"

  local criteria_json non_goals_json contract_exists files_json design_exists f entry ftype

  criteria_json="$(contract_criteria_json)"
  non_goals_json="$(contract_non_goals_json)"
  contract_exists="$(contract_ok)"

  files_json="[]"
  design_exists=false
  if [ -d "$DESIGN_DIR" ]; then
    design_exists=true
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if ! jq empty "$f" 2>/dev/null; then
        entry="$(jq -n --arg path "$f" '{path: $path, parsed: false, note: "not valid JSON"}')"
      else
        ftype="$(jq -r 'type' "$f" 2>/dev/null)"
        if [ "$ftype" != "object" ]; then
          entry="$(jq -n --arg path "$f" --arg t "$ftype" '{path: $path, parsed: false, note: ("valid JSON but a " + $t + ", not an object")}')"
        else
          entry="$(jq --arg path "$f" '{path: $path, parsed: true, id: (.id // null), title: (.title // null), criteriaServed: (.criteriaServed // []), criteriaOwned: (.criteriaOwned // [])}' "$f" 2>/dev/null)"
          [ -n "$entry" ] || entry="$(jq -n --arg path "$f" '{path: $path, parsed: false, note: "could not be read"}')"
        fi
      fi
      files_json="$(printf '%s' "$files_json" | jq --argjson e "$entry" '. + [$e]')"
    done < <(find "$DESIGN_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
  fi

  jq -n \
    --arg taskPath "$TASK_PATH" \
    --arg alignmentFile "$ALIGNMENT_FILE" \
    --argjson contractExists "$contract_exists" \
    --argjson criteria "$criteria_json" \
    --argjson nonGoals "$non_goals_json" \
    --arg designDir "$DESIGN_DIR" \
    --argjson designStarted "$design_exists" \
    --argjson files "$files_json" \
    '{taskPath: $taskPath, alignmentFile: $alignmentFile, contractExists: $contractExists,
      criteria: $criteria, nonGoals: $nonGoals, designDir: $designDir,
      designStarted: $designStarted, files: $files}'
  exit 0
}

# ------------------------------------------------------------------------------------------------
# start: makes sure the contract exists before design begins, and makes sure the design folder
# exists. Idempotent, the same as research's own `start`: no aggregate file here could be
# overwritten by a second call.
# ------------------------------------------------------------------------------------------------

do_start() {
  [ "$#" -eq 0 ] || die3 "start: unrecognized argument: $1"

  [ "$(contract_ok)" = "true" ] \
    || die2 "start: $ALIGNMENT_FILE not found, unreadable, or not a contract. Run the scope skill on this task first"

  mkdir -p "$DESIGN_DIR" || die3 "start: could not create $DESIGN_DIR"

  echo "STARTED: $DESIGN_DIR"
  contract_criteria_json
  printf '\n'
  exit 0
}

# ------------------------------------------------------------------------------------------------
# The next work order id: scan design/*.json for the highest wo<n> present and take the next
# number, starting at wo1 when none exist. See this script's own header for the known gap this
# leaves around a deleted, highest-numbered work order.
# ------------------------------------------------------------------------------------------------

next_wo_id() {
  local max
  max=0
  if [ -d "$DESIGN_DIR" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      jq empty "$f" 2>/dev/null || continue
      local this_id this_num
      this_id="$(jq -r '.id? // empty' "$f" 2>/dev/null)"
      case "$this_id" in
        wo[1-9]*)
          this_num="${this_id#wo}"
          case "$this_num" in
            ''|*[!0-9]*) continue ;;
          esac
          [ "$this_num" -gt "$max" ] && max="$this_num"
          ;;
      esac
    done < <(find "$DESIGN_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null)
  fi
  printf 'wo%d' "$((max + 1))"
}

# ------------------------------------------------------------------------------------------------
# create: mints an id and writes a new work order file with the scalar and id-list fields given.
# ownedFiles, tests and doneWhen start empty; use add-owned-file, add-test and add-done-when to
# grow them one entry at a time.
# ------------------------------------------------------------------------------------------------

do_create() {
  local title="" criteria_served="" criteria_owned="" non_goals="" depends_on=""
  local interface="" reasoning="" diff_budget=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --title)
        [ $# -ge 2 ] || die3 "create: --title needs a value"
        looks_like_flag "$2" && die3 "create: --title needs a value, got the option $2 instead"
        title="$2"; shift 2 ;;
      --criteria-served)
        [ $# -ge 2 ] || die3 "create: --criteria-served needs a value"
        looks_like_flag "$2" && die3 "create: --criteria-served needs a value, got the option $2 instead"
        criteria_served="$2"; shift 2 ;;
      --criteria-owned)
        [ $# -ge 2 ] || die3 "create: --criteria-owned needs a value"
        looks_like_flag "$2" && die3 "create: --criteria-owned needs a value, got the option $2 instead"
        criteria_owned="$2"; shift 2 ;;
      --non-goals)
        [ $# -ge 2 ] || die3 "create: --non-goals needs a value"
        looks_like_flag "$2" && die3 "create: --non-goals needs a value, got the option $2 instead"
        non_goals="$2"; shift 2 ;;
      --depends-on)
        [ $# -ge 2 ] || die3 "create: --depends-on needs a value"
        looks_like_flag "$2" && die3 "create: --depends-on needs a value, got the option $2 instead"
        depends_on="$2"; shift 2 ;;
      --interface)
        [ $# -ge 2 ] || die3 "create: --interface needs a value"
        looks_like_flag "$2" && die3 "create: --interface needs a value, got the option $2 instead"
        interface="$2"; shift 2 ;;
      --reasoning)
        [ $# -ge 2 ] || die3 "create: --reasoning needs a value"
        looks_like_flag "$2" && die3 "create: --reasoning needs a value, got the option $2 instead"
        reasoning="$2"; shift 2 ;;
      --diff-budget)
        [ $# -ge 2 ] || die3 "create: --diff-budget needs a value"
        looks_like_flag "$2" && die3 "create: --diff-budget needs a value, got the option $2 instead"
        diff_budget="$2"; shift 2 ;;
      *) die3 "create: unrecognized argument: $1" ;;
    esac
  done

  is_blank "$title" && die3 "create: --title is required and must not be blank"

  parse_id_list "$criteria_served" c "create: --criteria-served"; local served_json="$ID_LIST_JSON"
  parse_id_list "$criteria_owned" c "create: --criteria-owned"; local owned_json="$ID_LIST_JSON"
  parse_id_list "$non_goals" n "create: --non-goals"; local nongoals_json="$ID_LIST_JSON"
  parse_id_list "$depends_on" wo "create: --depends-on"; local dependson_json="$ID_LIST_JSON"

  mkdir -p "$DESIGN_DIR" || die3 "create: could not create $DESIGN_DIR"

  local id file
  id="$(next_wo_id)"
  file="$(wo_file_for "$id")"
  [ ! -e "$file" ] || die3 "create: $file already exists; the next id was minted wrong. This is a bug, not an authoring mistake"

  local doc
  doc="$(jq -n \
    --arg id "$id" --arg title "$title" \
    --argjson criteriaServed "$served_json" --argjson criteriaOwned "$owned_json" \
    --argjson nonGoals "$nongoals_json" --argjson dependsOn "$dependson_json" \
    --arg interface "$interface" --arg reasoning "$reasoning" --arg diffBudget "$diff_budget" \
    '{schemaVersion: 1, id: $id, title: $title,
      criteriaServed: $criteriaServed, criteriaOwned: $criteriaOwned, nonGoals: $nonGoals,
      dependsOn: $dependsOn, ownedFiles: [], interface: $interface, tests: [], doneWhen: [],
      reasoning: $reasoning, diffBudget: $diffBudget}')"

  write_atomic "$file" "$doc"

  echo "CREATED: $file"
  printf '%s\n' "$doc"

  render_wo "$id"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# update: replaces the given scalar or id-list fields on an existing work order, wholesale for
# any list passed. ownedFiles, tests and doneWhen are not settable here; use their own add-
# actions.
# ------------------------------------------------------------------------------------------------

do_update() {
  local id="" title="" criteria_served="" criteria_owned="" non_goals="" depends_on=""
  local interface="" reasoning="" diff_budget=""
  local set_title=false set_served=false set_owned=false set_nongoals=false set_dependson=false
  local set_interface=false set_reasoning=false set_diffbudget=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        [ $# -ge 2 ] || die3 "update: --id needs a value"
        looks_like_flag "$2" && die3 "update: --id needs a value, got the option $2 instead"
        id="$2"; shift 2 ;;
      --title)
        [ $# -ge 2 ] || die3 "update: --title needs a value"
        looks_like_flag "$2" && die3 "update: --title needs a value, got the option $2 instead"
        title="$2"; set_title=true; shift 2 ;;
      --criteria-served)
        [ $# -ge 2 ] || die3 "update: --criteria-served needs a value"
        looks_like_flag "$2" && die3 "update: --criteria-served needs a value, got the option $2 instead"
        criteria_served="$2"; set_served=true; shift 2 ;;
      --criteria-owned)
        [ $# -ge 2 ] || die3 "update: --criteria-owned needs a value"
        looks_like_flag "$2" && die3 "update: --criteria-owned needs a value, got the option $2 instead"
        criteria_owned="$2"; set_owned=true; shift 2 ;;
      --non-goals)
        [ $# -ge 2 ] || die3 "update: --non-goals needs a value"
        looks_like_flag "$2" && die3 "update: --non-goals needs a value, got the option $2 instead"
        non_goals="$2"; set_nongoals=true; shift 2 ;;
      --depends-on)
        [ $# -ge 2 ] || die3 "update: --depends-on needs a value"
        looks_like_flag "$2" && die3 "update: --depends-on needs a value, got the option $2 instead"
        depends_on="$2"; set_dependson=true; shift 2 ;;
      --interface)
        [ $# -ge 2 ] || die3 "update: --interface needs a value"
        looks_like_flag "$2" && die3 "update: --interface needs a value, got the option $2 instead"
        interface="$2"; set_interface=true; shift 2 ;;
      --reasoning)
        [ $# -ge 2 ] || die3 "update: --reasoning needs a value"
        looks_like_flag "$2" && die3 "update: --reasoning needs a value, got the option $2 instead"
        reasoning="$2"; set_reasoning=true; shift 2 ;;
      --diff-budget)
        [ $# -ge 2 ] || die3 "update: --diff-budget needs a value"
        looks_like_flag "$2" && die3 "update: --diff-budget needs a value, got the option $2 instead"
        diff_budget="$2"; set_diffbudget=true; shift 2 ;;
      *) die3 "update: unrecognized argument: $1" ;;
    esac
  done

  is_blank "$id" && die3 "update: --id is required and must not be blank"
  id_shape_ok "$id" wo || die3 "update: --id '$id' is not a valid wo<n> id shape"
  local file
  file="$(wo_file_for "$id")"
  wo_exists "$id" || die2 "update: no work order $id in $DESIGN_DIR"
  jq empty "$file" 2>/dev/null || die3 "update: $file exists but is not valid JSON"

  local doc
  doc="$(cat "$file")"

  if [ "$set_title" = "true" ]; then
    is_blank "$title" && die3 "update: --title must not be blank"
    doc="$(printf '%s' "$doc" | jq --arg v "$title" '.title = $v')"
  fi
  if [ "$set_served" = "true" ]; then
    parse_id_list "$criteria_served" c "update: --criteria-served"
    doc="$(printf '%s' "$doc" | jq --argjson v "$ID_LIST_JSON" '.criteriaServed = $v')"
  fi
  if [ "$set_owned" = "true" ]; then
    parse_id_list "$criteria_owned" c "update: --criteria-owned"
    doc="$(printf '%s' "$doc" | jq --argjson v "$ID_LIST_JSON" '.criteriaOwned = $v')"
  fi
  if [ "$set_nongoals" = "true" ]; then
    parse_id_list "$non_goals" n "update: --non-goals"
    doc="$(printf '%s' "$doc" | jq --argjson v "$ID_LIST_JSON" '.nonGoals = $v')"
  fi
  if [ "$set_dependson" = "true" ]; then
    parse_id_list "$depends_on" wo "update: --depends-on"
    doc="$(printf '%s' "$doc" | jq --argjson v "$ID_LIST_JSON" '.dependsOn = $v')"
  fi
  if [ "$set_interface" = "true" ]; then
    doc="$(printf '%s' "$doc" | jq --arg v "$interface" '.interface = $v')"
  fi
  if [ "$set_reasoning" = "true" ]; then
    doc="$(printf '%s' "$doc" | jq --arg v "$reasoning" '.reasoning = $v')"
  fi
  if [ "$set_diffbudget" = "true" ]; then
    doc="$(printf '%s' "$doc" | jq --arg v "$diff_budget" '.diffBudget = $v')"
  fi

  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  printf '%s\n' "$doc"

  render_wo "$id"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# add-owned-file, add-done-when, add-test: append one entry each, the same one-call-per-item
# shape research-actions.sh's own `record` uses for a finding.
# ------------------------------------------------------------------------------------------------

require_wo_id_arg() {
  # $1 = who, remaining positional args already consumed by the caller's own loop; this just
  # validates $ID after the caller's own flag parsing has set it.
  local who="$1" id="$2"
  is_blank "$id" && die3 "$who: --id is required and must not be blank"
  id_shape_ok "$id" wo || die3 "$who: --id '$id' is not a valid wo<n> id shape"
  wo_exists "$id" || die2 "$who: no work order $id in $DESIGN_DIR"
}

do_add_owned_file() {
  local id="" path_val=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        [ $# -ge 2 ] || die3 "add-owned-file: --id needs a value"
        looks_like_flag "$2" && die3 "add-owned-file: --id needs a value, got the option $2 instead"
        id="$2"; shift 2 ;;
      --path)
        [ $# -ge 2 ] || die3 "add-owned-file: --path needs a value"
        looks_like_flag "$2" && die3 "add-owned-file: --path needs a value, got the option $2 instead"
        path_val="$2"; shift 2 ;;
      *) die3 "add-owned-file: unrecognized argument: $1" ;;
    esac
  done
  require_wo_id_arg "add-owned-file" "$id"
  is_blank "$path_val" && die3 "add-owned-file: --path is required and must not be blank"

  local file doc
  file="$(wo_file_for "$id")"
  jq empty "$file" 2>/dev/null || die3 "add-owned-file: $file exists but is not valid JSON"
  doc="$(jq --arg p "$path_val" '.ownedFiles = (((.ownedFiles // []) + [$p]) | unique)' "$file")"
  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  printf '%s\n' "$doc"
  render_wo "$id"
  exit 0
}

do_add_done_when() {
  local id="" text=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        [ $# -ge 2 ] || die3 "add-done-when: --id needs a value"
        looks_like_flag "$2" && die3 "add-done-when: --id needs a value, got the option $2 instead"
        id="$2"; shift 2 ;;
      --text)
        [ $# -ge 2 ] || die3 "add-done-when: --text needs a value"
        looks_like_flag "$2" && die3 "add-done-when: --text needs a value, got the option $2 instead"
        text="$2"; shift 2 ;;
      *) die3 "add-done-when: unrecognized argument: $1" ;;
    esac
  done
  require_wo_id_arg "add-done-when" "$id"
  is_blank "$text" && die3 "add-done-when: --text is required and must not be blank"

  local file doc
  file="$(wo_file_for "$id")"
  jq empty "$file" 2>/dev/null || die3 "add-done-when: $file exists but is not valid JSON"
  doc="$(jq --arg t "$text" '.doneWhen = ((.doneWhen // []) + [$t])' "$file")"
  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  printf '%s\n' "$doc"
  render_wo "$id"
  exit 0
}

do_add_test() {
  local id="" level="" description=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        [ $# -ge 2 ] || die3 "add-test: --id needs a value"
        looks_like_flag "$2" && die3 "add-test: --id needs a value, got the option $2 instead"
        id="$2"; shift 2 ;;
      --level)
        [ $# -ge 2 ] || die3 "add-test: --level needs a value"
        looks_like_flag "$2" && die3 "add-test: --level needs a value, got the option $2 instead"
        level="$2"; shift 2 ;;
      --description)
        [ $# -ge 2 ] || die3 "add-test: --description needs a value"
        looks_like_flag "$2" && die3 "add-test: --description needs a value, got the option $2 instead"
        description="$2"; shift 2 ;;
      *) die3 "add-test: unrecognized argument: $1" ;;
    esac
  done
  require_wo_id_arg "add-test" "$id"
  is_blank "$description" && die3 "add-test: --description is required and must not be blank"

  # --level is accepted and optional, and design does not pass one. Selecting a tier belongs to the
  # stage that writes the test, which is where the framework's own recipe puts it. Design says what
  # the test must observe. The flag stays so that later stage can record what it chose.
  local file doc
  file="$(wo_file_for "$id")"
  jq empty "$file" 2>/dev/null || die3 "add-test: $file exists but is not valid JSON"
  if is_blank "$level"; then
    doc="$(jq --arg d "$description" \
      '.tests = ((.tests // []) + [{description: $d}])' "$file")"
  else
    doc="$(jq --arg l "$level" --arg d "$description" \
      '.tests = ((.tests // []) + [{level: $l, description: $d}])' "$file")"
  fi
  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  printf '%s\n' "$doc"
  render_wo "$id"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# render: calls design-render.sh directly, for a caller that only wants the markdown refreshed
# without changing anything.
# ------------------------------------------------------------------------------------------------

do_render() {
  local id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        [ $# -ge 2 ] || die3 "render: --id needs a value"
        looks_like_flag "$2" && die3 "render: --id needs a value, got the option $2 instead"
        id="$2"; shift 2 ;;
      *) die3 "render: unrecognized argument: $1" ;;
    esac
  done
  require_wo_id_arg "render" "$id"
  render_wo "$id"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# check: calls check-design.sh and remaps its exit code onto this script's own vocabulary, so
# exit 1 keeps one meaning across every action here (see the exit-code table above).
# ------------------------------------------------------------------------------------------------

do_check() {
  [ "$#" -eq 0 ] || die3 "check: unrecognized argument: $1"

  [ -f "$CHECK_DESIGN_SCRIPT" ] \
    || die3 "check: cannot find check-design.sh at $CHECK_DESIGN_SCRIPT"

  bash "$CHECK_DESIGN_SCRIPT" "$TASK_PATH"
  local rc=$?
  case "$rc" in
    0) exit 0 ;;
    1) exit 4 ;;
    3) exit 3 ;;
    4) exit 5 ;;
    *) die3 "check: check-design.sh exited with an unexpected code $rc" ;;
  esac
}

# ------------------------------------------------------------------------------------------------
# close: records what design closed on. Runs check-design.sh against the live files, exactly as
# `check` does, and only when that run exits 0 writes <task_folder>/design-closed.json: schemaVersion,
# the UTC date, and one hash over alignment.json and every design/*.json together, computed by
# records_hash_for (scripts/lib/records-hash.sh, sourced above). Never refuses a second close;
# reopening, changing, and closing again is how a design is meant to change once implementation may
# already have read the first close (ideal/implementation.md, "Freezing, and what a freeze is for").
# ------------------------------------------------------------------------------------------------

do_close() {
  [ "$#" -eq 0 ] || die3 "close: unrecognized argument: $1"

  [ -f "$CHECK_DESIGN_SCRIPT" ] \
    || die3 "close: cannot find check-design.sh at $CHECK_DESIGN_SCRIPT"

  local check_stderr_file check_report_json check_rc check_stderr_text
  check_stderr_file="$(mktemp)" || die3 "close: could not create a temporary file"
  check_report_json="$(bash "$CHECK_DESIGN_SCRIPT" "$TASK_PATH" 2>"$check_stderr_file")"
  check_rc=$?
  check_stderr_text="$(cat "$check_stderr_file" 2>/dev/null)"
  rm -f "$check_stderr_file"

  case "$check_rc" in
    0) : ;;
    1|4)
      local open_summary
      open_summary="$(printf '%s' "$check_report_json" | jq -r '
          [
            ((.coverage.criteriaWithNoServingOrder // [])[] | "criterion " + .id + " has no serving order"),
            ((.coverage.criteriaWithNoOwner // [])[] | "criterion " + .id + " has no owner"),
            ((.coverage.criteriaWithMultipleOwners // [])[] | "criterion " + .id + " is owned by more than one order"),
            ((.coverage.ordersServingNothing // [])[] | "order " + .id + " serves no criterion"),
            ((.coverage.ordersMissingRequiredTests // [])[] | "order " + .id + " owns a machine-verified criterion (" + .criterionId + ") with no test"),
            ((.graph.dependencyCycles // [])[] | "dependency cycle includes " + .),
            ((.graph.orphanSupportOrders // [])[] | "order " + . + " owns nothing and reaches no owner"),
            ((.graph.overlappingOwnedFiles // [])[] | "orders " + (.ids | join(", ")) + " both declare " + .path),
            ((.files // [])[] | select((.schema.issueCount // 0) > 0) | "file " + .path + " does not match the design shape")
          ] | join("; ")
        ' 2>/dev/null)"
      [ -n "$open_summary" ] || open_summary="design left something open; see check-design.sh against $TASK_PATH for detail"
      if [ "$check_rc" -eq 1 ]; then
        die4 "close: a work order file does not match the design shape. Fix it and close again. Open: $open_summary"
      else
        die5 "close: design has not closed cleanly. Finish design first. Open: $open_summary"
      fi
      ;;
    3)
      die3 "close: check-design.sh could not run: $check_stderr_text"
      ;;
    *)
      die3 "close: check-design.sh exited with an unexpected code $check_rc"
      ;;
  esac

  local hash
  hash="$(records_hash_for "$TASK_PATH")" \
    || die3 "close: could not compute the records hash for $TASK_PATH"

  local closed_at doc
  closed_at="$(date -u +%Y-%m-%d)"
  doc="$(jq -n --arg closedAt "$closed_at" --arg hash "$hash" \
    '{schemaVersion: 1, closedAt: $closedAt, hash: $hash}')"

  write_atomic "$CLOSED_FILE" "$doc"
  echo "CLOSED: $CLOSED_FILE"
  printf '%s\n' "$doc"
  exit 0
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
DESIGN_DIR="$TASK_PATH/design"
CLOSED_FILE="$TASK_PATH/design-closed.json"

case "$ACTION" in
  read)           do_read           "$@" ;;
  start)          do_start          "$@" ;;
  create)         do_create         "$@" ;;
  update)         do_update         "$@" ;;
  add-owned-file) do_add_owned_file "$@" ;;
  add-done-when)  do_add_done_when  "$@" ;;
  add-test)       do_add_test       "$@" ;;
  render)         do_render         "$@" ;;
  check)          do_check          "$@" ;;
  close)          do_close          "$@" ;;
  *) usage; die3 "unknown action: $ACTION" ;;
esac
