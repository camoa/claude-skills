#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
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
# `close` also moves each finished critique file from <task_folder>/records/, which the project
# ignores, into <task_folder>/design/, which it commits. It records the new paths, their finding
# count, and the outcome line --critique-outcome passed, `none` without one, and refused unattended.
#
# What reaches stdout is what reaches the orchestrator's context. Every action prints `key: value`
# summary lines and the paths it wrote, and never a record body. A caller that needs a field reads
# the file at the printed path. `check` writes check-design.sh's report to
# <task_folder>/records/design-check.json and prints its status, its line count and that path.
# records/ is where check-task.sh writes too, and the project's .gitignore keeps it out of history.
# A report that changes on every run is a derived value and never something to commit.
#
# Usage:
#   design-actions.sh read       <task_folder>
#   design-actions.sh start      <task_folder>
#   design-actions.sh create     <task_folder> \
#                        --title <text> [--criteria-served <id[,id...]>] \
#                        [--criteria-owned <id[,id...]>] [--non-goals <id[,id...]>] \
#                        [--depends-on <id[,id...]>] [--interface <text>] [--reasoning <text>] \
#                        [--diff-budget <text>] [--proof <tests|gate|record|observe>] [--surface <id>]...
#   design-actions.sh update     <task_folder> \
#                        --id <woId> [--title <text>] [--criteria-served <id[,id...]>] \
#                        [--criteria-owned <id[,id...]>] [--non-goals <id[,id...]>] \
#                        [--depends-on <id[,id...]>] [--interface <text>] [--reasoning <text>] \
#                        [--append-reasoning <text>] \
#                        [--diff-budget <text>] [--proof <tests|gate|record|observe>] [--surface <id>]...
#   design-actions.sh add-owned-file <task_folder> \
#                        --id <woId> --path <path>
#   design-actions.sh add-done-when  <task_folder> \
#                        --id <woId> --text <text>
#   design-actions.sh add-test       <task_folder> \
#                        --id <woId> --level <text> --description <text>
#   design-actions.sh remove-test    <task_folder> --id <woId> --description <text>
#   design-actions.sh remove-done-when  <task_folder> --id <woId> --text <text>
#   design-actions.sh remove-owned-file <task_folder> --id <woId> --path <path>
#   design-actions.sh merge          <task_folder> --into <woId> --from <woId>
#   design-actions.sh read-guide     <task_folder> --path <path on disk> [--name <guide name>]
#   design-actions.sh verify         <task_folder> --id <woId> --recipe <path> [--not-binding]
#   design-actions.sh verify         <task_folder> --id <woId> --run <command> [--pass <form>] --cite <source>
#   design-actions.sh verify         <task_folder> --id <woId> --check <text> --cite <source>
#   design-actions.sh verify         <task_folder> --id <woId> --clear
#   design-actions.sh render     <task_folder> --id <woId>
#   design-actions.sh check      <task_folder>
#   design-actions.sh --run-mode <interactive|autonomous> close <task_folder> \
#                        --recipe-fit <true|false|unsure> --recipe-path <path> --recipe-reason <text> | --no-recipe \
#                        [--critique-outcome <text>]...
#   design-actions.sh distill    <task_folder>
#   design-actions.sh --run-mode <interactive|autonomous> dispose <task_folder> --id <woId> \
#                        --candidate <text> --distance <same-name|same-directory|same-layer> \
#                        --cost <build|carry|agent|risk[,...]> --verdict <reuse|extend|supersede|decline> --why <text> [--confirmed] \
#                        [--path <path> --interface <text>]
#
# --run-mode is accepted on every action and `close` and `dispose` require it. A close record says who was
# present, so the mode cannot default: an autonomous run that forgot the flag would otherwise
# record a person nobody saw. Every other action ignores it. `dispose` needs --cost unless the
# verdict is decline, which compares nothing.
#
# Depends on, shipped by the same part and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/design-render.sh      called by `create`, `update` and `render`
#   ${CLAUDE_PLUGIN_ROOT}/scripts/check-design.sh       called by `check` and `close`
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/recipes.sh        sourced; `verify` reads a recipe through it
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
# reasoning and diffBudget in one call, and proof only when --proof was passed, so an absent field
# is an order nobody chose a proof for (every reader takes it as tests); ownedFiles, tests and doneWhen start empty and grow one
# entry at a time through their own add- actions, the same append-one-at-a-time shape
# research-actions.sh's own `record` uses, because a test or a done-when sentence is free text
# that cannot safely be packed into one comma-separated argument the way an id list can.
#
# An id is minted by scanning this task's own design/ folder for the highest wo<n> already
# present and taking the next number. There is no counter file recording a high-water mark the
# way alignment.json's nextCriterionId does for a criterion. `merge` is the one delete path: the
# sizing rule folds one order into another, and the folded order's file goes (live-run row 74).
# The gap this leaves, named plainly rather than hidden, is that folding the highest-numbered
# work order and then minting again reuses its id. Fix that by adding a counter, kept beside
# nextCriterionId's own precedent, the day a reused id is found to mislead a later record.
#
# `close` records what design closed on (ideal/implementation.md, "Freezing, and what a freeze is
# for"). It runs check-design.sh against the live files first, and writes
# <task_folder>/design-closed.json only when that run exits 0. The record holds schemaVersion, the
# UTC date, the run mode, who closed it, and one hash, computed by scripts/lib/records-hash.sh over alignment.json and every
# design/*.json together, in work order id order (scripts/design-closed-schema.json), plus recipeFit,
# design's verdict on the recipe it read, from the three --recipe-* flags (ideal/tooling.md). It sits at
# the task's own root, beside task.json and alignment.json, never inside design/, because a record
# inside the folder it hashes would hash itself. Implementation reads this file and refuses to
# freeze anything when the hash it re-derives from the live files disagrees with the hash recorded
# here; closing again after a further change, which this action always allows, is the supported
# way to make the two agree again.
#
# `read-guide` records that design opened a guide body (live-run row 77): research names guides
# without opening them, so design is the first read, and a second run in a new session could not
# tell what the first read. <task_folder>/design-guides-read.json holds one entry per path, with
# the body's sha256, the UTC date, and the name research gave it when --name was passed
# (scripts/design-guides-read-schema.json). A second read of the same path replaces its entry. It
# sits at the task root beside design-closed.json, never inside design/, where every file is read
# as a work order and hashed into the close. `read` and `start` print `guidesRead:`, and on a
# resumed run one `guide:` line per entry saying `changed`, `unchanged` or `missing` against the
# body on disk, so the resumed run reads only what changed. Commits nothing; the close commits it.
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
#      `add-owned-file`, `add-done-when`, `add-test`, `remove-test`, `remove-done-when`,
#      `remove-owned-file` or `render` were given an --id naming no work order file in this
#      task's design/ folder; or `remove-test` was given a --description no test on that order
#      carries, `remove-done-when` a --text no row carries, or `remove-owned-file` a --path the
#      order does not own; or `merge` was given an --into or --from naming no work order file;
#      or `read-guide` or `verify` was given a path naming no file on disk; or `distill` found no
#      records/design-distill.json, so the distiller has not been dispatched yet.
#   3  the script could not do its job: a missing, blank or malformed argument; an argument value
#      that is itself another option; a `--id` that is not a valid work order id shape; a
#      `--criteria-served`, `--criteria-owned`, `--non-goals` or `--depends-on` entry that is not
#      a valid id shape in its own space; a `dispose` refused attended (a supersede with no cost dimension, or
#      one without --confirmed), or a decline given --path; an `add-test` refused because the description names one of
#      the order's own surfaces on a `tests` order; a `remove-test` refused because the test named is the last one
#      on a `tests` order owning a machine-verified criterion; a `remove-owned-file` refused because
#      the path named is the only file the order owns; a `merge` refused because the two orders' proofs differ or
#      --into and --from name the same order; a work order file already on disk that is not valid
#      JSON or is not a JSON object; the plugin root could not be resolved; a write that failed;
#      `create`'s, `update`'s or `render`'s own call to design-render.sh failing to produce
#      <id>.md; `check`'s or `close`'s own call to check-design.sh failing to run at all
#      (check-design.sh's own exit 3, meaning it could not do its job either); the records-hash
#      library could not be sourced; or `close`'s own call to records_hash_for failing, once
#      design has already closed clean, to produce a hash; or a `close` with neither --recipe-fit nor --no-recipe;
#      or `read-guide` found design-guides-read.json already on disk and not valid JSON; or
#      `update` was given --reasoning and --append-reasoning together; or `close` was given
#      --critique-outcome with no finished critique file to record it beside, or unattended; or
#      `close` found something that is not a file where a critique file has to move; or `verify`
#      was given no single mode, a recipe with no `## Verifier` or nothing in it to carry, an
#      entry with no run or no pass, a pass outside the three forms, a run line carrying a shell
#      character, or a --run or --check with no --cite.
#   4  `check` ran and found a work order file, or the guides-read record, that cannot be read as
#      its format: not valid JSON, not an object, or a missing, malformed or unknown field
#      (check-design.sh's own exit 1, remapped here so it never collides with this script's own
#      exit 1, "not a task folder"). `close` refuses for the same reason, on the live files, before
#      writing anything.
#      Or `distill` found a sidecar that fails scripts/distill-schema.json, or says standsAlone
#      false with no gap. That sidecar is moved aside first, to <name>.malformed-<date>.json,
#      and stdout names it in a `setAside:` line.
#   5  `check` ran, every work order file reads fine, but a content or cross-order check has a
#      problem. That is a criterion with no serving order, or one owned by zero or by more than
#      one work order. Or an order serving no criterion, or one missing a required test. Or a
#      `record` order that declares a test or has no done-when row. Or one that owns a file
#      outside the project folder or under a path the project ignores. Or a dependency cycle, an
#      order that reaches no owner, overlapping owned files, or an id naming nothing real
#      (check-design.sh's own exit 4). `close` refuses for the same reason, on the live
#      files, before writing anything.
#   6  `start` was asked to begin design on a task research has not closed: no
#      records/research-check.json, or one whose exitCode is not 0. Research is required (the
#      owner's rule: no skip), and the way through is the research skill.
#   79  the action was run from outside the task's own worktree; every stage action but `read` runs there.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no regular
# expression interval quantifier anywhere, the same rule research-actions.sh and
# check-alignment.sh state for the same reason (foundations.md, Honesty). An id's own shape is
# checked with a `case` glob (`wo[1-9]*`, `c[1-9]*` or `n[1-9]*`), never a regular expression, the
# same way research-actions.sh checks a criterion id's own shape.

set -uo pipefail  # not -e: several branches test a command's exit code on purpose.
trap '' PIPE  # a closed pipe must not kill the writes after a print; research-actions.sh says why

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

# shellcheck disable=SC2329 # called by functions in scripts/lib/task-helpers.sh
die1() { printf 'design-actions: %s\n' "$1" >&2; exit 1; }
die2() { printf 'design-actions: %s\n' "$1" >&2; exit 2; }
die3() { printf 'design-actions: %s\n' "$1" >&2; exit 3; }
die4() { printf 'design-actions: %s\n' "$1" >&2; exit 4; }
die5() { printf 'design-actions: %s\n' "$1" >&2; exit 5; }
die6() { printf 'design-actions: %s\n' "$1" >&2; exit 6; }
# shellcheck disable=SC2329 # called by functions in scripts/lib/task-helpers.sh
die79() { printf 'design-actions: %s\n' "$1" >&2; exit 79; }

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
                                         [--diff-budget <text>] [--proof <tests|gate|record|observe>] [--surface <id>]...
       design-actions.sh update         <task_folder> --id <woId> [--title <text>] \
                                         [--criteria-served <id[,id...]>] \
                                         [--criteria-owned <id[,id...]>] \
                                         [--non-goals <id[,id...]>] [--depends-on <id[,id...]>] \
                                         [--interface <text>] [--reasoning <text>] \
                                         [--append-reasoning <text>] \
                                         [--diff-budget <text>] [--proof <tests|gate|record|observe>] [--surface <id>]...
       design-actions.sh add-owned-file <task_folder> --id <woId> --path <path>
       design-actions.sh add-done-when  <task_folder> --id <woId> --text <text>
       design-actions.sh add-test       <task_folder> --id <woId> --level <text> \
                                         --description <text>
       design-actions.sh remove-test    <task_folder> --id <woId> --description <text>
       design-actions.sh remove-done-when  <task_folder> --id <woId> --text <text>
       design-actions.sh remove-owned-file <task_folder> --id <woId> --path <path>
       design-actions.sh merge          <task_folder> --into <woId> --from <woId>
       design-actions.sh read-guide     <task_folder> --path <path on disk> [--name <guide name>]
       design-actions.sh verify         <task_folder> --id <woId> --recipe <path> [--not-binding]
       design-actions.sh verify         <task_folder> --id <woId> --run <command> [--pass <form>] --cite <source>
       design-actions.sh verify         <task_folder> --id <woId> --check <text> --cite <source>
       design-actions.sh verify         <task_folder> --id <woId> --clear
       design-actions.sh render         <task_folder> --id <woId>
       design-actions.sh check          <task_folder>
       design-actions.sh --run-mode <interactive|autonomous> close <task_folder> \
                                         --recipe-fit <true|false|unsure> --recipe-path <path> --recipe-reason <text> | --no-recipe \
                                         [--critique-outcome <text>]...
       design-actions.sh distill        <task_folder>
       design-actions.sh --run-mode <interactive|autonomous> dispose <task_folder> --id <woId> \
                                         --candidate <text> --distance <same-name|same-directory|same-layer> \
                                         --cost <build|carry|agent|risk[,...]> --verdict <reuse|extend|supersede|decline> --why <text> [--confirmed] \
                                         [--path <path> --interface <text>]
EOF
}

# The four helpers every stage script needs before it touches a task folder live in one place
# (scripts/lib/task-helpers.sh): resolve_task_folder, looks_like_flag, is_blank, write_atomic.
TASK_HELPERS_LIB="${PLUGIN_ROOT}/scripts/lib/task-helpers.sh"
[ -f "$TASK_HELPERS_LIB" ] || die3 "cannot find the task-helper library at $TASK_HELPERS_LIB"
# shellcheck source=/dev/null
source "$TASK_HELPERS_LIB" || die3 "the task-helper library failed to load: $TASK_HELPERS_LIB"
# `verify` reads a recipe's `## Verifier` with the recipe readers every stage shares:
# recipe_block_into, pc_trim, pc_unquote and refuse_if_unsafe. Sourced here, before the task folder
# resolves, because the library resets TASK_PATH when it loads.
RECIPES_LIB="${PLUGIN_ROOT}/scripts/lib/recipes.sh"
# shellcheck source=/dev/null
source "$RECIPES_LIB" || die3 "the recipes library failed to load: $RECIPES_LIB"

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
    "doneWhen: " + ((.doneWhen // []) | length | tostring),
    "proof: " + (.proof // "tests")'
}

# One line naming the proof the order's owned criteria imply, printed beside the proof it declares
# (live-run row 145). $1 is the work order document, $2 its id. An order whose every owned file
# lies under the project folder produces a document, so it implies `record`, the rule
# add-owned-file applies. Otherwise the line reads criteriaOwned alone. Every kind proves a
# machine-verified criterion in its own way, so owning one implies any kind: what the order
# produces decides. The line said `tests` here once, and pushed a report or an update onto an
# invented test. An order owning criteria of which none is machine-verified implies a proof
# other than `tests`. An order owning nothing implies nothing. Printed on every create and
# update, not only on a disagreement, so one line says what the contract says about this order.
implied_proof_line() {
  local owned machine
  owned="$(printf '%s' "$1" | jq -r '(.criteriaOwned // []) | length')"
  if [ "$owned" -eq 0 ]; then
    echo "impliedProof: none, because $2 owns no criterion"
    return
  fi
  if [ "$(printf '%s' "$1" | jq -r --arg t "$PROJECT_PATH/" \
        '((.ownedFiles // []) | length > 0) and ((.ownedFiles // []) | all(startswith($t)))')" = "true" ]; then
    echo "impliedProof: record, because every file $2 owns lies under the project folder"
    return
  fi
  if [ "$(contract_ok)" != "true" ]; then
    echo "impliedProof: not read, because the contract could not be read"
    return
  fi
  # The machine-verified criteria this order owns, read the way check-design.sh reads them.
  machine="$(jq -r --argjson wo "$1" '
    [ (.criteria // [])[]? | select(type == "object") | select(.verifiedBy == "machine") | .id ] as $m
    | [ ($wo.criteriaOwned // [])[] | select(. as $c | $m | index($c) != null) ] | join(",")
  ' "$ALIGNMENT_FILE" 2>/dev/null)"
  if [ -n "$machine" ]; then
    local word
    case "$machine" in
      *,*) word="criteria" ;;
      *)   word="criterion" ;;
    esac
    echo "impliedProof: any kind, because $2 owns the machine-verified $word $machine, which every kind proves in its own way. What $2 produces decides"
  else
    echo "impliedProof: not tests, because no criterion $2 owns is machine-verified"
  fi
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
        ((.coverage.gateOrdersDeclaringTests // [])[] | "order " + .id + " is proved by the configuration gate and declares a test"),
        ((.coverage.recordOrdersDeclaringTests // [])[] | "order " + .id + " is proved by " + (if .proof == "observe" then "a model looking through a browser" else "its record" end) + " and declares a test"),
        ((.coverage.recordOrdersOwningOutsideProjectFolder // [])[] | "order " + .id + " is proved by its record and owns " + .path + " " + .reason),
        ((.coverage.recordOrdersWithNoDoneWhen // [])[] | "order " + .id + " is proved by " + (if .proof == "observe" then "a model looking through a browser" else "its record" end) + " and has no done-when row"),
        ((.coverage.observeOrdersWithNoSurface // [])[] | "order " + .id + " is proved by a model looking through a browser and names no surface"),
        ((.graph.dependencyCycles // [])[] | "dependency cycle includes " + .),
        ((.graph.orphanSupportOrders // [])[] | "order " + . + " owns nothing and no owning order depends on it"),
        ((.graph.overlappingOwnedFiles // [])[] | "orders " + (.ids | join(", ")) + " both declare " + .path),
        ((.files // [])[] | select((.schema.issueCount // 0) > 0) | "file " + .path + " does not match the design shape"),
        (.guidesRead // {} | select((.issueCount // 0) > 0) | "file " + .path + " does not match the guides-read shape: " + ([.issues[].problem] | join(", ")))
      ] | join("; ")
    ' 2>/dev/null
}

# The orders whose declared proof disagrees with what their owned criteria imply, from a check
# report (live-run row 145). This one finding never raises the exit code, so `check` prints it on
# a line of its own. open_summary_of above prints only when the verdict is not zero, and a finding
# that never raises the verdict would vanish from every line whenever it is the only one.
proof_disagreement_of() {
  printf '%s' "$1" | jq -r '
      [ (.coverage.testOrdersOwningNoMachineCriterion // [])[] | .id ] | join(", ")
    ' 2>/dev/null
}

# The `findings: N` last line of the critique file at $1, or exit 1 when the file carries none.
# No line means its critic did not finish. `close` reads it twice: once to decide the file is
# evidence worth committing, once to count it.
critique_findings_of() {
  local n
  n="$(grep -E '^findings: [0-9]+$' "$1" | tail -n 1 | sed 's/^findings: //')"
  [ -n "$n" ] || return 1
  printf '%s' "$n"
}

# Prints $1, a work order document, with $2 added to its `reasoning` as a new paragraph. The
# paragraph follows a blank line, or is the whole field when it was empty. `dispose` and
# `update --append-reasoning` both write this way, so an earlier paragraph is never lost
# (live-run rows 79 and 131).
reasoning_appended() {
  printf '%s' "$1" | jq --arg v "$2" '.reasoning = (if (.reasoning // "") == "" then $v else .reasoning + "\n\n" + $v end)'
}

# The sha256 of the file at $1, or nothing when it cannot be read. The caller resolves the hash
# command first, through records_hash__resolve_sha256_cmd.
file_sha256() {
  [ -f "$1" ] && [ -r "$1" ] || return 1
  "${RECORDS_HASH_SHA256_CMD[@]}" <"$1" | cut -d' ' -f1
}

# The guides-read record's summary lines, for `read` and `start`: `guidesRead: <n>`, and when $1
# is above zero (a resumed run, work orders already on disk) one `guide: <path>` line per entry
# ending `changed`, `unchanged` or `missing`. `changed` means the body's sha256 differs from the
# recorded one; `missing` means no readable file is at the path any more, so the resumed run
# resolves it again through the navigator. A record that is not valid JSON counts as zero here;
# `check` is what refuses it.
guides_read_lines() {
  local resumed="$1" n=0 path recorded live tab
  if [ -f "$GUIDES_FILE" ] && jq empty "$GUIDES_FILE" 2>/dev/null; then
    n="$(jq -r '(.guides // []) | if type == "array" then length else 0 end' "$GUIDES_FILE")"
  fi
  echo "guidesRead: $n"
  [ "$resumed" -gt 0 ] && [ "$n" -gt 0 ] || return 0
  records_hash__resolve_sha256_cmd || die3 "neither sha256sum nor 'shasum -a 256' was found on PATH"
  tab="$(printf '\t')"
  while IFS="$tab" read -r path recorded; do
    [ -n "$path" ] || continue
    if ! live="$(file_sha256 "$path")"; then
      echo "guide: $path missing"
    elif [ "$live" = "$recorded" ]; then
      echo "guide: $path unchanged"
    else
      echo "guide: $path changed"
    fi
  done < <(jq -r '(.guides // [])[] | select(type == "object") | [(.path // ""), (.sha256 // "")] | @tsv' "$GUIDES_FILE")
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
  guides_read_lines "$wo_count"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# start: makes sure the contract exists and research has closed before design begins, and makes
# sure the design folder exists. Idempotent, the same as research's own `start`: no aggregate
# file here could be overwritten by a second call.
#
# The grounding hash (ideal/design.md, "Acting on a claim about a mechanism"): research's `check`
# records one sha256 per mechanismHints[].approach when it closes clean. `start` re-derives the list
# and prints a NOTE: per position that differs. Never a refusal: the claim may still be right, but
# the evidence no longer covers it.
# ------------------------------------------------------------------------------------------------

# One sha256 per approach in $1/task.json, as a JSON array, in order. Each approach is hashed as
# its own compact JSON string, one line each, so a multi-line approach never breaks the loop.
# research-actions.sh computes the same list the same way at its close.
mechanism_hashes_json() {
  local hashes='[]' line h
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    h="$(printf '%s' "$line" | "${RECORDS_HASH_SHA256_CMD[@]}" | cut -d' ' -f1)"
    hashes="$(printf '%s' "$hashes" | jq --arg h "$h" '. + [$h]')"
  done < <(jq -c '.mechanismHints[]? | .approach' "$1/task.json" 2>/dev/null)
  printf '%s' "$hashes"
}

do_start() {
  [ "$#" -eq 0 ] || die3 "start: unrecognized argument: $1"

  [ "$(contract_ok)" = "true" ] \
    || die2 "start: $ALIGNMENT_FILE not found, unreadable, or not a contract. Run the scope skill on this task first"
  [ -f "$RESEARCH_CHECK_FILE" ] && [ "$(jq -r '.exitCode // 1' "$RESEARCH_CHECK_FILE" 2>/dev/null)" = "0" ] \
    || die6 "start: research has not closed on this task ($RESEARCH_CHECK_FILE is absent or not clean). Research is required; run the research skill first"

  records_hash__resolve_sha256_cmd || die3 "start: neither sha256sum nor 'shasum -a 256' was found on PATH"

  mark_task_in_progress "$TASK_PATH" "design started" design
  mkdir -p "$DESIGN_DIR" || die3 "start: could not create $DESIGN_DIR"

  echo "STARTED: $DESIGN_DIR"
  echo "contract-file: $ALIGNMENT_FILE"
  echo "criteria: $(contract_criteria_json | jq -r '[.[].id] | join(" ")')"
  # A resumed run has work order files on disk already, and reads only the guides that changed.
  local resumed=0
  [ -z "$(find "$DESIGN_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | head -n 1)" ] || resumed=1
  guides_read_lines "$resumed"

  local recorded live
  recorded="$(jq -c '.mechanismHashes // []' "$RESEARCH_CHECK_FILE" 2>/dev/null)"
  live="$(mechanism_hashes_json "$TASK_PATH")"
  jq -nr --argjson r "$recorded" --argjson l "$live" '
    range([($r | length), ($l | length)] | max) | select($r[.] != $l[.])
    | "NOTE: mechanism hint " + ((. + 1) | tostring) + " in task.json was edited after research grounded it; read it as ungrounded"'
  exit 0
}

# ------------------------------------------------------------------------------------------------
# The next work order id: scan design/*.json for the highest wo<n> present and take the next
# number, starting at wo1 when none exist. See this script's own header for the known gap this
# leaves around a deleted, highest-numbered work order.
# ------------------------------------------------------------------------------------------------

next_wo_id() {
  local max this_id this_num
  max=0
  if [ -d "$DESIGN_DIR" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      jq empty "$f" 2>/dev/null || continue
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

# --proof takes one of four words. A unit whose deliverable is exported configuration is proved by
# the recipe's `## Configuration gate` lines and declares no test (live-run row 65). A unit whose
# deliverable is a document in the task folder is proved by its done-when rows and lands no commit
# in the code repository (nyc defect 17); add-owned-file below marks it `record` on its own. A unit
# whose deliverable is what a page shows is proved by a model's look through a browser at each of
# its surfaces, judged against its done-when rows after the build (live-run row 104): `observe`.
proof_word_ok() {
  case "$2" in
    tests|gate|record|observe) ;;
    *) die3 "$1: --proof takes tests, gate, record or observe, got: $2" ;;
  esac
}

do_create() {
  local title="" criteria_served="" criteria_owned="" non_goals="" depends_on=""
  local interface="" reasoning="" diff_budget="" surfaces_json='[]' proof=""
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
      --proof)
        need_value "create" "--proof" "$#" "${2:-}"
        proof_word_ok "create" "$2"
        proof="$2"; shift 2 ;;
      --surface)
        need_value "create" "--surface" "$#" "${2:-}"
        surfaces_json="$(printf '%s' "$surfaces_json" | jq --arg id "$2" '. + [$id]')"; shift 2 ;;
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
    --argjson surfaces "$surfaces_json" --arg proof "$proof" \
    '{schemaVersion: 1, id: $id, title: $title,
      criteriaServed: $criteriaServed, criteriaOwned: $criteriaOwned, nonGoals: $nonGoals,
      dependsOn: $dependsOn, ownedFiles: [], surfaces: $surfaces, interface: $interface, tests: [], doneWhen: [],
      reasoning: $reasoning, diffBudget: $diffBudget}
     + (if $proof == "" then {} else {proof: $proof} end)')"

  write_atomic "$file" "$doc"

  echo "CREATED: $file"
  wo_summary "$doc"
  implied_proof_line "$doc" "$id"

  render_wo "$id"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# update: replaces the given scalar or id-list fields on an existing work order, wholesale for
# any list passed. ownedFiles, tests and doneWhen are not settable here; use their own add-
# actions. --reasoning replaces the whole field; --append-reasoning adds a paragraph after a
# blank line and keeps what is there, the write `dispose` makes (live-run row 131). The two
# together are refused: one call cannot both replace the text and add to it.
# ------------------------------------------------------------------------------------------------

do_update() {
  local id="" title="" criteria_served="" criteria_owned="" non_goals="" depends_on=""
  local interface="" reasoning="" append_reasoning="" diff_budget="" surfaces_json='[]' proof=""
  local set_title=false set_served=false set_owned=false set_nongoals=false set_dependson=false
  local set_interface=false set_reasoning=false set_append=false set_diffbudget=false set_surfaces=false set_proof=false
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
      --append-reasoning)
        need_value "update" "--append-reasoning" "$#" "${2:-}"
        append_reasoning="$2"; set_append=true; shift 2 ;;
      --diff-budget)
        need_value "update" "--diff-budget" "$#" "${2:-}"
        diff_budget="$2"; set_diffbudget=true; shift 2 ;;
      --proof)
        need_value "update" "--proof" "$#" "${2:-}"
        proof_word_ok "update" "$2"
        proof="$2"; set_proof=true; shift 2 ;;
      --surface)
        need_value "update" "--surface" "$#" "${2:-}"
        surfaces_json="$(printf '%s' "$surfaces_json" | jq --arg id "$2" '. + [$id]')"; set_surfaces=true; shift 2 ;;
      *) die3 "update: unrecognized argument: $1" ;;
    esac
  done

  is_blank "$id" && die3 "update: --id is required and must not be blank"
  id_shape_ok "$id" wo || die3 "update: --id '$id' is not a valid wo<n> id shape"
  if [ "$set_append" = "true" ]; then
    is_blank "$append_reasoning" && die3 "update: --append-reasoning must not be blank"
    [ "$set_reasoning" != "true" ] \
      || die3 "update: --reasoning replaces the field and --append-reasoning adds to it. Pass one"
  fi
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
  if [ "$set_append" = "true" ]; then
    doc="$(reasoning_appended "$doc" "$append_reasoning")"
  fi
  if [ "$set_diffbudget" = "true" ]; then
    doc="$(printf '%s' "$doc" | jq --arg v "$diff_budget" '.diffBudget = $v')"
  fi
  if [ "$set_surfaces" = "true" ]; then
    doc="$(printf '%s' "$doc" | jq --argjson v "$surfaces_json" '.surfaces = $v')"
  fi
  if [ "$set_proof" = "true" ]; then
    doc="$(printf '%s' "$doc" | jq --arg v "$proof" '.proof = $v')"
  fi

  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  wo_summary "$doc"
  implied_proof_line "$doc" "$id"

  # A proof that is no longer tests leaves the prose fields naming the test files the order
  # once declared. A reviewer then holds the order to them (live-run row 115). Named, never
  # refused. A test file is a path segment tests/ or test/, or a name ending .spec.<ext>,
  # .test.<ext> or Test.php.
  local still_names
  if [ "$set_proof" = "true" ] && [ "$proof" != "tests" ]; then
    still_names="$(printf '%s' "$doc" | jq -r '
      [ ("interface", "reasoning", "diffBudget") as $f
        | select((.[$f] // "") | test("(^|[^A-Za-z0-9_])tests?/|\\.(spec|test)\\.[A-Za-z0-9]+($|[^A-Za-z0-9_])|Test\\.php($|[^A-Za-z0-9_])"))
        | $f ] | join(", ")')"
    [ -z "$still_names" ] || echo "stillNamesATest: $still_names"
  fi

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
  # An order whose every owned file lies under the project folder delivers a document, not code.
  # So its proof is `record` (nyc defect 17): no test, no commit in the code repository, its
  # done-when rows judged instead. The task folder's deliverables/ is the usual place; a report
  # may land beside earlier reports elsewhere in the project folder (live-run row 127). Marked
  # here, where the files arrive, and only on an order with no proof field. `create` writes one
  # only when --proof was passed, so a proof design set by hand stays, `tests` included. A code
  # file added later leaves `record` in place, and the design check names it; `update --proof
  # tests` is the repair.
  local inferred
  inferred="$(printf '%s' "$doc" | jq -r --arg t "$PROJECT_PATH/" \
    'if (has("proof") | not) and ((.ownedFiles // []) | all(startswith($t))) then "record" else "" end')"
  [ "$inferred" != "record" ] || doc="$(printf '%s' "$doc" | jq '.proof = "record"')"
  # A record order's range is the project folder's history, so a file the project ignores can
  # never land in it: build-record would refuse the empty range (exit 71) on every attempt. The
  # project ignores records/ at every depth, the folder of derived check output. git finds the
  # repository upward from the task folder. Only a path under the project folder is asked. A
  # path outside it is a code path, which the design check names on a record order. The refusal
  # comes before the proof-set line, so nothing reports a write that did not happen.
  if [ "$(printf '%s' "$doc" | jq -r '.proof // "tests"')" = "record" ] \
     && [ "${path_val#"$PROJECT_PATH"/}" != "$path_val" ] \
     && git -C "$TASK_PATH" check-ignore -q -- "$path_val" 2>/dev/null; then
    die3 "add-owned-file: the project ignores $path_val, so a commit can never hold it and a record order owning it can never be recorded. records/ is derived check output the project keeps out of history. Put the deliverable in a folder the project commits, such as $TASK_PATH/deliverables/."
  fi
  [ "$inferred" != "record" ] || echo "proof-set: record, because every owned file of $id lies under the project folder"
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

  # A test on a `tests` order is a file a test author writes, red then green. A description that
  # names one of the order's own surfaces reads as review's surface row over that page. That row
  # is no file and runs after every order closes (live-run row 97). The design check counts tests and
  # reads no sentence, so the refusal sits here. The id must appear as a whole word, case as
  # written; an order with no surfaces is never refused.
  local proof surface_hit
  proof="$(jq -r '.proof // "tests"' "$file")"
  if [ "$proof" = "tests" ]; then
    surface_hit="$(jq -r --arg d "$description" \
      '[$d | match("[A-Za-z0-9_-]+"; "g").string] as $words
       | [(.surfaces // [])[] | select(. as $s | any($words[]; . == $s))] | first // ""' "$file")"
    [ -z "$surface_hit" ] \
      || die3 "add-test: the description names the surface $surface_hit, so it reads as the review stage's surface row over that page. That row is not a test a test author writes as a file. A machine criterion is proved one of two ways. Describe here what a spec observes, and the tests step writes it as a file the test-execution recipe's own glob matches. Or reopen scope so the criterion reads verified by person, and the review stage's surface row over $surface_hit verifies it"
  fi
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
# remove-test: drops one declared test, named by its description, the one field design writes on
# a test. The sizing rules end with a test ceasing to exist. Until this action existed, that edit
# ran through jq outside the one producer (live-run row 74). The last test is refused on the same
# rule check-design.sh applies: a `tests` order that owns a machine-verified criterion needs one.
# Add the replacement first, then remove. A person-only order may go to zero.
# ------------------------------------------------------------------------------------------------

do_remove_test() {
  local id="" description=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        need_value "remove-test" "--id" "$#" "${2:-}"
        id="$2"; shift 2 ;;
      --description)
        need_value "remove-test" "--description" "$#" "${2:-}"
        description="$2"; shift 2 ;;
      *) die3 "remove-test: unrecognized argument: $1" ;;
    esac
  done
  require_wo_id_arg "remove-test" "$id"
  is_blank "$description" && die3 "remove-test: --description is required and must not be blank"

  local file doc matched total proof
  file="$(wo_file_for "$id")"
  jq empty "$file" 2>/dev/null || die3 "remove-test: $file exists but is not valid JSON"
  matched="$(jq -r --arg d "$description" '[(.tests // [])[] | select(.description == $d)] | length' "$file")"
  [ "$matched" -gt 0 ] || die2 "remove-test: $id declares no test with the description '$description'"
  total="$(jq -r '(.tests // []) | length' "$file")"
  proof="$(jq -r '.proof // "tests"' "$file")"
  if [ "$proof" = "tests" ] && [ "$total" -eq "$matched" ]; then
    # The machine-verified criteria this order owns, read the way check-design.sh reads them.
    local machine_owned
    machine_owned="$(jq -r --slurpfile wo "$file" '
      [ (.criteria // [])[]? | select(type == "object") | select(.verifiedBy == "machine") | .id ] as $machine
      | [ ($wo[0].criteriaOwned // [])[] | select(. as $c | $machine | index($c) != null) ] | join(",")
    ' "$ALIGNMENT_FILE" 2>/dev/null)"
    [ -z "$machine_owned" ] \
      || die3 "remove-test: that is the last test on $id, and $id owns the machine-verified criteria $machine_owned. check-design.sh refuses a tests order that owns one with no test. Add the replacement test first, or set --proof gate when the deliverable is configuration, or --proof record when it is a document in the task folder"
  fi
  doc="$(jq --arg d "$description" '.tests = [(.tests // [])[] | select(.description != $d)]' "$file")"
  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  echo "removed-tests: $matched"
  wo_summary "$doc"
  render_wo "$id"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# remove-done-when and remove-owned-file: the reverse of add-done-when and add-owned-file, the
# same move remove-test makes one field over (live-run row 76). A row is named by its exact text,
# the way add-done-when wrote it and remove-test names a test. No report numbers a done-when row,
# so an index would be a number counted from a rendered list. Every row carrying that text goes,
# and the count is printed. A path is named as it was added. The last owned file is refused on the
# schema's own rule: an order that names no file hands the builder no boundary. On a `record`
# order, the inference add-owned-file makes runs again in reverse. An order left with no owned
# file under the project folder loses `proof`. It does not stay `record` on the strength of
# files it no longer owns.
# ------------------------------------------------------------------------------------------------

do_remove_done_when() {
  local id="" text=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        need_value "remove-done-when" "--id" "$#" "${2:-}"
        id="$2"; shift 2 ;;
      --text)
        need_value "remove-done-when" "--text" "$#" "${2:-}"
        text="$2"; shift 2 ;;
      *) die3 "remove-done-when: unrecognized argument: $1" ;;
    esac
  done
  require_wo_id_arg "remove-done-when" "$id"
  is_blank "$text" && die3 "remove-done-when: --text is required and must not be blank"

  local file doc matched
  file="$(wo_file_for "$id")"
  jq empty "$file" 2>/dev/null || die3 "remove-done-when: $file exists but is not valid JSON"
  matched="$(jq -r --arg t "$text" '[(.doneWhen // [])[] | select(. == $t)] | length' "$file")"
  [ "$matched" -gt 0 ] || die2 "remove-done-when: $id carries no done-when row with the text '$text'"
  doc="$(jq --arg t "$text" '.doneWhen = [(.doneWhen // [])[] | select(. != $t)]' "$file")"
  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  echo "removed-done-when: $matched"
  wo_summary "$doc"
  render_wo "$id"
  exit 0
}

do_remove_owned_file() {
  local id="" path_val=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        need_value "remove-owned-file" "--id" "$#" "${2:-}"
        id="$2"; shift 2 ;;
      --path)
        need_value "remove-owned-file" "--path" "$#" "${2:-}"
        path_val="$2"; shift 2 ;;
      *) die3 "remove-owned-file: unrecognized argument: $1" ;;
    esac
  done
  require_wo_id_arg "remove-owned-file" "$id"
  is_blank "$path_val" && die3 "remove-owned-file: --path is required and must not be blank"

  local file doc
  file="$(wo_file_for "$id")"
  jq empty "$file" 2>/dev/null || die3 "remove-owned-file: $file exists but is not valid JSON"
  jq -e --arg p "$path_val" '((.ownedFiles // []) | index($p)) != null' "$file" >/dev/null 2>&1 \
    || die2 "remove-owned-file: $id does not own $path_val"
  [ "$(jq -r '(.ownedFiles // []) | length' "$file")" -gt 1 ] \
    || die3 "remove-owned-file: $path_val is the only file $id owns, and an order that names no file hands the builder no boundary (design-schema.json, ownedFiles). Add the replacement first, or fold the order into another with merge"
  doc="$(jq --arg p "$path_val" '.ownedFiles = [(.ownedFiles // [])[] | select(. != $p)]' "$file")"
  local unset_proof
  unset_proof="$(printf '%s' "$doc" | jq -r --arg t "$PROJECT_PATH/" \
    'if (.proof // "") == "record" and ((.ownedFiles // []) | any(startswith($t)) | not) then "yes" else "" end')"
  if [ "$unset_proof" = "yes" ]; then
    doc="$(printf '%s' "$doc" | jq 'del(.proof)')"
    echo "proof-unset: record, because no owned file of $id lies under the project folder now; every reader takes the order as tests until --proof says otherwise"
  fi
  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  echo "removed-owned-file: $path_val"
  wo_summary "$doc"
  render_wo "$id"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# verify: writes the order's own proof from the knowledge that covers it, the `verify` list, and
# is that field's one writer. `--recipe` replaces the list with the covering agentic recipe's
# `## Verifier`. Each entry of its `verifier:` block becomes a run entry with its `id`, `run` and
# `pass`, the shape the dev-guides proposal asks every recipe to use. Each numbered item of the
# section's prose becomes a check entry, verbatim, wrapped lines joined: today's nine recipes hold
# only prose. A paragraph is not a check, and no command is ever made from prose. Every entry
# cites the recipe and is binding, unless --not-binding says research marked the source as one
# this project did not accept. `--run` or `--check` adds one entry from a research finding. It
# cites its source and is never binding, and a second entry with the same text replaces the
# first. `--clear` empties the list. A run line carrying a shell character, and a pass outside
# the three forms, are refused here, before the gate would refuse them at build time.
# ------------------------------------------------------------------------------------------------

# The numbered items of the `## Verifier` prose of the recipe $1, one per line, wrapped lines
# joined with a space. Fenced blocks and the `verifier:` block are skipped. The block ends at the
# first line that begins with neither a space, a tab nor a dash.
verifier_prose_items() {
  awk '
    function flush() { if (item != "") print item; item = "" }
    /^## / { flush(); inSection = ($0 == "## Verifier"); inFence = 0; inBlock = 0; next }
    !inSection { next }
    /^```/ { flush(); inFence = !inFence; next }
    inFence { next }
    /^verifier:/ { flush(); inBlock = 1; next }
    inBlock && /^[^ \t-]/ { inBlock = 0 }
    inBlock { next }
    /^[0-9]+\. / { flush(); item = $0; sub(/^[0-9]+\. +/, "", item); sub(/[ \t]+$/, "", item); next }
    /^[ \t]*$/ { flush(); next }
    item != "" { line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line); item = item " " line; next }
    END { flush() }
  ' "$1"
}

# One pass form of the three the dev-guides Verifier block allows. $1 the action, $2 the value.
verify_pass_ok() {
  case "$2" in
    'exit 0'|'stdout empty'|'stdout contains '?*) ;;
    *) die3 "$1: a pass is exit 0, stdout empty or stdout contains <text>, got: $2" ;;
  esac
}

# The entry held between lines of the `verifier:` block, the way PC_* holds a precondition.
VF_ID=""; VF_RUN=""; VF_PASS=""; VF_ENTRIES='[]'
# Appends the held entry to VF_ENTRIES and clears it. $1 the recipe.
verify_flush_entry() {
  [ -n "$VF_ID$VF_RUN$VF_PASS" ] || return 0
  [ -n "$VF_RUN" ] || die3 "verify: the verifier: entry ${VF_ID:-with no id} in $1 holds no run"
  [ -n "$VF_PASS" ] || die3 "verify: the verifier: entry ${VF_ID:-with no id} in $1 holds no pass. Nothing here guesses what passing means"
  verify_pass_ok "verify" "$VF_PASS"
  refuse_if_unsafe "design-actions" "$1" "$VF_RUN" || die3 "verify: the run line above is refused"
  VF_ENTRIES="$(printf '%s' "$VF_ENTRIES" | jq -c --arg id "$VF_ID" --arg run "$VF_RUN" --arg pass "$VF_PASS" \
    '. + [ (if $id == "" then {} else {id: $id} end) + {run: $run, pass: $pass} ]')"
  VF_ID=""; VF_RUN=""; VF_PASS=""
}

do_verify() {
  local id="" recipe="" run="" check="" cite="" pass="" binding=true clear=false modes=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)     need_value "verify" "--id" "$#" "${2:-}"; id="$2"; shift 2 ;;
      --recipe) need_value "verify" "--recipe" "$#" "${2:-}"; recipe="$2"; modes=$((modes + 1)); shift 2 ;;
      --run)    need_value "verify" "--run" "$#" "${2:-}"; run="$2"; modes=$((modes + 1)); shift 2 ;;
      --check)  need_value "verify" "--check" "$#" "${2:-}"; check="$2"; modes=$((modes + 1)); shift 2 ;;
      --cite)   need_value "verify" "--cite" "$#" "${2:-}"; cite="$2"; shift 2 ;;
      --pass)   need_value "verify" "--pass" "$#" "${2:-}"; pass="$2"; shift 2 ;;
      --not-binding) binding=false; shift ;;
      --clear)  clear=true; modes=$((modes + 1)); shift ;;
      *) die3 "verify: unrecognized argument: $1" ;;
    esac
  done
  require_wo_id_arg "verify" "$id"
  [ "$modes" -eq 1 ] || die3 "verify: pass exactly one of --recipe, --run, --check or --clear"
  [ -z "$pass" ] || [ -n "$run" ] || die3 "verify: --pass belongs to --run"
  [ "$binding" = "true" ] || [ -n "$recipe" ] || die3 "verify: --not-binding belongs to --recipe. A research line is never binding"
  if [ -n "$run$check" ]; then
    is_blank "$cite" && die3 "verify: --cite is required with --run and --check: every line names the source it came from"
  else
    [ -z "$cite" ] || die3 "verify: --cite belongs to --run and --check. A recipe's entries cite the recipe"
  fi
  local file doc entries_json source_name before
  file="$(wo_file_for "$id")"
  jq empty "$file" 2>/dev/null || die3 "verify: $file exists but is not valid JSON"
  doc="$(cat "$file")"
  before="$(printf '%s' "$doc" | jq '(.verify // []) | length')"

  if [ "$clear" = "true" ]; then
    doc="$(printf '%s' "$doc" | jq 'del(.verify)')"
    echo "cleared: $before"
  elif [ -n "$recipe" ]; then
    [ -f "$recipe" ] || die2 "verify: no file at $recipe. Give the path the navigator returned"
    grep -q '^## Verifier[[:space:]]*$' "$recipe" || die3 "verify: $recipe has no ## Verifier section"
    source_name="$recipe"
    local block_file state line trimmed item
    block_file="$(mktemp)" || die3 "verify: could not create a temporary file"
    state="$(recipe_block_into "$recipe" "Verifier" "verifier" "$block_file")"
    VF_ID=""; VF_RUN=""; VF_PASS=""; VF_ENTRIES='[]'
    if [ "$state" = "ok" ]; then
      while IFS= read -r line; do
        case "$line" in ''|[[:space:]-]*) ;; *) break ;; esac
        trimmed="$(pc_trim "$line")"
        case "$trimmed" in
          '- id:'*) verify_flush_entry "$recipe"; VF_ID="$(pc_trim "${trimmed#- id:}")" ;;
          'run:'*)  VF_RUN="$(pc_unquote "$(pc_trim "${trimmed#run:}")")" ;;
          'pass:'*) VF_PASS="$(pc_unquote "$(pc_trim "${trimmed#pass:}")")" ;;
        esac
      done <"$block_file"
      verify_flush_entry "$recipe"
    fi
    rm -f "$block_file"
    entries_json="$VF_ENTRIES"
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      entries_json="$(printf '%s' "$entries_json" | jq -c --arg c "$item" '. + [{check: $c}]')"
    done < <(verifier_prose_items "$recipe")
    [ "$(printf '%s' "$entries_json" | jq 'length')" -gt 0 ] \
      || die3 "verify: the ## Verifier of $recipe holds no verifier: entry and no numbered check, so there is nothing to carry"
    doc="$(printf '%s' "$doc" | jq --argjson e "$entries_json" --arg c "$recipe" --argjson b "$binding" \
      '.verify = [ $e[] + {cites: $c, binding: $b} ]')"
    [ "$before" -eq 0 ] || echo "replaced: $before"
  else
    local entry
    if [ -n "$run" ]; then
      [ -n "$pass" ] || pass="exit 0"
      verify_pass_ok "verify" "$pass"
      refuse_if_unsafe "design-actions" "--run" "$run" || die3 "verify: the run line above is refused"
      entry="$(jq -nc --arg r "$run" --arg p "$pass" --arg c "$cite" '{run: $r, pass: $p, cites: $c, binding: false}')"
    else
      entry="$(jq -nc --arg k "$check" --arg c "$cite" '{check: $k, cites: $c, binding: false}')"
    fi
    doc="$(printf '%s' "$doc" | jq --argjson e "$entry" '
      .verify = ([ (.verify // [])[] | select(((.run // .check) == ($e.run // $e.check)) | not) ] + [$e])')"
    source_name="$cite"
    binding=false
  fi

  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  printf '%s' "$doc" | jq -r '"verify: " + ([ (.verify // [])[] | select(has("run")) ] | length | tostring) + " run, "
    + ([ (.verify // [])[] | select(has("check")) ] | length | tostring) + " check"'
  [ "$clear" = "true" ] || echo "source: $source_name, binding $binding"
  render_wo "$id"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# merge: folds one order into another (SKILL.md, "Size a work order"). Every list field is the
# ordered union without duplicates, the survivor's entries first. `interface` and `reasoning` are
# appended under a line naming the folded order. A disposition `dispose` wrote on it is not
# lost, and a reader can tell which order stated what. The summary says which scalars were carried
# and which were dropped. A live run that saw only list counts read the append as a drop and
# rewrote the interface by hand (live-run row 78). `title`, `diffBudget`
# and `proof` stay the survivor's, so the two proofs must agree. A `gate` order folded into a
# `tests` order would carry tests it may not declare, or the reverse. The folded order's
# json and md are removed. Every other order's `dependsOn` naming it is rewritten to the survivor,
# without duplicates, and the survivor never depends on itself. This is the delete path the id
# comment above once said did not exist, and the gap named there now applies here. Commits
# nothing, the same as every edit before `close`.
# ------------------------------------------------------------------------------------------------

do_merge() {
  local into="" from=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --into)
        need_value "merge" "--into" "$#" "${2:-}"
        into="$2"; shift 2 ;;
      --from)
        need_value "merge" "--from" "$#" "${2:-}"
        from="$2"; shift 2 ;;
      *) die3 "merge: unrecognized argument: $1" ;;
    esac
  done
  is_blank "$into" && die3 "merge: --into is required and must not be blank"
  is_blank "$from" && die3 "merge: --from is required and must not be blank"
  id_shape_ok "$into" wo || die3 "merge: --into '$into' is not a valid wo<n> id shape"
  id_shape_ok "$from" wo || die3 "merge: --from '$from' is not a valid wo<n> id shape"
  [ "$into" != "$from" ] || die3 "merge: --into and --from both name $into"
  wo_exists "$into" || die2 "merge: no work order $into in $DESIGN_DIR"
  wo_exists "$from" || die2 "merge: no work order $from in $DESIGN_DIR"

  local into_file from_file into_proof from_proof
  into_file="$(wo_file_for "$into")"
  from_file="$(wo_file_for "$from")"
  jq empty "$into_file" 2>/dev/null || die3 "merge: $into_file exists but is not valid JSON"
  jq empty "$from_file" 2>/dev/null || die3 "merge: $from_file exists but is not valid JSON"
  into_proof="$(jq -r '.proof // "tests"' "$into_file")"
  from_proof="$(jq -r '.proof // "tests"' "$from_file")"
  [ "$into_proof" = "$from_proof" ] \
    || die3 "merge: $into is proved by $into_proof and $from by $from_proof. Set one order's --proof so the two agree, then merge"

  # The union keeps first occurrence order, so `unique`, which sorts, is not used here.
  local doc
  doc="$(jq --slurpfile f "$from_file" --arg from "$from" '
    $f[0] as $f
    | def dedupe: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
      def union(k): if (has(k) or ($f | has(k))) then .[k] = (((.[k] // []) + ($f[k] // [])) | dedupe) else . end;
      def append(k): if (($f[k] // "") == "" or ($f[k] == .[k])) then . elif ((.[k] // "") == "") then .[k] = "From " + $from + ":\n" + $f[k] else .[k] = .[k] + "\n\nFrom " + $from + ":\n" + $f[k] end;
    . as $i
    | union("criteriaServed") | union("criteriaOwned") | union("nonGoals") | union("dependsOn")
    | union("ownedFiles") | union("surfaces") | union("tests") | union("doneWhen") | union("reuses") | union("verify")
    | .dependsOn = [ (.dependsOn // [])[] | select(. != $from and . != $i.id) ]
    | append("interface") | append("reasoning")
  ' "$into_file")"

  local k before after
  for k in criteriaServed criteriaOwned nonGoals dependsOn ownedFiles surfaces tests doneWhen reuses verify; do
    before="$(jq -r --arg k "$k" '(.[$k] // []) | length' "$into_file")"
    after="$(printf '%s' "$doc" | jq -r --arg k "$k" '(.[$k] // []) | length')"
    echo "$k: $before -> $after"
  done
  local carried
  carried="$(jq -r '[ (if (.interface // "") != "" then "interface" else empty end),
                     (if (.reasoning // "") != "" then "reasoning" else empty end) ] | join(", ")' "$from_file")"
  echo "carried: ${carried:-none}"
  echo "dropped: title, diffBudget; the survivor's stand"
  echo "title: $(jq -r '.title' "$into_file"), the survivor's"
  write_atomic "$into_file" "$doc"

  # Every other order that depended on the folded one now depends on the survivor.
  local f other_id other_doc
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$f" != "$into_file" ] && [ "$f" != "$from_file" ] || continue
    jq -e --arg from "$from" '((.dependsOn // []) | index($from)) != null' "$f" >/dev/null 2>&1 || continue
    other_id="$(jq -r '.id' "$f")"
    other_doc="$(jq --arg from "$from" --arg into "$into" '
      .dependsOn = ((.dependsOn // []) | map(if . == $from then $into else . end)
        | reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end))' "$f")"
    write_atomic "$f" "$other_doc"
    echo "REWRITTEN: $f"
    render_wo "$other_id"
  done < <(find "$DESIGN_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)

  rm -f "$from_file" "$DESIGN_DIR/$from.md"
  echo "REMOVED: $from_file"
  echo "removed: $DESIGN_DIR/$from.md"
  echo "UPDATED: $into_file"
  wo_summary "$doc"
  render_wo "$into"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# read-guide: records that design opened a guide body, by path, with the body's sha256 and the
# UTC date (live-run row 77). --name carries the name research gave the guide, so the entry joins
# the finding that named it. One entry per path; a second read of the same path replaces its
# entry, the way `dispose` replaces a `reuses` entry, and keeps the name when --name is not passed
# again. The path is stored absolute, because a resumed run compares by it. Commits nothing, the
# same as every edit before `close`.
# ------------------------------------------------------------------------------------------------

do_read_guide() {
  local path_val="" name=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --path) need_value "read-guide" "--path" "$#" "${2:-}"; path_val="$2"; shift 2 ;;
      --name) need_value "read-guide" "--name" "$#" "${2:-}"; name="$2"; shift 2 ;;
      *) die3 "read-guide: unrecognized argument: $1" ;;
    esac
  done
  is_blank "$path_val" && die3 "read-guide: --path is required and must not be blank"
  [ -f "$path_val" ] || die2 "read-guide: no file at $path_val. Give the path the navigator's lookup returned, or the project's own source file"
  [ -r "$path_val" ] || die3 "read-guide: $path_val exists but is not readable"
  records_hash__resolve_sha256_cmd || die3 "read-guide: neither sha256sum nor 'shasum -a 256' was found on PATH"

  local abs sha
  abs="$(cd -- "$(dirname -- "$path_val")" 2>/dev/null && pwd -P)/$(basename -- "$path_val")"
  sha="$(file_sha256 "$abs")"
  [ -n "$sha" ] || die3 "read-guide: could not hash $abs"

  local doc existed entry
  if [ -f "$GUIDES_FILE" ]; then
    jq empty "$GUIDES_FILE" 2>/dev/null || die3 "read-guide: $GUIDES_FILE exists but is not valid JSON"
    doc="$(cat "$GUIDES_FILE")"
  else
    doc='{"schemaVersion": 1, "guides": []}'
  fi
  existed="$(printf '%s' "$doc" | jq -r --arg p "$abs" '[(.guides // [])[]? | select(type == "object" and .path == $p)] | length' 2>/dev/null)"
  # Without --name, the name the earlier entry recorded stays: the join to research's finding
  # must survive the re-read a resumed run makes.
  if is_blank "$name"; then
    name="$(printf '%s' "$doc" | jq -r --arg p "$abs" '[(.guides // [])[]? | select(type == "object" and .path == $p) | .name? // ""] | first // ""' 2>/dev/null)"
  fi
  entry="$(jq -nc --arg p "$abs" --arg s "$sha" --arg d "$(date -u +%Y-%m-%d)" --arg n "$name" \
    '{path: $p, sha256: $s, readAt: $d} + (if $n == "" then {} else {name: $n} end)')"
  doc="$(printf '%s' "$doc" | jq --argjson e "$entry" \
    '.guides = ([(.guides // [])[]? | select(type == "object" and .path != $e.path)]) + [$e]' 2>/dev/null)"
  [ -n "$doc" ] || die3 "read-guide: $GUIDES_FILE is valid JSON but not this record's shape; check-design.sh names what is wrong"
  write_atomic "$GUIDES_FILE" "$doc"
  echo "RECORDED: $GUIDES_FILE"
  echo "guide: $abs"
  echo "sha256: $sha"
  if [ "${existed:-0}" -gt 0 ]; then echo "entry: updated"; else echo "entry: new"; fi
  echo "guidesRead: $(printf '%s' "$doc" | jq -r '.guides | length')"
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
  local rc verdict lines disagrees
  mkdir -p "$TASK_PATH/records" || die3 "check: could not create $TASK_PATH/records"
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
  disagrees="$(proof_disagreement_of "$(cat "$CHECK_FILE")")"
  echo "impliedProofDisagrees: ${disagrees:-none}"
  [ -z "$disagrees" ] \
    || echo "next: each order above owns a machine-verified criterion after all, or its proof is the gate, the record or the observation"
  # The orders whose proof cites a source this project did not accept. A person sees them before
  # the close, which is the design's approval.
  echo "verifyNotBinding: $(find "$DESIGN_DIR" -mindepth 1 -maxdepth 1 -type f -name 'wo*.json' 2>/dev/null | sort \
    | while IFS= read -r f; do jq -r 'select(any((.verify // [])[]; .binding == false)) | .id' "$f" 2>/dev/null; done \
    | paste -s -d ',' - | sed 's/,/, /g; s/^$/none/')"
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
  [ -n "$RUN_MODE" ] \
    || die3 "close: --run-mode is required. The close record says who was present, and that is never assumed"
  local fit="" fit_path="" fit_reason="" no_recipe=false fit_json="" outcome=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --recipe-fit)    need_value "close" "--recipe-fit" "$#" "${2:-}";    fit="$2"; shift 2 ;;
      --recipe-path)   need_value "close" "--recipe-path" "$#" "${2:-}";   fit_path="$2"; shift 2 ;;
      --recipe-reason) need_value "close" "--recipe-reason" "$#" "${2:-}"; fit_reason="$2"; shift 2 ;;
      --no-recipe)     no_recipe=true; shift ;;
      --critique-outcome)
        need_value "close" "--critique-outcome" "$#" "${2:-}"
        is_blank "$2" && die3 "close: --critique-outcome must not be blank"
        [ "$RUN_MODE" != "autonomous" ] \
          || die3 "close: --critique-outcome is a person's answer to the findings, and an autonomous close has nobody to answer them. The record says none"
        outcome="${outcome:+$outcome
}$2"; shift 2 ;;
      *) die3 "close: unrecognized argument: $1" ;;
    esac
  done
  if [ "$no_recipe" = true ]; then
    [ -z "$fit$fit_path$fit_reason" ] || die3 "close: --no-recipe means no recipe body was read, so it cannot come with a --recipe-fit"
  else
    case "$fit" in true|false|unsure) ;; '') die3 "close: pass --recipe-fit with --recipe-path and --recipe-reason, or --no-recipe when no recipe body was read" ;;
      *) die3 "close: --recipe-fit must be true, false or unsure, got '$fit'" ;; esac
    is_blank "$fit_path" && die3 "close: --recipe-path is required with --recipe-fit. It names the recipe body that was judged"
    is_blank "$fit_reason" && die3 "close: --recipe-reason is required with --recipe-fit. A verdict with no reason cannot be read later"
    fit_json="$(jq -nc --arg path "$fit_path" --arg fits "$fit" --arg reason "$fit_reason" '{path: $path, fits: $fits, reason: $reason}')"
  fi

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
        die4 "close: a work order file, or the guides-read record, does not match its shape. Fix it and close again. Open: $open_summary"
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
    --arg runMode "$RUN_MODE" --arg closedBy "$closed_by" --arg pluginVersion "$(plugin_version)" \
    '{schemaVersion: 1, pluginVersion: $pluginVersion, closedAt: $closedAt, runMode: $runMode, closedBy: $closedBy, hash: $hash}')"
  [ -z "$fit_json" ] || doc="$(printf '%s' "$doc" | jq --argjson rf "$fit_json" '.recipeFit = $rf')"

  # Each finished critique moves out of `records/`, which the project ignores, and into the design
  # folder, which this close commits. The record used to cite the paths under `records/`. A reader
  # a month later, on another branch or another machine, found a count and three paths the
  # repository never held (live-run row 176). A critique is not reproducible: the critics run at
  # opus, so a second dispatch answers with a different table. On an unattended close nobody read
  # the findings at the time either, and the count was then the whole surviving statement. The move
  # runs before the commit below, so one commit carries the record and the evidence it names. The
  # design folder is the committed place the stage already writes: `design-render.sh` puts
  # `design/<id>.md` there beside every order. A work order id can never take this name.
  #
  # An unfinished critique moves too, under an `unfinished-` prefix (gap row 190). It is no more
  # reproducible than a finished one, and it is the only copy of what that critic wrote before it
  # stopped. The close does not count it: it is not evidence the close judged, and a findings total
  # read from it would be invented. The prefix keeps it out of the `design-critique-*.md` pattern.
  # So the count loop below skips it. And the design skill still routes a bare `close` to the
  # critique step when no finished file is there.
  local crit_file crit_dest
  while IFS= read -r crit_file; do
    [ -n "$crit_file" ] || continue
    if critique_findings_of "$crit_file" >/dev/null; then
      crit_dest="$DESIGN_DIR/$(basename -- "$crit_file")"
    else
      crit_dest="$DESIGN_DIR/unfinished-$(basename -- "$crit_file")"
      printf 'close: %s has no findings line, so its critic did not finish; it moves to %s and is not counted\n' "$crit_file" "$crit_dest" >&2
    fi
    # A directory at the destination takes the move inside itself, and `mv` exits 0. The count
    # loop below then reads one file fewer. The record names fewer files than the close carried,
    # with a total nothing on disk adds up to. Nothing in AIDA makes such a directory, so this
    # needs a hand. It is still the one shape where the record and the disk disagree in silence.
    [ ! -e "$crit_dest" ] || [ -f "$crit_dest" ] \
      || die3 "close: $crit_dest is not a file, so the critique $crit_file cannot move there. Remove it and close again"
    mv -f -- "$crit_file" "$crit_dest" || die3 "close: could not move $crit_file to $crit_dest"
  done < <(find "$TASK_PATH/records" -mindepth 1 -maxdepth 1 -type f -name 'design-critique-*.md' 2>/dev/null | sort)

  # The critique files this close carries: their paths, and the total of their `findings: N` last
  # lines. So the close says what was read before it. Absent when no critic ran. A file without
  # that line was not finished by its critic, and a count read from it would be invented, so that
  # file is left out of the record and named on stderr. The critique blocks nothing, which is the
  # design: a critic that can stop a close trains a design that writes for the critic. Beside the
  # count sits `outcome`, the --critique-outcome line: how the findings were answered, in the
  # person's words, one line per flag. A count alone said nothing about what changed (live-run row
  # 135). `none` when no flag was passed, which is every unattended close: nobody answered the
  # findings there, so the flag is refused above. A second close reads the files the first close
  # moved and records them again, so the record still names what is on disk.
  local critique_files critique_total crit_n
  critique_files=""; critique_total=0
  while IFS= read -r crit_file; do
    [ -n "$crit_file" ] || continue
    crit_n="$(critique_findings_of "$crit_file")" || {
      printf 'close: %s has no findings line, so its critic did not finish; it is not counted\n' "$crit_file" >&2
      continue
    }
    critique_total=$((critique_total + crit_n))
    critique_files="$critique_files$crit_file
"
  done < <(find "$DESIGN_DIR" -mindepth 1 -maxdepth 1 -type f -name 'design-critique-*.md' 2>/dev/null | sort)
  if [ -n "$critique_files" ]; then
    doc="$(printf '%s' "$doc" | jq --arg files "$critique_files" --argjson n "$critique_total" --arg outcome "${outcome:-none}" \
      '.critique = {files: ($files | split("\n") | map(select(length > 0))), findings: $n, outcome: $outcome}')"
  elif [ -n "$outcome" ]; then
    die3 "close: --critique-outcome names how the critique's findings were answered, and no finished critique file is under $TASK_PATH/records or $DESIGN_DIR to record it beside"
  fi

  write_atomic "$CLOSED_FILE" "$doc"
  # The stage boundary: the task folder is committed, with the order count the check just
  # walked and who closed as the reason. Closing again commits again, over the new hash.
  commit_stage_close "$TASK_PATH" design "Close design for $(jq -r '.id' "$TASK_PATH/task.json")" \
    "$(printf '%s' "$check_report_json" | jq -r '.files | length | if . == 1 then "1 work order" else "\(.) work orders" end'), closed by $closed_by"
  echo "CLOSED: $CLOSED_FILE"
  echo "closedBy: $closed_by"
  echo "runMode: $RUN_MODE"
  echo "hash: $hash"
  [ -z "$critique_files" ] || printf '%s\n' "${outcome:-none}" | sed 's/^/critiqueOutcome: /'
  exit 0
}

# ------------------------------------------------------------------------------------------------
# dispose: records a reuse decision on a work order by table, never by the model's own reasoning
# (ideal/design.md, "The reuse decision lands here"; version 5's prior-art-disposition.sh). The
# caller gives the candidate, its closeness, the cost dimensions compared, the verdict and why. The
# table decides what stands, and the outcome lands in `reasoning`, the write `update` makes.
#
# `--path` and `--interface`, given together, add one entry to the order's `reuses`: where the
# reused thing lives and the shape it exposes. The tests brief carries that list, because the test
# author may not open production source and a reused module belongs to no work order (live-run
# row 69). A second dispose naming the same path replaces its entry, and `reasoning` gains one
# paragraph per call, so every candidate's verdict survives. Neither flag, and the order's
# `reuses` is left as it was.
#
# The table. Rows are tried in order and the first that applies decides. Extend is the downgrade
# because it removes nothing. A reuse or extend citing no cost has nothing to downgrade to, so it
# stands and the thin reasoning is recorded for a person to see (version 5's rule). A decline
# compares nothing: the candidate was weighed and set aside, and the reason says what was weighed.
# It is a recorded decision, not a downgrade, so it stands in both modes (live-run row 79).
#   distance    cost cited       verdict       mode        outcome
#   any         any              decline       any         stands: nothing compared; the reason names what was weighed
#   any         none recognised  reuse|extend  any         stands: nothing to downgrade to; the reasoning says no cost was cited
#   any         none recognised  supersede     attended    refused: a supersede naming no cost compared nothing; ask the person
#   any         none recognised  supersede     unattended  extend: nobody to ask
#   any         build only       supersede     any         extend: build is paid once, carry, agent and risk forever
#   same-layer  any              supersede     any         extend: sharing only a layer, it is not absorbed; a second implementation
#   name|dir    recurring        supersede     attended    stands with --confirmed, else refused: it widens the task and owes a migration
#   name|dir    recurring        supersede     unattended  extend: no person to ask; re-surfaces on the next attended run
#   any         recognised       reuse|extend  any         stands
# ------------------------------------------------------------------------------------------------

do_dispose() {
  [ -n "$RUN_MODE" ] || die3 "dispose: --run-mode is required. The table reads it, and it is never assumed"
  local id="" candidate="" distance="" cost="" verdict="" why="" confirmed=false reuse_path="" reuse_interface=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)        need_value "dispose" "--id" "$#" "${2:-}";        id="$2"; shift 2 ;;
      --path)      need_value "dispose" "--path" "$#" "${2:-}";      reuse_path="$2"; shift 2 ;;
      --interface) need_value "dispose" "--interface" "$#" "${2:-}"; reuse_interface="$2"; shift 2 ;;
      --candidate) need_value "dispose" "--candidate" "$#" "${2:-}"; candidate="$2"; shift 2 ;;
      --distance)  need_value "dispose" "--distance" "$#" "${2:-}";  distance="$2"; shift 2 ;;
      --cost)      need_value "dispose" "--cost" "$#" "${2:-}";      cost="$2"; shift 2 ;;
      --verdict)   need_value "dispose" "--verdict" "$#" "${2:-}";   verdict="$2"; shift 2 ;;
      --why)       need_value "dispose" "--why" "$#" "${2:-}";       why="$2"; shift 2 ;;
      --confirmed) confirmed=true; shift ;;
      *) die3 "dispose: unrecognized argument: $1" ;;
    esac
  done
  require_wo_id_arg "dispose" "$id"
  is_blank "$candidate" && die3 "dispose: --candidate is required and must not be blank"
  is_blank "$why" && die3 "dispose: --why is required and must not be blank"
  case "$verdict" in
    reuse|extend|supersede|decline) ;;
    *) die3 "dispose: --verdict must be reuse, extend, supersede or decline, got '${verdict:-<nothing>}'" ;;
  esac
  [ "$verdict" = "decline" ] || { is_blank "$cost" && die3 "dispose: --cost is required and must not be blank"; }
  if ! is_blank "$reuse_path" || ! is_blank "$reuse_interface"; then
    [ "$verdict" = "decline" ] && die3 "dispose: a decline reuses nothing, so --path and --interface do not apply"
    is_blank "$reuse_path" && die3 "dispose: --interface was given without --path. The brief needs both: where the reused thing lives and what it exposes"
    is_blank "$reuse_interface" && die3 "dispose: --path was given without --interface. The brief needs both: where the reused thing lives and what it exposes"
  fi
  case "$distance" in
    same-name|same-directory|same-layer) ;;
    *) die3 "dispose: --distance must be same-name, same-directory or same-layer, got '${distance:-<nothing>}'" ;;
  esac

  # Which cost classes were cited. An unknown class never counts, so "vibes" clears no bar.
  local known=false recurring=false dim
  while IFS= read -r dim; do
    case "$dim" in
      build) known=true ;;
      carry|agent|risk) known=true; recurring=true ;;
    esac
  done < <(printf '%s\n' "$cost" | tr ',' '\n')

  local outcome="$verdict" rule="stands"
  if [ "$verdict" = "decline" ]; then
    rule="stands: nothing compared; the candidate is set aside and the reason names what was weighed"
  elif [ "$known" != "true" ] && [ "$verdict" != "supersede" ]; then
    rule="stands: no recognised cost dimension cited; a $verdict has nothing to downgrade to"
  elif [ "$known" != "true" ]; then
    [ "$RUN_MODE" = "interactive" ] \
      && die3 "dispose: no recognised cost dimension named (build, carry, agent, risk). Ask the person what this supersede compared, then call again"
    outcome=extend; rule="downgraded: a supersede with no cost dimension cited and nobody present to ask"
  elif [ "$verdict" = "supersede" ]; then
    if [ "$recurring" != "true" ]; then
      outcome=extend; rule="downgraded: a supersede resting on build cost alone; build is paid once, carry, agent and risk forever"
    elif [ "$distance" = "same-layer" ]; then
      outcome=extend; rule="downgraded: a candidate sharing only a layer is not absorbed by a replacement"
    elif [ "$RUN_MODE" = "interactive" ]; then
      [ "$confirmed" = "true" ] \
        || die3 "dispose: a supersede widens the task and owes a migration. Ask the person whether it stands, then call again with --confirmed"
      rule="stands: the person confirmed the supersede"
    else
      outcome=extend; rule="downgraded: a supersede with no person present; it re-surfaces on the next attended run"
    fi
  fi

  local file doc
  file="$(wo_file_for "$id")"
  jq empty "$file" 2>/dev/null || die3 "dispose: $file exists but is not valid JSON"
  doc="$(reasoning_appended "$(cat "$file")" "Candidate $candidate ($distance). Proposed $verdict, citing ${cost:-nothing}. Disposition: $outcome ($rule). $why")"
  if [ -n "$reuse_path" ]; then
    doc="$(printf '%s' "$doc" | jq --arg p "$reuse_path" --arg i "$reuse_interface" \
      '.reuses = ((.reuses // []) | map(select(.path != $p))) + [{path: $p, interface: $i}]')"
  fi
  write_atomic "$file" "$doc"
  echo "DISPOSED: $file"
  echo "proposed: $verdict"
  echo "disposition: $outcome"
  echo "reuses: $(printf '%s' "$doc" | jq -r '(.reuses // []) | length')"
  wo_summary "$doc"
  render_wo "$id"
  exit 0
}

# Reads the sidecar the distiller wrote after `close`; the read is distill_read in task-helpers.sh.
do_distill() {
  [ "$#" -eq 0 ] || die3 "distill: unrecognized argument: $1"
  distill_read "$TASK_PATH" design
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
# The project folder, two levels up, where commit_stage_close sends the stage commit. A record
# order's files lie under it (live-run row 127).
PROJECT_PATH="$(dirname -- "$(dirname -- "$TASK_PATH")")"
ALIGNMENT_FILE="$TASK_PATH/alignment.json"
DESIGN_DIR="$TASK_PATH/design"
CLOSED_FILE="$TASK_PATH/design-closed.json"
GUIDES_FILE="$TASK_PATH/design-guides-read.json"
CHECK_FILE="$TASK_PATH/records/design-check.json"
RESEARCH_CHECK_FILE="$TASK_PATH/records/research-check.json"

case "$ACTION" in
  read)           do_read           "$@" ;;
  start)          do_start          "$@" ;;
  create)         do_create         "$@" ;;
  update)         do_update         "$@" ;;
  add-owned-file) do_add_owned_file "$@" ;;
  add-done-when)  do_add_done_when  "$@" ;;
  add-test)       do_add_test       "$@" ;;
  remove-test)    do_remove_test    "$@" ;;
  remove-done-when)  do_remove_done_when  "$@" ;;
  remove-owned-file) do_remove_owned_file "$@" ;;
  merge)          do_merge          "$@" ;;
  read-guide)     do_read_guide     "$@" ;;
  render)         do_render         "$@" ;;
  check)          do_check          "$@" ;;
  close)          do_close          "$@" ;;
  dispose)        do_dispose        "$@" ;;
  distill)        do_distill        "$@" ;;
  verify)         do_verify         "$@" ;;
  *) usage; die3 "unknown action: $ACTION" ;;
esac
