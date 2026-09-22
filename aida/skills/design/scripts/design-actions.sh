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
# `close` also records the critique files under <task_folder>/records/ and their finding count.
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
#   design-actions.sh render     <task_folder> --id <woId>
#   design-actions.sh check      <task_folder>
#   design-actions.sh --run-mode <interactive|autonomous> close <task_folder> \
#                        --recipe-fit <true|false|unsure> --recipe-path <path> --recipe-reason <text> | --no-recipe
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
#      or `read-guide` was given a --path naming no file on disk; or `distill` found no
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
#      or `read-guide` found design-guides-read.json already on disk and not valid JSON.
#   4  `check` ran and found a work order file, or the guides-read record, that cannot be read as
#      its format: not valid JSON, not an object, or a missing, malformed or unknown field
#      (check-design.sh's own exit 1, remapped here so it never collides with this script's own
#      exit 1, "not a task folder"). `close` refuses for the same reason, on the live files, before
#      writing anything.
#      Or `distill` found a sidecar that fails scripts/distill-schema.json, or says standsAlone
#      false with no gap. That sidecar is moved aside first, to <name>.malformed-<date>.json,
#      and stdout names it in a `setAside:` line.
#   5  `check` ran, every work order file reads fine, but a content or cross-order check has a
#      problem: a criterion with no serving order, a criterion owned by zero or by more than one
#      work order, an order serving no criterion, an order missing a required test, a `record`
#      order that declares a test, owns a file outside the task folder or has no done-when row, a
#      dependency cycle, an order that reaches no owner, overlapping owned files, or an id naming
#      nothing real (check-design.sh's own exit 4). `close` refuses for the same reason, on the live
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

die1() { printf 'design-actions: %s\n' "$1" >&2; exit 1; }
die2() { printf 'design-actions: %s\n' "$1" >&2; exit 2; }
die3() { printf 'design-actions: %s\n' "$1" >&2; exit 3; }
die4() { printf 'design-actions: %s\n' "$1" >&2; exit 4; }
die5() { printf 'design-actions: %s\n' "$1" >&2; exit 5; }
die6() { printf 'design-actions: %s\n' "$1" >&2; exit 6; }
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
       design-actions.sh render         <task_folder> --id <woId>
       design-actions.sh check          <task_folder>
       design-actions.sh --run-mode <interactive|autonomous> close <task_folder> \
                                         --recipe-fit <true|false|unsure> --recipe-path <path> --recipe-reason <text> | --no-recipe
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
        ((.coverage.recordOrdersOwningOutsideTaskFolder // [])[] | "order " + .id + " is proved by its record and owns " + .path + " outside the task folder"),
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
  local interface="" reasoning="" diff_budget="" surfaces_json='[]' proof=""
  local set_title=false set_served=false set_owned=false set_nongoals=false set_dependson=false
  local set_interface=false set_reasoning=false set_diffbudget=false set_surfaces=false set_proof=false
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
  if [ "$set_surfaces" = "true" ]; then
    doc="$(printf '%s' "$doc" | jq --argjson v "$surfaces_json" '.surfaces = $v')"
  fi
  if [ "$set_proof" = "true" ]; then
    doc="$(printf '%s' "$doc" | jq --arg v "$proof" '.proof = $v')"
  fi

  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  wo_summary "$doc"

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
  # An order whose every owned file lies under the task folder delivers a document, not code, so
  # its proof is `record` (nyc defect 17): no test, no commit in the code repository, its done-when
  # rows judged instead. Marked here, where the files arrive, and only on an order with no proof
  # field: `create` writes one only when --proof was passed, so a proof design set by hand stays,
  # `tests` included. A code file added later leaves `record` in place, and the design check
  # names it; `update --proof tests` is the repair.
  local inferred
  inferred="$(printf '%s' "$doc" | jq -r --arg t "$TASK_PATH/" \
    'if (has("proof") | not) and ((.ownedFiles // []) | all(startswith($t))) then "record" else "" end')"
  if [ "$inferred" = "record" ]; then
    doc="$(printf '%s' "$doc" | jq '.proof = "record"')"
    echo "proof-set: record, because every owned file of $id lies under the task folder"
  fi
  # A record order's range is the project folder's history, so a file the project ignores can
  # never land in it: build-record would refuse the empty range (exit 71) on every attempt. The
  # project ignores records/ at every depth, the folder of derived check output. git finds the
  # repository upward from the task folder. Only a path under the task folder is asked: a path
  # outside it is a code path, which the design check names on a record order.
  if [ "$(printf '%s' "$doc" | jq -r '.proof // "tests"')" = "record" ] \
     && [ "${path_val#"$TASK_PATH"/}" != "$path_val" ] \
     && git -C "$TASK_PATH" check-ignore -q -- "$path_val" 2>/dev/null; then
    die3 "add-owned-file: the project ignores $path_val, so a commit can never hold it and a record order owning it can never be recorded. records/ is derived check output the project keeps out of history. Put the deliverable in a folder the project commits, such as $TASK_PATH/deliverables/."
  fi
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
# file under the task folder loses `proof`. It does not stay `record` on the strength of files
# it no longer owns.
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
  unset_proof="$(printf '%s' "$doc" | jq -r --arg t "$TASK_PATH/" \
    'if (.proof // "") == "record" and ((.ownedFiles // []) | any(startswith($t)) | not) then "yes" else "" end')"
  if [ "$unset_proof" = "yes" ]; then
    doc="$(printf '%s' "$doc" | jq 'del(.proof)')"
    echo "proof-unset: record, because no owned file of $id lies under the task folder now; every reader takes the order as tests until --proof says otherwise"
  fi
  write_atomic "$file" "$doc"
  echo "UPDATED: $file"
  echo "removed-owned-file: $path_val"
  wo_summary "$doc"
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
    | union("ownedFiles") | union("surfaces") | union("tests") | union("doneWhen") | union("reuses")
    | .dependsOn = [ (.dependsOn // [])[] | select(. != $from and . != $i.id) ]
    | append("interface") | append("reasoning")
  ' "$into_file")"

  local k before after
  for k in criteriaServed criteriaOwned nonGoals dependsOn ownedFiles surfaces tests doneWhen reuses; do
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
  local rc verdict lines
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
  local fit="" fit_path="" fit_reason="" no_recipe=false fit_json=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --recipe-fit)    need_value "close" "--recipe-fit" "$#" "${2:-}";    fit="$2"; shift 2 ;;
      --recipe-path)   need_value "close" "--recipe-path" "$#" "${2:-}";   fit_path="$2"; shift 2 ;;
      --recipe-reason) need_value "close" "--recipe-reason" "$#" "${2:-}"; fit_reason="$2"; shift 2 ;;
      --no-recipe)     no_recipe=true; shift ;;
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
    --arg runMode "$RUN_MODE" --arg closedBy "$closed_by" \
    '{schemaVersion: 1, closedAt: $closedAt, runMode: $runMode, closedBy: $closedBy, hash: $hash}')"
  [ -z "$fit_json" ] || doc="$(printf '%s' "$doc" | jq --argjson rf "$fit_json" '.recipeFit = $rf')"

  # The critique files the design skill's critics wrote before this close: their paths and the
  # total of their `findings: N` last lines, so the close says what was read before it. Absent when
  # no critic ran. A file without that line was not finished by its critic, and a count read from
  # it would be invented, so that file is left out of the record and named on stderr. The critique
  # blocks nothing, which is the design: a critic that can stop a close trains a design that
  # writes for the critic.
  local critique_files critique_total crit_file crit_n
  critique_files=""; critique_total=0
  while IFS= read -r crit_file; do
    [ -n "$crit_file" ] || continue
    crit_n="$(grep -E '^findings: [0-9]+$' "$crit_file" | tail -n 1 | sed 's/^findings: //')"
    if [ -z "$crit_n" ]; then
      printf 'close: %s has no findings line, so its critic did not finish; it is not counted\n' "$crit_file" >&2
      continue
    fi
    critique_total=$((critique_total + crit_n))
    critique_files="$critique_files$crit_file
"
  done < <(find "$TASK_PATH/records" -mindepth 1 -maxdepth 1 -type f -name 'design-critique-*.md' 2>/dev/null | sort)
  [ -z "$critique_files" ] || doc="$(printf '%s' "$doc" | jq --arg files "$critique_files" --argjson n "$critique_total" \
    '.critique = {files: ($files | split("\n") | map(select(length > 0))), findings: $n}')"

  write_atomic "$CLOSED_FILE" "$doc"
  # The stage boundary: the task folder is committed, with the order count the check just
  # walked and who closed as the reason. Closing again commits again, over the new hash.
  commit_stage_close "$TASK_PATH" design "Close design for $(jq -r '.id' "$TASK_PATH/task.json")" \
    "$(printf '%s' "$check_report_json" | jq -r '.files | length | if . == 1 then "1 work order" else "\(.) work orders" end'), closed by $closed_by"
  echo "CLOSED: $CLOSED_FILE"
  echo "closedBy: $closed_by"
  echo "runMode: $RUN_MODE"
  echo "hash: $hash"
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
  doc="$(jq --arg v "Candidate $candidate ($distance). Proposed $verdict, citing ${cost:-nothing}. Disposition: $outcome ($rule). $why" '.reasoning = (if (.reasoning // "") == "" then $v else .reasoning + "\n\n" + $v end)' "$file")"
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
  *) usage; die3 "unknown action: $ACTION" ;;
esac
