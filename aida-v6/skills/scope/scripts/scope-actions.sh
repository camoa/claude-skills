#!/usr/bin/env bash
# scope-actions.sh: the deterministic half of the scope skill (ideal/scope.md).
#
# The skill body holds the conversation: what to ask, what to propose, and whether a person has
# confirmed something. This script never asks a question. Every fact it needs arrives already
# decided, as an argument, the same split task-actions.sh and tool-actions.sh use. It writes
# alignment.json, mints ids, and renders alignment.md by calling alignment-render.sh. Deciding
# whether a criterion is approved belongs to whoever calls this, never to this script.
#
# Usage:
#   scope-actions.sh [--run-mode <interactive|autonomous>] read           <task_folder>
#   scope-actions.sh [--run-mode <interactive|autonomous>] init           <task_folder>
#   scope-actions.sh [--run-mode <interactive|autonomous>] set-goal       <task_folder> \
#                      --goal <text> [--expected-result <text>]
#   scope-actions.sh [--run-mode <interactive|autonomous>] add            <task_folder> \
#                      --text <text> --verification <text> --verified-by <machine|person> \
#                      [--author <owner|designer>]
#   scope-actions.sh [--run-mode <interactive|autonomous>] add-non-goal   <task_folder> \
#                      --text <text>
#   scope-actions.sh [--run-mode <interactive|autonomous>] update         <task_folder> \
#                      --id <id> [--text <text>] [--verification <text>] \
#                      [--verified-by <machine|person>] [--author owner]
#   scope-actions.sh [--run-mode <interactive|autonomous>] remove         <task_folder> \
#                      --id <id>
#   scope-actions.sh [--run-mode <interactive|autonomous>] render         <task_folder>
#   scope-actions.sh [--run-mode <interactive|autonomous>] set-mechanism  <task_folder> \
#                      --approach <text> --status <suggested|required>
#   scope-actions.sh [--run-mode <interactive|autonomous>] record-decision <task_folder> \
#                      --text <text>
#
# --run-mode is the DEFAULT for `add`'s author, used only when `add` is not given its own
# --author (ideal/scope.md, "Approval" and "The autonomous branch"): interactive means nobody has
# said otherwise, so the caller is expected to pass --author owner once a person actually
# confirmed the criterion; autonomous means nobody was there to confirm it, so `author` defaults
# to `designer`. There is no third value, and a missing answer is never read as the owner's.
# Absent, or any other value, means interactive, the safe default (foundations.md, Run mode). A
# non-goal carries no author (alignment-schema.json's own nonGoal has only id and text), so run
# mode never affects add-non-goal.
#
# Depends on, shipped by the same part and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/alignment-render.sh   called by `render`, unmodified
#
# This script never runs check-alignment.sh. Every field it writes is validated before the write,
# so what it produces is shaped correctly by construction; a stale or hand-edited alignment.json
# already on disk before this script's first call on a task is a fact check-alignment.sh reports,
# not one this script repairs.
#
# alignment.json's top level carries schemaVersion, goal, expectedResult, criteria, nonGoals,
# nextCriterionId, nextNonGoalId and decidedWithoutAPerson, and nothing else. An id, once minted,
# must never be reused after its criterion or non-goal is removed (ideal/scope.md, "Why the id
# exists"). The highest id ever issued, in each of the two id spaces, is kept as two integer
# fields on this same file, nextCriterionId and nextNonGoalId, rather than in a second file: a
# retired id is part of the contract's own history, so its high-water mark freezes with the
# contract instead of living somewhere that can be lost or reset independently of it. There is no
# alignment-ids.json; this script never writes one, and one found on disk is not read.
# decidedWithoutAPerson holds a string per question an unattended run answered on the person's
# behalf (ideal/scope.md, "The autonomous branch"); only `record-decision` appends to it.
#
# Every write is atomic: a temporary file in the task folder itself, then a rename over the
# target, so a write that fails partway never leaves a half-written alignment.json or task.json
# behind.
#
# This script commits nothing to git. task-actions.sh commits on create, start, complete and
# split because each is a discrete stage-boundary event. Scope's own set-goal, add, add-non-goal,
# update, remove, set-mechanism and record-decision are mid-conversation edits inside one still-
# open contract, closer to a document being drafted than to a stage finishing. Where the whole
# contract is frozen, ready to be committed as a stage boundary (foundations.md, History: "AIDA
# commits at stage boundaries"), is not decided here; that decision, and which caller makes the
# commit, is left to the skill body, not built by this script.
#
# Exit codes, each one and only one meaning:
#   0  did what was asked. For `read`, this includes an honest report that no contract exists yet.
#   1  the given path does not exist, is not a folder, or holds no task.json: not a task folder
#      (ideal/scope.md, "Scope runs against a task that already exists").
#   2  the target of this action is not present: alignment.json does not exist yet, for an action
#      that needs one already (every action but `read`, `init` and `set-mechanism`); or, for
#      `update` and `remove`, the given --id names no criterion and no non-goal in an
#      alignment.json that does exist.
#   3  the script could not do its job: a missing, blank or malformed argument; an argument value
#      that is itself another option; alignment.json exists but will not parse as JSON, or parses
#      but is not a contract (missing schemaVersion, goal, expectedResult, or criteria/nonGoals
#      not arrays); task.json exists but will not parse as JSON; `init` called where
#      alignment.json already exists (refused, never overwritten); a given --id that does not
#      match either id format, or that is already present when `add` tries to mint it; a given
#      --verified-by that is not machine or person; a given --author that add does not recognise,
#      or that update is asked to set to anything but owner; a missing or unusable
#      nextCriterionId or nextNonGoalId; the plugin root could not be resolved; or a write that
#      failed.
#   4  a script this action calls ran and failed. `render` calls alignment-render.sh; that
#      script's own stderr is the answer, printed here rather than duplicated.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no regular
# expression interval quantifier anywhere, the same rule task-actions.sh and check-alignment.sh
# state for the same reason (foundations.md, Honesty). No awk is used at all. An id's own shape is
# checked with a `case` glob (`c[1-9][0-9]*` or `n[1-9][0-9]*`), never a regular expression, the
# same way task-actions.sh checks a task id's own shape.

set -uo pipefail  # not -e: several branches test a command's exit code on purpose.

if [ -n "${ZSH_VERSION:-}" ]; then
  setopt KSH_ARRAYS 2>/dev/null
fi

# The plugin root is ${CLAUDE_PLUGIN_ROOT} when a skill sets it, and this script's own resolved
# location otherwise (the fallback scripts/check-alignment.sh and skills/tool/scripts/tool-
# actions.sh both use), so a person can run it directly and so a bare unset variable never exits
# 1: exit 1 is reserved for "not a task folder" by this script's own table above.
if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="$0"
else
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd -- "$(dirname -- "$SCRIPT_SOURCE")/../../.." >/dev/null 2>&1 && pwd -P)}"
if [ -z "$PLUGIN_ROOT" ] || [ ! -d "$PLUGIN_ROOT" ]; then
  printf 'scope-actions: could not resolve the plugin root (CLAUDE_PLUGIN_ROOT is not set and the script'"'"'s own location could not be resolved)\n' >&2
  exit 3
fi
ALIGNMENT_RENDER_SCRIPT="${PLUGIN_ROOT}/scripts/alignment-render.sh"

RUN_MODE="interactive"
if [ "${1:-}" = "--run-mode" ]; then
  [ $# -ge 2 ] || { printf 'scope-actions: --run-mode needs a value\n' >&2; exit 3; }
  RUN_MODE="$2"
  shift 2
fi
case "$RUN_MODE" in
  interactive|autonomous) ;;
  *) printf 'scope-actions: run mode must be interactive or autonomous, got %s\n' "$RUN_MODE" >&2; exit 3 ;;
esac

command -v jq >/dev/null 2>&1 || { printf 'scope-actions: jq is required and was not found on PATH\n' >&2; exit 3; }

die1() { printf 'scope-actions: %s\n' "$1" >&2; exit 1; }
die2() { printf 'scope-actions: %s\n' "$1" >&2; exit 2; }
die3() { printf 'scope-actions: %s\n' "$1" >&2; exit 3; }

usage() {
  cat <<'EOF' >&2
usage: scope-actions.sh read            <task_folder>
       scope-actions.sh init            <task_folder>
       scope-actions.sh set-goal        <task_folder> --goal <text> [--expected-result <text>]
       scope-actions.sh add             <task_folder> --text <text> --verification <text> \
                                         --verified-by <machine|person> [--author <owner|designer>]
       scope-actions.sh add-non-goal    <task_folder> --text <text>
       scope-actions.sh update          <task_folder> --id <id> [--text <text>] \
                                         [--verification <text>] [--verified-by <machine|person>] \
                                         [--author owner]
       scope-actions.sh remove          <task_folder> --id <id>
       scope-actions.sh render          <task_folder>
       scope-actions.sh set-mechanism   <task_folder> --approach <text> --status <suggested|required>
       scope-actions.sh record-decision <task_folder> --text <text>
EOF
}

# ------------------------------------------------------------------------------------------------
# Small helpers shared by more than one action below.
# ------------------------------------------------------------------------------------------------

# The task folder must already exist and already hold a task.json (ideal/scope.md, "Scope runs
# against a task that already exists": scope finds a task or says it cannot, it never scaffolds
# one). Prints the canonical path on success.
resolve_task_folder() {
  local arg="$1" who="$2" p
  [ -n "$arg" ] || die3 "$who: a task folder is required"
  p="$(cd "$arg" 2>/dev/null && pwd -P)" || die1 "$who: task folder not found: $arg"
  [ -f "$p/task.json" ] || die1 "$who: $p has no task.json; this is not a task folder"
  printf '%s' "$p"
}

# True (exit 0) when $1 looks like another option rather than real data for the option that
# wanted it (defect: an argument whose value is another flag was accepted for every text field
# except --id). id_kind, below, is this same house style applied to an id's own shape: refuse on
# the value's shape rather than trust the caller got the argument order right.
looks_like_flag() {
  case "$1" in
    --*) return 0 ;;
    *) return 1 ;;
  esac
}

# True (exit 0) when $1 is empty, or holds only whitespace. Not the rubber-stamp judgement
# (ideal/scope.md, "Open"), which belongs to the conversation; this is a value with no characters
# in it at all.
is_blank() {
  case "$1" in
    *[![:space:]]*) return 1 ;;
  esac
  return 0
}

# Every action past read/init needs a contract that already exists, parses, and actually is a
# contract: an object carrying schemaVersion, goal, expectedResult, and criteria/nonGoals as
# arrays. A file that merely parses as JSON is not enough; jq's own `+= []` on a missing field
# would otherwise invent an array on any object at all, so this is checked before every write
# instead of trusted (ideal/scope.md, "A file that will not parse is unreadable, not empty").
require_alignment_exists() {
  local who="$1" shape
  [ -f "$ALIGNMENT_FILE" ] || die2 "$who: $ALIGNMENT_FILE not found. Run init first"
  [ -r "$ALIGNMENT_FILE" ] \
    || die3 "$who: $ALIGNMENT_FILE exists but is not readable (a permission problem, not the same fact as missing or malformed)"
  jq empty "$ALIGNMENT_FILE" 2>/dev/null \
    || die3 "$who: $ALIGNMENT_FILE exists but is not valid JSON (malformed, not the same fact as missing or unreadable)"
  shape="$(jq -r '
      if type != "object" then "not an object"
      elif (has("schemaVersion") | not) then "missing schemaVersion"
      elif (has("goal") | not) then "missing goal"
      elif (has("expectedResult") | not) then "missing expectedResult"
      elif ((.criteria | type) != "array") then "criteria is not an array"
      elif ((.nonGoals | type) != "array") then "nonGoals is not an array"
      else "ok"
      end
    ' "$ALIGNMENT_FILE" 2>/dev/null)"
  [ "$shape" = "ok" ] \
    || die3 "$who: $ALIGNMENT_FILE is not a contract ($shape). A contract is never inferred"
}

# Writes $2 (assumed already-valid JSON text) to $1 through a temporary file in the same
# directory, then renames over the target, so a failure partway through never leaves a
# half-written file behind (this script's own header comment).
write_atomic() {
  local target="$1" content="$2" tmp
  tmp="$(mktemp "${TASK_PATH}/.$(basename -- "$target").XXXXXX")" \
    || die3 "could not create a temporary file in $TASK_PATH"
  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; die3 "could not write $tmp"; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; die3 "could not write $target"; }
}

# Prints "criterion" for a c<n> id, "nongoal" for an n<n> id, and nothing for anything else.
# A glob's `*` is a free-form wildcard, not "zero or more of the class before it" the way a
# regex `*` is, so `c[1-9][0-9]*` would actually demand two digits and let anything follow the
# second one; that is not this script's rule to get wrong twice. Instead the prefix is read
# first, then the remaining digits are checked as their own string: not empty, not starting
# with 0 (which also refuses the bare "0" alignment-schema.json's own examples call invalid),
# and holding no character outside 0-9, with `*[!0-9]*` (case globs, not a regular expression,
# the same idiom task-actions.sh uses for a task id's own shape). No interval quantifier and no
# awk anywhere in this check (this script's own header, Portability).
id_kind() {
  local id="$1" prefix num
  case "$id" in
    c*) prefix="c" ;;
    n*) prefix="n" ;;
    *) printf ''; return ;;
  esac
  num="${id#?}"
  case "$num" in
    ''|0*|*[!0-9]*) printf ''; return ;;
  esac
  if [ "$prefix" = "c" ]; then printf 'criterion'; else printf 'nongoal'; fi
}

# ------------------------------------------------------------------------------------------------
# read: the contract as JSON, or an honest empty state. Never a script failure just because a
# task has not run scope yet.
# ------------------------------------------------------------------------------------------------

do_read() {
  [ "$#" -eq 0 ] || die3 "read: unrecognized argument: $1"

  if [ ! -f "$ALIGNMENT_FILE" ]; then
    jq -n --arg taskPath "$TASK_PATH" \
      '{exists: false, taskPath: $taskPath, message: "no scope contract yet"}'
    exit 0
  fi
  [ -r "$ALIGNMENT_FILE" ] \
    || die3 "read: $ALIGNMENT_FILE exists but is not readable (a permission problem, not the same fact as missing or malformed)"
  jq empty "$ALIGNMENT_FILE" 2>/dev/null \
    || die3 "read: $ALIGNMENT_FILE exists but is not valid JSON (malformed, not the same fact as missing or unreadable)"

  cat "$ALIGNMENT_FILE"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# init: writes a new alignment.json with no criteria and no non-goals, both id counters starting
# at 1, and no decisions recorded yet. Refuses to overwrite one that already exists; scope has an
# update path for that, not a second init.
# ------------------------------------------------------------------------------------------------

do_init() {
  [ "$#" -eq 0 ] || die3 "init: unrecognized argument: $1"

  [ ! -e "$ALIGNMENT_FILE" ] \
    || die3 "init: $ALIGNMENT_FILE already exists. This task already has a scope contract; use the other actions to change it"

  local empty
  empty="$(jq -n '{schemaVersion: 1, goal: "", expectedResult: "", criteria: [], nonGoals: [],
                   nextCriterionId: 1, nextNonGoalId: 1, decidedWithoutAPerson: []}')"
  write_atomic "$ALIGNMENT_FILE" "$empty"

  echo "INITIALIZED: $ALIGNMENT_FILE"
  cat "$ALIGNMENT_FILE"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# set-goal: sets the goal, and the expected result when given. Both are plain strings that
# nothing cites and nothing counts (alignment-schema.json).
# ------------------------------------------------------------------------------------------------

do_set_goal() {
  local goal="" expected="" expected_given=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --goal)
        [ $# -ge 2 ] || die3 "set-goal: --goal needs a value"
        looks_like_flag "$2" && die3 "set-goal: --goal needs a value, got the option $2 instead"
        goal="$2"; shift 2 ;;
      --expected-result)
        [ $# -ge 2 ] || die3 "set-goal: --expected-result needs a value"
        looks_like_flag "$2" && die3 "set-goal: --expected-result needs a value, got the option $2 instead"
        expected="$2"; expected_given=1; shift 2 ;;
      *) die3 "set-goal: unrecognized argument: $1" ;;
    esac
  done
  is_blank "$goal" && die3 "set-goal: --goal is required and must not be blank"
  [ "$expected_given" -eq 0 ] || { is_blank "$expected" && die3 "set-goal: --expected-result must not be blank"; }

  require_alignment_exists "set-goal"

  local updated
  if [ "$expected_given" -eq 1 ]; then
    updated="$(jq --arg g "$goal" --arg e "$expected" '.goal = $g | .expectedResult = $e' "$ALIGNMENT_FILE")" \
      || die3 "set-goal: could not update $ALIGNMENT_FILE"
  else
    updated="$(jq --arg g "$goal" '.goal = $g' "$ALIGNMENT_FILE")" \
      || die3 "set-goal: could not update $ALIGNMENT_FILE"
  fi
  write_atomic "$ALIGNMENT_FILE" "$updated"

  echo "GOAL SET"
  cat "$ALIGNMENT_FILE"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# add: mints the next criterion id from nextCriterionId, refuses to mint one already present,
# sets author from --author when given or from the run mode otherwise, and appends it.
# ------------------------------------------------------------------------------------------------

do_add() {
  local text="" verification="" verified_by="" author="" author_given=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --text)
        [ $# -ge 2 ] || die3 "add: --text needs a value"
        looks_like_flag "$2" && die3 "add: --text needs a value, got the option $2 instead"
        text="$2"; shift 2 ;;
      --verification)
        [ $# -ge 2 ] || die3 "add: --verification needs a value"
        looks_like_flag "$2" && die3 "add: --verification needs a value, got the option $2 instead"
        verification="$2"; shift 2 ;;
      --verified-by)
        [ $# -ge 2 ] || die3 "add: --verified-by needs a value"
        looks_like_flag "$2" && die3 "add: --verified-by needs a value, got the option $2 instead"
        verified_by="$2"; shift 2 ;;
      --author)
        [ $# -ge 2 ] || die3 "add: --author needs a value"
        looks_like_flag "$2" && die3 "add: --author needs a value, got the option $2 instead"
        author="$2"; author_given=1; shift 2 ;;
      *) die3 "add: unrecognized argument: $1" ;;
    esac
  done
  is_blank "$text" && die3 "add: --text is required and must not be blank"
  is_blank "$verification" && die3 "add: --verification is required and must not be blank. Every criterion carries a verify clause"
  case "$verified_by" in
    machine|person) : ;;
    *) die3 "add: --verified-by must be machine or person, got '${verified_by:-<nothing>}'" ;;
  esac
  if [ "$author_given" -eq 1 ]; then
    case "$author" in
      owner|designer) : ;;
      *) die3 "add: --author must be owner or designer, got '$author'" ;;
    esac
  else
    if [ "$RUN_MODE" = "autonomous" ]; then author="designer"; else author="owner"; fi
  fi

  require_alignment_exists "add"

  local next_id id present updated
  next_id="$(jq -r '.nextCriterionId // empty' "$ALIGNMENT_FILE")"
  case "$next_id" in
    ''|*[!0-9]*) die3 "add: $ALIGNMENT_FILE has no usable nextCriterionId; this contract cannot mint a new id" ;;
  esac
  [ "$next_id" -ge 1 ] || die3 "add: $ALIGNMENT_FILE's nextCriterionId must be at least 1, got $next_id"
  id="c${next_id}"

  present="$(jq -r --arg id "$id" '([ (.criteria // [])[]?.id? ] | index($id)) != null' "$ALIGNMENT_FILE")"
  [ "$present" != "true" ] \
    || die3 "add: id $id is already present in $ALIGNMENT_FILE; refusing to mint a duplicate"

  updated="$(jq \
      --arg id "$id" --arg text "$text" --arg verification "$verification" \
      --arg verifiedBy "$verified_by" --arg author "$author" --argjson next "$((next_id + 1))" \
      '.criteria += [{id: $id, text: $text, verification: $verification, verifiedBy: $verifiedBy,
                       author: $author, verdict: "unanswered"}]
       | .nextCriterionId = $next' "$ALIGNMENT_FILE")" \
    || die3 "add: could not add the new criterion to $ALIGNMENT_FILE"
  write_atomic "$ALIGNMENT_FILE" "$updated"

  echo "ADDED: $id"
  jq --arg id "$id" '(.criteria[] | select(.id == $id))' "$ALIGNMENT_FILE"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# add-non-goal: mints the next non-goal id from nextNonGoalId, in its own space, and appends it.
# ------------------------------------------------------------------------------------------------

do_add_non_goal() {
  local text=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --text)
        [ $# -ge 2 ] || die3 "add-non-goal: --text needs a value"
        looks_like_flag "$2" && die3 "add-non-goal: --text needs a value, got the option $2 instead"
        text="$2"; shift 2 ;;
      *) die3 "add-non-goal: unrecognized argument: $1" ;;
    esac
  done
  is_blank "$text" && die3 "add-non-goal: --text is required and must not be blank"

  require_alignment_exists "add-non-goal"

  local next_id id updated
  next_id="$(jq -r '.nextNonGoalId // empty' "$ALIGNMENT_FILE")"
  case "$next_id" in
    ''|*[!0-9]*) die3 "add-non-goal: $ALIGNMENT_FILE has no usable nextNonGoalId; this contract cannot mint a new id" ;;
  esac
  [ "$next_id" -ge 1 ] || die3 "add-non-goal: $ALIGNMENT_FILE's nextNonGoalId must be at least 1, got $next_id"
  id="n${next_id}"

  updated="$(jq \
      --arg id "$id" --arg text "$text" --argjson next "$((next_id + 1))" \
      '.nonGoals += [{id: $id, text: $text}]
       | .nextNonGoalId = $next' "$ALIGNMENT_FILE")" \
    || die3 "add-non-goal: could not add the new non-goal to $ALIGNMENT_FILE"
  write_atomic "$ALIGNMENT_FILE" "$updated"

  echo "ADDED: $id"
  jq --arg id "$id" '(.nonGoals[] | select(.id == $id))' "$ALIGNMENT_FILE"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# update: changes text, verification, verifiedBy, or promotes author, on an existing criterion or
# non-goal, found by id. Never touches verdict: that is the end review's own answer
# (ideal/scope.md, "What a criterion holds"). Author moves one direction only, designer to owner:
# promoting a proposed criterion once a person approves it is the whole point, and there is no
# call for moving it back.
# ------------------------------------------------------------------------------------------------

do_update() {
  local id="" text="" verification="" verified_by="" author=""
  local set_text=0 set_verification=0 set_verified_by=0 set_author=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        [ $# -ge 2 ] || die3 "update: --id needs a value"
        id="$2"; shift 2 ;;
      --text)
        [ $# -ge 2 ] || die3 "update: --text needs a value"
        looks_like_flag "$2" && die3 "update: --text needs a value, got the option $2 instead"
        text="$2"; set_text=1; shift 2 ;;
      --verification)
        [ $# -ge 2 ] || die3 "update: --verification needs a value"
        looks_like_flag "$2" && die3 "update: --verification needs a value, got the option $2 instead"
        verification="$2"; set_verification=1; shift 2 ;;
      --verified-by)
        [ $# -ge 2 ] || die3 "update: --verified-by needs a value"
        looks_like_flag "$2" && die3 "update: --verified-by needs a value, got the option $2 instead"
        verified_by="$2"; set_verified_by=1; shift 2 ;;
      --author)
        [ $# -ge 2 ] || die3 "update: --author needs a value"
        looks_like_flag "$2" && die3 "update: --author needs a value, got the option $2 instead"
        author="$2"; set_author=1; shift 2 ;;
      *) die3 "update: unrecognized argument: $1" ;;
    esac
  done
  [ -n "$id" ] || die3 "update: --id is required"
  [ "$set_text" -eq 0 ] || { is_blank "$text" && die3 "update: --text must not be blank"; }
  [ "$set_verification" -eq 0 ] || { is_blank "$verification" && die3 "update: --verification must not be blank"; }
  [ "$set_text" -eq 1 ] || [ "$set_verification" -eq 1 ] || [ "$set_verified_by" -eq 1 ] || [ "$set_author" -eq 1 ] \
    || die3 "update: at least one of --text, --verification, --verified-by or --author is required"

  local kind
  kind="$(id_kind "$id")"
  [ -n "$kind" ] \
    || die3 "update: '$id' is not a valid id; a criterion id is c<n>, a non-goal id is n<n>, with no leading zero"

  if [ "$kind" = "nongoal" ]; then
    [ "$set_verification" -eq 0 ] || die3 "update: --verification does not apply to a non-goal ($id); a non-goal only has text"
    [ "$set_verified_by" -eq 0 ] || die3 "update: --verified-by does not apply to a non-goal ($id); a non-goal only has text"
    [ "$set_author" -eq 0 ] || die3 "update: --author does not apply to a non-goal ($id); a non-goal has no author"
  fi
  if [ "$set_verified_by" -eq 1 ]; then
    case "$verified_by" in
      machine|person) : ;;
      *) die3 "update: --verified-by must be machine or person, got '$verified_by'" ;;
    esac
  fi
  if [ "$set_author" -eq 1 ]; then
    [ "$author" = "owner" ] \
      || die3 "update: --author only accepts owner, got '$author'; a criterion's author moves from designer to owner when a person approves it, and never the other way"
  fi

  require_alignment_exists "update"

  local arrfield
  if [ "$kind" = "criterion" ]; then arrfield="criteria"; else arrfield="nonGoals"; fi

  local present
  present="$(jq -r --arg arr "$arrfield" --arg id "$id" \
      '([ (.[$arr] // [])[]?.id? ] | index($id)) != null' "$ALIGNMENT_FILE")"
  [ "$present" = "true" ] || die2 "update: no $kind with id $id in $ALIGNMENT_FILE"

  local set_text_json set_verification_json set_verified_by_json set_author_json updated
  if [ "$set_text" -eq 1 ]; then set_text_json=true; else set_text_json=false; fi
  if [ "$set_verification" -eq 1 ]; then set_verification_json=true; else set_verification_json=false; fi
  if [ "$set_verified_by" -eq 1 ]; then set_verified_by_json=true; else set_verified_by_json=false; fi
  if [ "$set_author" -eq 1 ]; then set_author_json=true; else set_author_json=false; fi

  updated="$(jq \
      --arg arr "$arrfield" --arg id "$id" \
      --arg text "$text" --argjson setText "$set_text_json" \
      --arg verification "$verification" --argjson setVerification "$set_verification_json" \
      --arg verifiedBy "$verified_by" --argjson setVerifiedBy "$set_verified_by_json" \
      --arg author "$author" --argjson setAuthor "$set_author_json" \
      '(.[$arr] |= map(
          if .id == $id then
            (if $setText then .text = $text else . end)
            | (if $setVerification then .verification = $verification else . end)
            | (if $setVerifiedBy then .verifiedBy = $verifiedBy else . end)
            | (if $setAuthor then .author = $author else . end)
          else . end
        ))' "$ALIGNMENT_FILE")" || die3 "update: could not update $ALIGNMENT_FILE"
  write_atomic "$ALIGNMENT_FILE" "$updated"

  echo "UPDATED: $id"
  jq --arg arr "$arrfield" --arg id "$id" '(.[$arr][] | select(.id == $id))' "$ALIGNMENT_FILE"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# remove: the id stays retired. nextCriterionId and nextNonGoalId never move backward, so add
# never reuses it.
# ------------------------------------------------------------------------------------------------

do_remove() {
  local id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id)
        [ $# -ge 2 ] || die3 "remove: --id needs a value"
        id="$2"; shift 2 ;;
      *) die3 "remove: unrecognized argument: $1" ;;
    esac
  done
  [ -n "$id" ] || die3 "remove: --id is required"

  local kind
  kind="$(id_kind "$id")"
  [ -n "$kind" ] \
    || die3 "remove: '$id' is not a valid id; a criterion id is c<n>, a non-goal id is n<n>, with no leading zero"

  require_alignment_exists "remove"

  local arrfield
  if [ "$kind" = "criterion" ]; then arrfield="criteria"; else arrfield="nonGoals"; fi

  local present
  present="$(jq -r --arg arr "$arrfield" --arg id "$id" \
      '([ (.[$arr] // [])[]?.id? ] | index($id)) != null' "$ALIGNMENT_FILE")"
  [ "$present" = "true" ] || die2 "remove: no $kind with id $id in $ALIGNMENT_FILE"

  local updated
  updated="$(jq --arg arr "$arrfield" --arg id "$id" '.[$arr] |= map(select(.id != $id))' "$ALIGNMENT_FILE")" \
    || die3 "remove: could not update $ALIGNMENT_FILE"
  write_atomic "$ALIGNMENT_FILE" "$updated"

  echo "REMOVED: $id"
  echo "This id is retired. It is never minted again for this task."
  exit 0
}

# ------------------------------------------------------------------------------------------------
# render: calls alignment-render.sh. Its own stdout and stderr pass straight through, so its
# message is never duplicated here.
# ------------------------------------------------------------------------------------------------

do_render() {
  [ "$#" -eq 0 ] || die3 "render: unrecognized argument: $1"

  [ -f "$ALIGNMENT_RENDER_SCRIPT" ] \
    || die3 "render: cannot find alignment-render.sh at $ALIGNMENT_RENDER_SCRIPT"

  bash "$ALIGNMENT_RENDER_SCRIPT" "$TASK_PATH"
  local rc=$?
  [ "$rc" -eq 0 ] || exit 4
  exit 0
}

# ------------------------------------------------------------------------------------------------
# set-mechanism: records a stated approach into task.json's own mechanismHints array
# (task-schema.json), never into alignment.json. Scope records the claim; it never challenges it
# (ideal/scope.md, "The stated mechanism is not scope's field").
# ------------------------------------------------------------------------------------------------

do_set_mechanism() {
  local approach="" status=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --approach)
        [ $# -ge 2 ] || die3 "set-mechanism: --approach needs a value"
        looks_like_flag "$2" && die3 "set-mechanism: --approach needs a value, got the option $2 instead"
        approach="$2"; shift 2 ;;
      --status)
        [ $# -ge 2 ] || die3 "set-mechanism: --status needs a value"
        looks_like_flag "$2" && die3 "set-mechanism: --status needs a value, got the option $2 instead"
        status="$2"; shift 2 ;;
      *) die3 "set-mechanism: unrecognized argument: $1" ;;
    esac
  done
  is_blank "$approach" && die3 "set-mechanism: --approach is required and must not be blank"
  case "$status" in
    suggested|required) : ;;
    *) die3 "set-mechanism: --status must be suggested or required, got '${status:-<nothing>}'" ;;
  esac

  [ -r "$TASK_FILE" ] \
    || die3 "set-mechanism: $TASK_FILE exists but is not readable (a permission problem, not the same fact as missing or malformed)"
  jq empty "$TASK_FILE" 2>/dev/null \
    || die3 "set-mechanism: $TASK_FILE exists but is not valid JSON (malformed, not the same fact as missing or unreadable)"

  local updated
  updated="$(jq --arg approach "$approach" --arg status "$status" \
      '.mechanismHints = ((.mechanismHints // []) + [{approach: $approach, status: $status}])' \
      "$TASK_FILE")" || die3 "set-mechanism: could not update $TASK_FILE"
  write_atomic "$TASK_FILE" "$updated"

  echo "MECHANISM RECORDED"
  jq '.mechanismHints' "$TASK_FILE"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# record-decision: appends to alignment.json's own decidedWithoutAPerson, one string per question
# an unattended run answered on the person's behalf (ideal/scope.md, "The autonomous branch").
# ------------------------------------------------------------------------------------------------

do_record_decision() {
  local text=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --text)
        [ $# -ge 2 ] || die3 "record-decision: --text needs a value"
        looks_like_flag "$2" && die3 "record-decision: --text needs a value, got the option $2 instead"
        text="$2"; shift 2 ;;
      *) die3 "record-decision: unrecognized argument: $1" ;;
    esac
  done
  is_blank "$text" && die3 "record-decision: --text is required and must not be blank"

  require_alignment_exists "record-decision"

  local updated
  updated="$(jq --arg text "$text" \
      '.decidedWithoutAPerson = ((.decidedWithoutAPerson // []) + [$text])' "$ALIGNMENT_FILE")" \
    || die3 "record-decision: could not update $ALIGNMENT_FILE"
  write_atomic "$ALIGNMENT_FILE" "$updated"

  echo "DECISION RECORDED"
  jq '.decidedWithoutAPerson' "$ALIGNMENT_FILE"
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
# resolve_task_folder runs in the subshell command substitution creates, so its own die1/die3
# calls only end that subshell; its message already reached stderr from there, but the exit code
# has to be re-raised here by hand or the script would fall through with TASK_PATH empty.
[ "$RESOLVE_RC" -eq 0 ] || exit "$RESOLVE_RC"
ALIGNMENT_FILE="$TASK_PATH/alignment.json"
TASK_FILE="$TASK_PATH/task.json"

case "$ACTION" in
  read)             do_read             "$@" ;;
  init)             do_init             "$@" ;;
  set-goal)         do_set_goal         "$@" ;;
  add)              do_add              "$@" ;;
  add-non-goal)     do_add_non_goal     "$@" ;;
  update)           do_update           "$@" ;;
  remove)           do_remove           "$@" ;;
  render)           do_render           "$@" ;;
  set-mechanism)    do_set_mechanism    "$@" ;;
  record-decision)  do_record_decision  "$@" ;;
  *) usage; die3 "unknown action: $ACTION" ;;
esac
