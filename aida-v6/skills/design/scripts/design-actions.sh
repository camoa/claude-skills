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
# What reaches stdout is what reaches the orchestrator's context. Every action prints `key: value`
# summary lines and the paths it wrote, and never a record body. A caller that needs a field reads
# the file at the printed path. `check` writes check-design.sh's report to
# <task_folder>/design-check.json and prints its status, its line count and that path.
#
# Usage:
#   design-actions.sh read       <task_folder>
#   design-actions.sh start      <task_folder>
#   design-actions.sh create     <task_folder> \
#                        --title <text> [--criteria-served <id[,id...]>] \
#                        [--criteria-owned <id[,id...]>] [--non-goals <id[,id...]>] \
#                        [--depends-on <id[,id...]>] [--interface <text>] [--reasoning <text>] \
#                        [--diff-budget <text>]
#   design-actions.sh update     <task_folder> \
#                        --id <woId> [--title <text>] [--criteria-served <id[,id...]>] \
#                        [--criteria-owned <id[,id...]>] [--non-goals <id[,id...]>] \
#                        [--depends-on <id[,id...]>] [--interface <text>] [--reasoning <text>] \
#                        [--diff-budget <text>]
#   design-actions.sh add-owned-file <task_folder> \
#                        --id <woId> --path <path>
#   design-actions.sh add-done-when  <task_folder> \
#                        --id <woId> --text <text>
#   design-actions.sh add-test       <task_folder> \
#                        --id <woId> --level <text> --description <text>
#   design-actions.sh render     <task_folder> --id <woId>
#   design-actions.sh check      <task_folder>
#   design-actions.sh --run-mode <interactive|autonomous> close <task_folder>
#
# --run-mode is accepted on every action and `close` requires it. A close record says who was
# present, so the mode cannot default: an autonomous run that forgot the flag would otherwise
# record a person nobody saw. Every other action ignores it.
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
# UTC date, the run mode, who closed it, and one hash, computed by scripts/lib/records-hash.sh over alignment.json and every
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

RUN_MODE=""
if [ "${1:-}" = "--run-mode" ]; then
  [ $# -ge 2 ] || { printf 'design-actions: --run-mode needs a value\n' >&2; exit 3; }
  RUN_MODE="$2"
  shift 2
  case "$RUN_MODE" in
    interactive|autonomous) ;;
    *) printf 'design-actions: run mode must be interactive or autonomous, got %s\n' "$RUN_MODE" >&2; exit 3 ;;
  esac
fi

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
       design-actions.sh --run-mode <interactive|autonomous> close <task_folder>
EOF
}

# The four helpers every stage script needs before it touches a task folder live in one place
# (scripts/lib/task-helpers.sh): resolve_task_folder, looks_like_flag, is_blank, write_atomic.
TASK_HELPERS_LIB="${PLUGIN_ROOT}/scripts/lib/task-helpers.sh"
[ -f "$TASK_HELPERS_LIB" ] || die3 "cannot find the task-helper library at $TASK_HELPERS_LIB"
# shellcheck source=/dev/null
source "$TASK_HELPERS_LIB" || die3 "the task-helper library failed to load: $TASK_HELPERS_LIB"

# Every flag that takes a value refuses the same two ways: no value at all, and a value that is
# itself the next option. $1 the action, $2 the flag, $3 what is left of "$#", $4 the value.
need_value() {
  [ "$3" -ge 2 ] || die3 "$1: $2 needs a value"
  looks_like_flag "$4" && die3 "$1: $2 needs a value, got the option $4 instead"
  return 0
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
# The list is split with tr and read line by line. An unquoted `for id in $raw` under a comma IFS
# splits in bash and not in zsh. zsh was handed the whole list as one id.
parse_id_list() {
  local raw="$1" space="$2" who="$3" id
  ID_LIST_JSON='[]'
  [ -n "$raw" ] || return 0
  while IFS= read -r id; do
    is_blank "$id" && die3 "$who: has a blank id in '$raw'"
    id_shape_ok "$id" "$space" \
      || die3 "$who: id '$id' is not a valid ${space}<n> id shape (no leading zero)"
    ID_LIST_JSON="$(printf '%s' "$ID_LIST_JSON" | jq --arg id "$id" '. + [$id]')"
  done < <(printf '%s\n' "$raw" | tr ',' '\n')
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
  bash "$DESIGN_RENDER_SCRIPT" "$TASK_PATH" "$id" >/dev/null
  local rc=$?
  [ "$rc" -eq 0 ] || die3 "design-render.sh could not render $id.md (exit $rc)"
  echo "rendered: $DESIGN_DIR/$id.md"
}

# The one summary printer. It names the id and the list fields, and counts the free-text ones.
wo_summary() {
  printf '%s' "$1" | jq -r '
    "id: " + .id,
    "criteriaServed: " + ((.criteriaServed // []) | join(",")),
    "criteriaOwned: " + ((.criteriaOwned // []) | join(",")),
    "dependsOn: " + ((.dependsOn // []) | join(",")),
    "ownedFiles: " + ((.ownedFiles // []) | length | tostring),
    "tests: " + ((.tests // []) | length | tostring),
    "doneWhen: " + ((.doneWhen // []) | length | tostring)'
}

# One line naming everything a check report left open, for `check` and `close` alike.
open_summary_of() {
  printf '%s' "$1" | jq -r '
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
    ' 2>/dev/null
}

# ------------------------------------------------------------------------------------------------
# read: the current state, never a failure just because nothing has run yet.
# ------------------------------------------------------------------------------------------------

do_read() {
  [ "$#" -eq 0 ] || die3 "read: unrecognized argument: $1"

  # Summary lines only. The skill routes on `contract:` and `work-orders:`, and reads the contract
  # and each work order from the paths printed here when it needs their text.
  local contract_state design_state wo_count f ftype
  contract_state="absent"
  [ "$(contract_ok)" = "true" ] && contract_state="present"
  echo "action: read"
  echo "task: $TASK_PATH"
  echo "contract: $contract_state"
  echo "contract-file: $ALIGNMENT_FILE"
  echo "criteria: $(contract_criteria_json | jq -r '[.[].id] | join(" ")')"
  echo "non-goals: $(contract_non_goals_json | jq -r '[.[].id] | join(" ")')"

  design_state="not started"
  wo_count=0
  if [ -d "$DESIGN_DIR" ]; then
    design_state="started"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      ftype="$(jq -r 'type' "$f" 2>/dev/null)"
      if [ "$ftype" = "object" ]; then
        wo_count=$((wo_count + 1))
        echo "work-order: $f"
      else
        echo "unreadable: $f"
      fi
    done < <(find "$DESIGN_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
  fi
  echo "design: $design_state"
  echo "design-dir: $DESIGN_DIR"
  echo "work-orders: $wo_count"
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
  echo "contract-file: $ALIGNMENT_FILE"
  echo "criteria: $(contract_criteria_json | jq -r '[.[].id] | join(" ")')"
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
        need_value "create" "--title" "$#" "${2:-}"
        title="$2"; shift 2 ;;
      --criteria-served)
        need_value "create" "--criteria-served" "$#" "${2:-}"
        criteria_served="$2"; shift 2 ;;
      --criteria-owned)
        need_value "create" "--criteria-owned" "$#" "${2:-}"
        criteria_owned="$2"; shift 2 ;;
      --non-goals)
        need_value "create" "--non-goals" "$#" "${2:-}"
        non_goals="$2"; shift 2 ;;
      --depends-on)
        need_value "create" "--depends-on" "$#" "${2:-}"
        depends_on="$2"; shift 2 ;;
      --interface)
        need_value "create" "--interface" "$#" "${2:-}"
        interface="$2"; shift 2 ;;
      --reasoning)
        need_value "create" "--reasoning" "$#" "${2:-}"
        reasoning="$2"; shift 2 ;;
      --diff-budget)
        need_value "create" "--diff-budget" "$#" "${2:-}"
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
  wo_summary "$doc"

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
        need_value "update" "--id" "$#" "${2:-}"
        id="$2"; shift 2 ;;
      --title)
        need_value "update" "--title" "$#" "${2:-}"
        title="$2"; set_title=true; shift 2 ;;
      --criteria-served)
        need_value "update" "--criteria-served" "$#" "${2:-}"
        criteria_served="$2"; set_served=true; shift 2 ;;
      --criteria-owned)
        need_value "update" "--criteria-owned" "$#" "${2:-}"
        criteria_owned="$2"; set_owned=true; shift 2 ;;
      --non-goals)
        need_value "update" "--non-goals" "$#" "${2:-}"
        non_goals="$2"; set_nongoals=true; shift 2 ;;
      --depends-on)
        need_value "update" "--depends-on" "$#" "${2:-}"
        depends_on="$2"; set_dependson=true; shift 2 ;;
      --interface)
        need_value "update" "--interface" "$#" "${2:-}"
        interface="$2"; set_interface=true; shift 2 ;;
      --reasoning)
        need_value "update" "--reasoning" "$#" "${2:-}"
        reasoning="$2"; set_reasoning=true; shift 2 ;;
      --diff-budget)
        need_value "update" "--diff-budget" "$#" "${2:-}"
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
  wo_summary "$doc"

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
        need_value "add-owned-file" "--id" "$#" "${2:-}"
        id="$2"; shift 2 ;;
      --path)
        need_value "add-owned-file" "--path" "$#" "${2:-}"
        path_val="$2"; shift 2 ;;
      *) die3 "add-owned-file: unrecognized argument: $1" ;;
    esac
  done
  require_wo_id_arg "add-owned-file" "$id"
  is_blank "$path_val" && die3 "add-owned-file: --path is required and must not be blank"
  # A path, never a glob. Implementation derives the test author's denied reads from these entries
  # and compares them as paths, so a glob would deny nothing while the dispatch still reads as
  # enforced. Refusing here is where the model finds out; check-design.sh repeats the rule for a
  # file edited by hand.
  case "$path_val" in
    *'*'*|*'?'*|*'['*)
      die3 "add-owned-file: an owned file is a path and not a glob, and $path_val carries a wildcard. Name the directory, such as src/thing/, or add each file. A glob denies nothing when implementation derives what the test author may not read." ;;
  esac
  # A path never begins with a dash. Implementation expands these entries into the argument list of
  # whatever tool the framework recipe names, so a leading dash reaches that tool as an option, and
  # a tool with a fixing mode rewrites what it is pointed at.
  case "$path_val" in
    -*)
      die3 "add-owned-file: an owned file never begins with a dash, and $path_val does. Implementation hands these entries to the coding-standards, static-analysis and security tools as arguments, where a leading dash reads as an option and not as a path. Write ./$path_val, or rename the file." ;;
  esac

  local file doc
  file="$(wo_file_for "$id")"
  jq empty "$file" 2>/dev/null || die3 "add-owned-file: $file exists but is not valid JSON"
  doc="$(jq --arg p "$path_val" '.ownedFiles = (((.ownedFiles // []) + [$p]) | unique)' "$file")"
  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  wo_summary "$doc"
  render_wo "$id"
  exit 0
}

do_add_done_when() {
  local id="" text=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        need_value "add-done-when" "--id" "$#" "${2:-}"
        id="$2"; shift 2 ;;
      --text)
        need_value "add-done-when" "--text" "$#" "${2:-}"
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
  wo_summary "$doc"
  render_wo "$id"
  exit 0
}

do_add_test() {
  local id="" level="" description=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        need_value "add-test" "--id" "$#" "${2:-}"
        id="$2"; shift 2 ;;
      --level)
        need_value "add-test" "--level" "$#" "${2:-}"
        level="$2"; shift 2 ;;
      --description)
        need_value "add-test" "--description" "$#" "${2:-}"
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
  wo_summary "$doc"
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
        need_value "render" "--id" "$#" "${2:-}"
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

  # The report goes to a file and the summary to stdout, so the conversation holds the verdict and
  # a path rather than the whole report.
  local rc verdict lines
  bash "$CHECK_DESIGN_SCRIPT" "$TASK_PATH" >"$CHECK_FILE"
  rc=$?
  case "$rc" in
    0) verdict=0 ;;
    1) verdict=4 ;;
    3) verdict=3 ;;
    4) verdict=5 ;;
    *) die3 "check: check-design.sh exited with an unexpected code $rc" ;;
  esac
  lines="$(wc -l <"$CHECK_FILE" | tr -d '[:space:]')"
  echo "action: check"
  echo "status: $verdict"
  echo "lines: $lines"
  echo "report: $CHECK_FILE"
  if [ "$verdict" -ne 0 ]; then
    echo "open: $(open_summary_of "$(cat "$CHECK_FILE")")"
  fi
  exit "$verdict"
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
  [ -n "$RUN_MODE" ] \
    || die3 "close: --run-mode is required. The close record says who was present, and that is never assumed"

  [ -f "$CHECK_DESIGN_SCRIPT" ] \
    || die3 "close: cannot find check-design.sh at $CHECK_DESIGN_SCRIPT"

  local check_stderr_file check_report_json check_rc check_stderr_text
  check_stderr_file="$(mktemp)" || die3 "close: could not create a temporary file"
  check_report_json="$(bash "$CHECK_DESIGN_SCRIPT" "$TASK_PATH" 2>"$check_stderr_file")"
  check_rc=$?
  check_stderr_text="$(cat "$check_stderr_file" 2>/dev/null)"
  rm -f "$check_stderr_file"

  case "$check_rc" in
    0)
      # Exit 0 means nothing the check could reach was wrong. It does not mean everything was
      # reached. A contract it could not read leaves the coverage joins un-run, and a task with no
      # design/ folder leaves the graph checks un-run, and both still exit 0 because the check
      # reports what it could not do rather than guessing. Closing on that would freeze a hash over
      # a design nothing compared against the contract, and implementation refuses to start without
      # exactly that hash. Unanswered is not a pass (ideal/design.md, "Design's own checks run, they
      # do not read"), and version 5 required a recorded not_run rather than an un-run check
      # (stages/07-design-coverage.md).
      local coverage_checked graph_checked skipped_note
      coverage_checked="$(printf '%s' "$check_report_json" | jq -r '.coverage.checked // false' 2>/dev/null)"
      graph_checked="$(printf '%s' "$check_report_json" | jq -r '.graph.checked // false' 2>/dev/null)"
      skipped_note=""
      if [ "$coverage_checked" != "true" ]; then
        skipped_note="$(printf '%s' "$check_report_json" | jq -r '.coverage.note // "the contract could not be read"' 2>/dev/null)"
        die5 "close: the coverage checks against the contract never ran, so nothing compared this design to the criteria it must serve. Reason: $skipped_note"
      fi
      if [ "$graph_checked" != "true" ]; then
        skipped_note="$(printf '%s' "$check_report_json" | jq -r '.graph.note // "design has not started"' 2>/dev/null)"
        die5 "close: the checks between work orders never ran, so nothing walked this design's own dependencies. Reason: $skipped_note"
      fi
      ;;
    1|4)
      local open_summary
      open_summary="$(open_summary_of "$check_report_json")"
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

  # An interactive close happens in front of the person who has just read the rendered design, so
  # the person is the one closing. An autonomous close has nobody to be that person, and saying so
  # is the whole value of the field.
  local closed_at closed_by doc
  closed_at="$(date -u +%Y-%m-%d)"
  if [ "$RUN_MODE" = "autonomous" ]; then closed_by="nobody"; else closed_by="person"; fi
  doc="$(jq -n --arg closedAt "$closed_at" --arg hash "$hash" \
    --arg runMode "$RUN_MODE" --arg closedBy "$closed_by" \
    '{schemaVersion: 1, closedAt: $closedAt, runMode: $runMode, closedBy: $closedBy, hash: $hash}')"

  write_atomic "$CLOSED_FILE" "$doc"
  echo "CLOSED: $CLOSED_FILE"
  echo "closedBy: $closed_by"
  echo "runMode: $RUN_MODE"
  echo "hash: $hash"
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
CHECK_FILE="$TASK_PATH/design-check.json"

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
