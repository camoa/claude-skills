#!/usr/bin/env bash
# review-actions.sh: the deterministic half of the review skill (ideal/review.md).
#
# The skill body holds the conversation. This script holds the deterministic half: it reads what
# implementation handed over, writes the diff once, runs every command the two recipes declare over
# the changed files at the final commit, assembles the architecture reviewer's brief, records what
# that reviewer found, runs the surfaces and takes the person's walk, and closes the review with one
# verdict. It never judges whether a criterion is met by reading code, and it starts no fixer: a
# failed review goes to the person with the record.
#
# One review record, at <task folder>/review/review.json (scripts/review-schema.json). It lives in
# its own folder beside research/, design/ and implementation/, because implementation's own
# `restart` archives that folder whole and a review inside it would go with a build restart it has
# nothing to do with.
#
# Usage:
#   review-actions.sh read     <task_folder>
#   review-actions.sh checks   <task_folder> [--recipe <framework>=<path>]...
#                                            [--check-recipe <framework>=<path>]...
#                                            [--lookup-failed <framework>=<reason>]...
#                                            [--value <name>=<value>]...
#   review-actions.sh brief    <task_folder>          writes <task>/review/brief.json
#   review-actions.sh findings <task_folder> --findings <path the reviewer wrote>
#   review-actions.sh surfaces <task_folder> [--walked <surface id>]...
#                                            [--accept-baseline <surface id>]...
#   review-actions.sh close    <task_folder> [--row <criterion>=met|unmet]...
#   review-actions.sh step     <name>
#
# `--recipe` names the `test-execution` recipe, for its `## Test commands` block, which carries the
# suite row and the mutation row. `--check-recipe` names the `review` recipe, for its
# `## Check commands` block and its `## Surface commands` block. Every framework the project
# declares needs one of the two, or a `--lookup-failed` saying which way its lookup failed. The
# three reasons stay apart: no-recipe, listing-unreachable, fetch-failed. Only the first says
# anything about the framework; the other two mean nobody looked.
#
# Every action prints a summary of `key: value` lines and nothing else: no record body, no diff, no
# command output, no research text. Each line that a person may want in full names the path that holds
# it, which is <task>/review/review.json for the record, review/diff.patch for the diff and
# review/brief.json for the reviewer's brief. The one body any action prints is `read`'s checklist
# rows, because the person answering them has to read them verbatim.
#
# `surfaces` takes no recipe flag. It reads the review recipe path `checks` recorded, so the surface
# block is read from the same file the tool rows came from and review keeps its two lookups.
#
# `step` prints one of this skill's own step files, from
# ${CLAUDE_PLUGIN_ROOT}/skills/review/references/<name>.md. The skill reads them through this action
# rather than with Read: the documentation mirror scopes ${CLAUDE_PLUGIN_ROOT} substitution in
# `allowed-tools` to Bash rules, so a Read rule naming that variable never matches and every
# step-file read raises a prompt an unattended run cannot answer.
#
# Exit codes, each one and only one meaning, and every meaning is the one implementation gave it:
#   0  did what was asked. For `read`, this includes an honest report that nothing has run yet.
#   1  the given path does not exist, is not a folder, or holds no task.json: not a task folder.
#   3  the script could not do its job: a missing or unrecognized argument, jq or git not on PATH,
#      the plugin root or a library that could not be resolved, a project or task folder that could
#      not be resolved, a record or a frozen file that is present but unreadable, a record that does
#      not match scripts/review-schema.json, a framework nothing was said about, or a code
#      repository whose HEAD is not the commit implementation's own range ends at.
#   5  the recorded codePath exists and is not a git repository.
#  14  the project's own project.json exists and is not valid JSON.
#  15  the recorded codePath does not exist on disk.
#  51  the code path moved, or went dirty, since `checks` ran.
#  52  the findings file could not be read as a findings file.
#  61  the code repository's tree is dirty.
#  62  a step ran out of order, and what it depends on recorded nothing.
#  63  the previous record could not be archived, so the write was refused.
#  66  implementation has not finished, so there is no finished.json.
#  70  a person's answer was passed on a run with nobody present.
#  72  two frameworks each command one tool.
#  73  the check recipe resolved now is not the one the baseline was taken with.
#  77  the project records no framework.
#
# Codes 5, 14, 15, 52, 70, 72 and 73 arrive from scripts/lib/recipes.sh, which both stages source, and
# they carry exactly the meanings implement-actions.sh's own table gives them. ideal/review.md lists
# eight of these; the rest come with the shared helpers, and giving them new numbers here would make
# one number mean two things.
#
# Depends on, shipped by other builders of this same project and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/recipes.sh       sourced. The recipe block parsers, the
#                                                      resolver, the command runner, the clean-tree
#                                                      refusal, the code-path loader, the findings
#                                                      file reader. Nothing here carries a second
#                                                      copy of any of them.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/records-hash.sh  sourced, for the one decision about which
#                                                      sha256 tool exists.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/task-helpers.sh  sourced, for resolve_task_folder,
#                                                      write_atomic, looks_like_flag and is_blank.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/schema-check.sh  sourced. Every record write is compared
#                                                      against review-schema.json before it lands.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/review-schema.json   the shape of the record this script writes.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no awk, no
# regular-expression interval quantifier. The five zsh traps implement-actions.sh's header lists
# hold here too: never a variable named `path` or `fpath`, no reliance on word splitting an unquoted
# expansion, no variable used as a case pattern without GLOB_SUBST scoped to a subshell, no
# `local a b="$a"` statement, and no `local` inside a loop body.

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
  printf 'review-actions: could not resolve the plugin root (CLAUDE_PLUGIN_ROOT is not set and the script'"'"'s own location could not be resolved)\n' >&2
  exit 3
fi
STEPS_DIR="${PLUGIN_ROOT}/skills/review/references"
RECORDS_HASH_LIB="${PLUGIN_ROOT}/scripts/lib/records-hash.sh"
RECIPES_LIB="${PLUGIN_ROOT}/scripts/lib/recipes.sh"
TASK_HELPERS_LIB="${PLUGIN_ROOT}/scripts/lib/task-helpers.sh"
SCHEMA_CHECK_LIB="${PLUGIN_ROOT}/scripts/lib/schema-check.sh"
REVIEW_SCHEMA="${PLUGIN_ROOT}/scripts/review-schema.json"

command -v jq >/dev/null 2>&1 || { printf 'review-actions: jq is required and was not found on PATH\n' >&2; exit 3; }
command -v git >/dev/null 2>&1 || { printf 'review-actions: git is required and was not found on PATH\n' >&2; exit 3; }

die() { printf 'review-actions: %s\n' "$2" >&2; exit "$1"; }
# One refusal function, one exit code as its first argument. The table above is the only place a
# number gets a meaning, and nothing here mints one that table does not carry.

# task-helpers.sh takes these two from its caller, so a refusal still says which script refused.
die1() { die 1 "$1"; }
die3() { die 3 "$1"; }

for lib_name in "$RECORDS_HASH_LIB" "$TASK_HELPERS_LIB" "$SCHEMA_CHECK_LIB" "$RECIPES_LIB"; do
  [ -f "$lib_name" ] || die 3 "cannot find the library at $lib_name"
  # shellcheck source=/dev/null
  source "$lib_name" || die 3 "the library failed to load: $lib_name"
done
[ -f "$REVIEW_SCHEMA" ] || die 3 "cannot find the record shape at $REVIEW_SCHEMA"

# The seven lenses one dispatch carries. The words are fixed here, in agents/architecture-reviewer.md
# and in the step file, and each of checks 2, 9, 10, 11, 12 and 16 reads its verdict off its own
# lens. A word this list does not hold would leave its check reading met on a findings file that is
# not empty, so a finding naming one is refused rather than recorded.
LENS_WORDS="non-goals solid dry architecture guides practices mutation"

# The sixteen checks, by the id each one carries in the record. The tool rows a recipe declares
# beyond coding-standards, static-analysis and security carry their own row ids, because the check
# commands block is a floor and never the list.
CHECK_EVERY_CRITERION="every-criterion"
CHECK_SERVES="serves-a-criterion"
CHECK_TEST_MUTATION="test-and-mutation"
CHECK_SUITE="suite"
CHECK_E2E="e2e"
CHECK_VR="visual-regression"
CHECK_PARITY="visual-parity"

usage() {
  cat <<'EOF' >&2
usage: review-actions.sh read     <task_folder>
       review-actions.sh checks   <task_folder>
                                  [--recipe <framework>=<path to the test-execution recipe>]...
                                  [--check-recipe <framework>=<path to the review recipe>]...
                                  [--lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed>]...
                                  [--value <name>=<value>]...
       review-actions.sh brief    <task_folder>
       review-actions.sh findings <task_folder> --findings <path the reviewer wrote>
       review-actions.sh surfaces <task_folder> [--walked <surface id>]...
                                               [--accept-baseline <surface id>]...
       review-actions.sh close    <task_folder> [--row <criterion>=met|unmet]...
       review-actions.sh step     <name>
EOF
}

# ------------------------------------------------------------------------------------------------
# The files this stage reads and the one it writes.
# ------------------------------------------------------------------------------------------------

IMPL_DIR=""; REVIEW_DIR=""; RECORD_FILE=""; DIFF_FILE=""
FINISHED_FILE=""; LEDGER_FILE=""; SNAPSHOT_FILE=""; BASELINE_FILE=""; ALIGNMENT_FILE=""
FINDINGS_TARGET=""; BRIEF_FILE=""

# $1 the action's own name, $2 the task folder as given. Sets TASK_PATH and every path above.
rw_paths() {
  local who="$1" arg="$2" resolve_rc
  TASK_PATH="$(resolve_task_folder "$arg" "$who")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"
  REVIEW_DIR="$TASK_PATH/review"
  RECORD_FILE="$REVIEW_DIR/review.json"
  DIFF_FILE="$REVIEW_DIR/diff.patch"
  FINDINGS_TARGET="$REVIEW_DIR/findings.json"
  BRIEF_FILE="$REVIEW_DIR/brief.json"
  FINISHED_FILE="$IMPL_DIR/finished.json"
  LEDGER_FILE="$IMPL_DIR/ledger.json"
  SNAPSHOT_FILE="$IMPL_DIR/snapshot.json"
  BASELINE_FILE="$IMPL_DIR/baseline.json"
  ALIGNMENT_FILE="$TASK_PATH/alignment.json"
}

RW_FINISHED_DOC=""; RW_LEDGER_DOC=""; RW_SNAPSHOT_DOC=""; RW_RECORD_DOC=""
RW_RUN_MODE="interactive"; RW_PROJECT_DOC=""; RW_TASK_ID=""

# Exit 66. Implementation has not finished, so there is nothing to review.
rw_require_finished() {
  local who="$1"
  case "$(json_file_state "$FINISHED_FILE")" in
    missing)
      die 66 "$who: $FINISHED_FILE not found, so implementation has not finished for this task. Run the implement skill's finish step first; review reads the record it writes." ;;
    unreadable)
      die 3 "$who: $FINISHED_FILE exists but could not be read as JSON. Repair or remove it by hand before running this again." ;;
  esac
  RW_FINISHED_DOC="$(jq -c '.' "$FINISHED_FILE")"
}

# The ledger, for the run mode, and the snapshot, for the frozen contract and the frozen orders.
# Both exist whenever finished.json does, so either one absent is a tree this script reports rather
# than repairs.
rw_require_frozen() {
  local who="$1"
  case "$(json_file_state "$LEDGER_FILE")" in
    missing)    die 3 "$who: $LEDGER_FILE not found, though $FINISHED_FILE exists. The run mode is read from the ledger and nothing else holds it." ;;
    unreadable) die 3 "$who: $LEDGER_FILE exists but could not be read as JSON. Repair or remove it by hand before running this again." ;;
  esac
  RW_LEDGER_DOC="$(jq -c '.' "$LEDGER_FILE")"
  RW_RUN_MODE="$(printf '%s' "$RW_LEDGER_DOC" | jq -r '.runMode // "interactive"')"
  case "$(json_file_state "$SNAPSHOT_FILE")" in
    missing)    die 3 "$who: $SNAPSHOT_FILE not found, though $FINISHED_FILE exists. The frozen contract and the frozen orders are what review judges against." ;;
    unreadable) die 3 "$who: $SNAPSHOT_FILE exists but could not be read as JSON. Repair or remove it by hand before running this again." ;;
  esac
  RW_SNAPSHOT_DOC="$(jq -c '.' "$SNAPSHOT_FILE")"
  RW_TASK_ID="$(jq -r '.id // empty' "$TASK_PATH/task.json" 2>/dev/null)"
  [ -n "$RW_TASK_ID" ] || die 3 "$who: $TASK_PATH/task.json has no usable id field."
}

# The project record, for the frameworks and the two surface fields. rv_load_codepath has already
# said the file is valid JSON by the time this runs.
rw_load_project() {
  RW_PROJECT_DOC="$(jq -c '.' "$RV_PROJECT_FOLDER/project.json" 2>/dev/null)"
  [ -n "$RW_PROJECT_DOC" ] || die 14 "$1: $RV_PROJECT_FOLDER/project.json could not be read as JSON."
}

# Sets RW_RECORD_DOC to the record on disk, or the empty string when there is none. $1 the action.
rw_load_record() {
  local who="$1"
  RW_RECORD_DOC=""
  case "$(json_file_state "$RECORD_FILE")" in
    ok)         RW_RECORD_DOC="$(jq -c '.' "$RECORD_FILE")" ;;
    unreadable) die 3 "$who: $RECORD_FILE exists but could not be read as JSON. Move it aside by hand; review refuses to write over a record it cannot read." ;;
  esac
}

# True when the record holds a check row with id $1.
rw_record_has_check() {
  [ -n "$RW_RECORD_DOC" ] || return 1
  printf '%s' "$RW_RECORD_DOC" | jq -e --arg id "$1" '[ (.checks // [])[] | select(.id == $id) ] | length > 0' >/dev/null 2>&1
}

# Exit 62. A step whose input recorded nothing has nothing to act on, and a review that carried on
# would record a verdict read off a file that is not there. $1 the action, $2 the check id that
# proves the earlier step ran, $3 what to run instead.
rw_require_step() {
  local who="$1" marker="$2" advice="$3"
  rw_record_has_check "$marker" && return 0
  die 62 "$who: $RECORD_FILE records no $marker row, so the step before this one recorded nothing. Run $advice first."
}

# Which step this task is at, as one word the `read` report prints: checks, reviewer, surfaces,
# close or done. Read off the record's own rows, because each action writes rows nothing else
# writes; there is no separate state field, and a fourth place to keep one would be a fourth thing
# to keep in step.
rw_step_now() {
  if [ -z "$RW_RECORD_DOC" ]; then printf 'checks'; return; fi
  if printf '%s' "$RW_RECORD_DOC" | jq -e 'has("verdict")' >/dev/null 2>&1; then printf 'done'; return; fi
  if rw_record_has_check "$CHECK_E2E"; then printf 'close'; return; fi
  if rw_record_has_check "solid"; then printf 'surfaces'; return; fi
  if rw_record_has_check "$CHECK_SERVES"; then printf 'reviewer'; return; fi
  printf 'checks'
}

# Exit 63. A re-run archives the record a previous pass closed, and refuses when the move fails.
# Version 5 ran four review passes on one task, each overwriting the last, and pass three found a
# defect pass four's record does not mention. A record with no verdict is a pass still in flight and
# is updated in place: nothing in it has been concluded yet. The name reuses the shape `restart`
# writes. $1 the action.
rw_archive_closed_record() {
  local who="$1" short today target
  [ -n "$RW_RECORD_DOC" ] || return 0
  printf '%s' "$RW_RECORD_DOC" | jq -e 'has("verdict")' >/dev/null 2>&1 || return 0
  short="$(printf '%s' "$RW_RECORD_DOC" | jq -r '.reviewedAt // ""' | cut -c1-7)"
  [ -n "$short" ] || short="unknown"
  today="$(date -u +%Y-%m-%d)"
  target="$REVIEW_DIR/review-$today-$short.json"
  [ ! -e "$target" ] \
    || die 63 "$who: $target already exists, so archiving $RECORD_FILE would write over the record of an earlier pass. Move or remove that file by hand first; nothing has been written."
  mv "$RECORD_FILE" "$target" \
    || die 63 "$who: could not move $RECORD_FILE to $target, so the write was refused. The record of the previous pass is still there."
  echo "$(printf '%s' "$who" | tr '[:lower:]' '[:upper:]'): the previous review record moved to $target" >&2
  RW_RECORD_DOC=""
}

# Compares $2, the record as text, against scripts/review-schema.json through the same library
# check-project.sh and check-task.sh use, then writes it. A field the schema requires and the record
# does not hold, or one whose type or constraint the schema refuses, stops the write: a record this
# stage cannot read back is worse than no record. A field the schema marks optional may be absent,
# and `verdict` is the one that matters, because it is absent until `close`. $1 the action.
rw_write_record() {
  local who="$1" doc="$2" tmp result missing_required unreadable_fields
  mkdir -p "$REVIEW_DIR" || die 3 "$who: could not create $REVIEW_DIR"
  tmp="$(mktemp "$REVIEW_DIR/.review-candidate.XXXXXX")" \
    || die 3 "$who: could not create a temporary file in $REVIEW_DIR"
  printf '%s\n' "$doc" >"$tmp" || { rm -f "$tmp"; die 3 "$who: could not write $tmp"; }
  result="$(schema_check_compare "$REVIEW_SCHEMA" "$tmp")"
  if [ -z "$result" ]; then
    rm -f "$tmp"
    die 3 "$who: the record could not be compared against $REVIEW_SCHEMA."
  fi
  missing_required="$(jq -r --slurpfile schema "$REVIEW_SCHEMA" '
    ($schema[0].required // []) as $req
    | [ (.missing // [])[] | select(.field as $f | $req | index($f)) | .field ] | join(", ")' <<RW_SCHEMA_RESULT
$result
RW_SCHEMA_RESULT
)"
  unreadable_fields="$(jq -r '[ (.unreadable // [])[] | (.field + " (" + .reason + ")") ] | join("; ")' <<RW_SCHEMA_RESULT2
$result
RW_SCHEMA_RESULT2
)"
  if [ -n "$missing_required" ] || [ -n "$unreadable_fields" ]; then
    rm -f "$tmp"
    die 3 "$who: the record does not match $REVIEW_SCHEMA and was not written. Missing: ${missing_required:-none}. Wrong shape: ${unreadable_fields:-none}."
  fi
  rm -f "$tmp"
  write_atomic "$RECORD_FILE" "$doc"
}

# Exit 51. Every action after `checks` answers about the code `checks` read. $1 the action, $2
# whether the working tree must also still be clean (`clean` or `commit-only`).
#
# `findings` asks for both: the reviewer holds Write for one purpose, its own findings file, so a
# file it left in the code repository is caught here rather than read as a finding later. `surfaces`
# and `close` ask for the commit alone, because accepting a new surface baseline writes images into
# the code repository on purpose and the step that follows it would otherwise refuse.
rw_refuse_moved_code() {
  local who="$1" how="$2" recorded current dirty
  recorded="$(printf '%s' "$RW_RECORD_DOC" | jq -r '.reviewedAt // ""')"
  [ -n "$recorded" ] || die 62 "$who: $RECORD_FILE records no commit, so there is nothing to compare the code against. Run checks first."
  current="$(git -C "$RV_CODEPATH" rev-parse HEAD 2>/dev/null)"
  [ -n "$current" ] \
    || die 3 "$who: could not capture the current commit (git rev-parse HEAD failed in $RV_CODEPATH)."
  [ "$recorded" = "$current" ] \
    || die 51 "$who: $RV_CODEPATH is at $current, and the checks were run at $recorded. The code moved under this review, so what this step would record is about code that is no longer there."
  [ "$how" = "clean" ] || return 0
  dirty="$(git -C "$RV_CODEPATH" status --porcelain 2>/dev/null)"
  [ -z "$dirty" ] \
    || die 51 "$who: the working tree at $RV_CODEPATH is dirty, and the reviewer may write nothing but its own findings file. What changed: $(printf '%s' "$dirty" | tr '\n' ' ')"
}

# Exit 70. A person's answer is accepted only when a person is present, which is the rule
# tests-freeze already applies to its own rows and the number it already uses. $1 the action, $2 the
# flag, $3 what the flag would have decided.
rw_require_person() {
  local who="$1" flag="$2" what="$3"
  [ "$RW_RUN_MODE" = "autonomous" ] || return 0
  die 70 "$who: $flag says $what, and this run is autonomous. No person is here to answer, and an answer recorded as a person's is one nobody can list again later. Nothing is written."
}

# ------------------------------------------------------------------------------------------------
# Reading the frozen records.
# ------------------------------------------------------------------------------------------------

# The frozen contract, as an object.
rw_alignment() { printf '%s' "$RW_SNAPSHOT_DOC" | jq -c '.alignment // {}'; }

# Every work order's ownedFiles, as one JSON array with duplicates removed.
rw_owned_files() {
  printf '%s' "$RW_SNAPSHOT_DOC" | jq -c '[ (.workOrders // [])[] | (.ownedFiles // [])[] ] | unique'
}

# Every frozen test row, across every order's own tests-<unit>.json, as one JSON array. Walked with
# `find` and a while loop rather than a glob, so a task with no frozen record at all reads as an
# empty list instead of a literal pattern. $1 the action.
RW_TEST_ROWS="[]"
rw_load_test_rows() {
  local who="$1" list one doc
  RW_TEST_ROWS='[]'
  list="$(find "$IMPL_DIR" -maxdepth 1 -type f -name 'tests-*.json' 2>/dev/null | sort)"
  while IFS= read -r one; do
    [ -n "$one" ] || continue
    doc="$(jq -c '.' "$one" 2>/dev/null)"
    [ -n "$doc" ] \
      || die 3 "$who: $one exists but could not be read as JSON. Repair or remove it by hand before running this again."
    RW_TEST_ROWS="$(jq -nc --argjson have "$RW_TEST_ROWS" --argjson doc "$doc" \
      '$have + [ ($doc.rows // [])[] | . + {unit: ($doc.unit // "")} ]')"
  done <<RW_TEST_FILES
$list
RW_TEST_FILES
}

# ------------------------------------------------------------------------------------------------
# `read`: what is already there, and nothing written.
# ------------------------------------------------------------------------------------------------

# What an action prints. A summary, never a body: one `key: value` line at a time, and nothing that
# came out of a tool, a record, a diff or a research finding. The orchestrator reads this in its own
# conversation, and a record printed there costs the review the context its own steps need, so every
# line that a person may want to read in full is named by a path instead.
#
# $1 the record, $2 the action. The detail each check carries is this script's own wording, cut to one
# line, and the record holds the whole of it beside the command's own output.
rw_print_summary() {
  local doc="$1" who="$2"
  printf '%s' "$doc" | jq -r --arg who "$who" --arg record "$RECORD_FILE" '
    def line($k; $v): "\($k): \($v)";
    def short: (. // "") | gsub("\n"; " ") | .[0:160];
    [ line("action"; $who),
      line("task"; .task),
      line("range"; .reviewedRange),
      line("commit"; .reviewedAt),
      line("runMode"; .runMode) ]
    + [ (.recipes // [])[] | line("recipe(\(.framework))"; "lookup=\(.lookup) test=\(.testRecipe) check=\(.checkRecipe)") ]
    + [ (.checks // [])[] | line("check(\(.id))"; "\(.verdict) | \(.detail | short)") ]
    + [ (.criteria // [])[] | line("criterion(\(.id))"; "\(.verdict) answeredBy=\(.answeredBy)") ]
    + [ (.surfaces // [])[] | line("surface(\(.id))"; "\(.verdict) walked=\(.walked) ran=\(.ran)") ]
    + (if has("surfaceSetup") then [ line("surfaceSetup"; .surfaceSetup) ] else [] end)
    + [ line("mutation"; "\(.mutation.verdict) survivors=\((.mutation.survivors // []) | length) score=\(if (.mutation.score // "") == "" then "none printed" else "in the record" end)") ]
    + [ (.findings // []) | group_by(.lens)[] | line("lens(\(.[0].lens))"; "\(length) finding(s): \([ .[].id ] | join(", "))") ]
    + [ (.findings // []) | group_by(.disposition)[] | line("disposition(\(.[0].disposition))"; "\(length): \([ .[].id ] | join(", "))") ]
    + [ line("catalogNotes"; ((.catalogNotes // []) | length)) ]
    + (if has("verdict") then
         [ line("failing"; ([ ((.checks // [])[] | select(.verdict == "unmet" or .verdict == "unknown") | .id),
                              ((.criteria // [])[] | select(.verdict == "unmet" or .verdict == "unanswered") | .id) ] | join(", "))),
           line("verdict"; .verdict) ]
       else [] end)
    + [ line("record"; $record) ]
    | .[]'
}

do_read() {
  [ "$#" -ge 1 ] || die 3 "read: a task folder is required"
  [ "$#" -le 1 ] || die 3 "read: unrecognized extra argument: $2"
  rw_paths "read" "$1"

  local finished_state ledger_state record_state report
  local range final_commit machine_count person_count checklists_json
  local frameworks_json e2e_enabled vr_enabled registry_path code_state
  finished_state="$(json_file_state "$FINISHED_FILE")"
  ledger_state="$(json_file_state "$LEDGER_FILE")"
  record_state="$(json_file_state "$RECORD_FILE")"

  range=""; final_commit=""; machine_count=0; person_count=0
  checklists_json='[]'
  if [ "$finished_state" = "ok" ]; then
    RW_FINISHED_DOC="$(jq -c '.' "$FINISHED_FILE")"
    range="$(printf '%s' "$RW_FINISHED_DOC" | jq -r '.commitRange // ""')"
    final_commit="${range##*..}"
    machine_count="$(printf '%s' "$RW_FINISHED_DOC" | jq '[ (.criteria // [])[] | select(.verifiedBy == "machine") ] | length')"
    person_count="$(printf '%s' "$RW_FINISHED_DOC" | jq '[ (.criteria // [])[] | select(.verifiedBy == "person") ] | length')"
    # Every checklist row, whole and verbatim. `close` shows each one to the person and takes met or
    # unmet per row, and a summary asks a different question than the row a person signed up to
    # answer. This skill holds one Bash rule and no Read rule, so nothing else could open the file.
    checklists_json="$(printf '%s' "$RW_FINISHED_DOC" | jq -c '.checklists // []')"
  fi

  RW_RUN_MODE="interactive"
  [ "$ledger_state" = "ok" ] && RW_RUN_MODE="$(jq -r '.runMode // "interactive"' "$LEDGER_FILE")"

  frameworks_json='[]'; e2e_enabled="unknown"; vr_enabled="unknown"; registry_path=""
  code_state="unresolved"
  RV_PROJECT_FOLDER="$(resolve_project_folder "$TASK_PATH")" || RV_PROJECT_FOLDER=""
  if [ -n "$RV_PROJECT_FOLDER" ] && [ "$(json_file_state "$RV_PROJECT_FOLDER/project.json")" = "ok" ]; then
    RW_PROJECT_DOC="$(jq -c '.' "$RV_PROJECT_FOLDER/project.json")"
    frameworks_json="$(printf '%s' "$RW_PROJECT_DOC" | jq -c '.frameworks // []')"
    e2e_enabled="$(printf '%s' "$RW_PROJECT_DOC" | jq -r 'if (.e2e // null) == null then "not-set-up" elif (.e2e.enabled // false) then "on" else "off" end')"
    vr_enabled="$(printf '%s' "$RW_PROJECT_DOC" | jq -r 'if (.visualRegression // null) == null then "not-set-up" elif (.visualRegression.enabled // false) then "on" else "off" end')"
    registry_path="$(printf '%s' "$RW_PROJECT_DOC" | jq -r '.visualRegression.registryPath // ""')"
    code_state="$(printf '%s' "$RW_PROJECT_DOC" | jq -r '.codePath // ""')"
  fi

  rw_load_record "read"
  report="$(jq -n \
    --arg task "$(basename -- "$TASK_PATH")" \
    --arg finished "$finished_state" --arg range "$range" --arg final "$final_commit" \
    --arg runMode "$RW_RUN_MODE" --arg ledger "$ledger_state" \
    --argjson machine "$machine_count" --argjson person "$person_count" \
    --argjson checklistRows "$checklists_json" \
    --argjson frameworks "$frameworks_json" \
    --arg e2e "$e2e_enabled" --arg vr "$vr_enabled" --arg registry "$registry_path" \
    --arg codePath "$code_state" \
    --arg recordState "$record_state" --arg step "$(rw_step_now)" \
    --argjson record "${RW_RECORD_DOC:-null}" '
    {task: $task,
     finished: $finished,
     reviewedRange: $range,
     finalCommit: $final,
     runMode: $runMode,
     runModeSource: (if $ledger == "ok" then "the ledger" else "nothing read it; interactive is what absence means" end),
     criteria: {machineVerified: $machine, personVerified: $person, checklistRows: ($checklistRows | length)},
     checklists: $checklistRows,
     frameworks: $frameworks,
     codePath: $codePath,
     surfaces: {e2e: $e2e, visualRegression: $vr, registryPath: $registry},
     record: ({state: $recordState} + (($record // {}) | {checks: ((.checks // []) | length),
              findings: ((.findings // []) | length), surfaces: ((.surfaces // []) | length),
              verdict: (.verdict // "")})),
     nextStep: $step}')"
  [ -n "$report" ] || die 3 "read: could not assemble the report for $TASK_PATH."
  printf '%s\n' "$report"
  if [ "$finished_state" != "ok" ]; then
    echo "READ: implementation has not finished for this task. There is no $FINISHED_FILE, so there is nothing to review yet." >&2
  fi
  exit 0
}

# ------------------------------------------------------------------------------------------------
# `checks`: the diff once, every command the recipes declare, and checks 3 to 8.
# ------------------------------------------------------------------------------------------------

# The verdict a framework whose lookup failed contributes to every commanded check, and the line
# that says so. Two words, kept apart on purpose: a framework with no recipe answered, and a
# listing or a fetch that failed means nobody looked. Collapsing them writes a false finding
# nothing can tell from a true one. Sets RW_LOOKUP_FLOOR and RW_LOOKUP_NOTE.
RW_LOOKUP_FLOOR=""; RW_LOOKUP_NOTE=""
# What a block the parser could not read contributes to every check that reads it. `unparseable` is
# the heading being there while its key never opens under it, which is nobody having looked rather
# than a framework that declared nothing, so the word is unknown and it fails the review. A block
# that is simply absent stays undeclared, because a framework with no such block has answered.
RW_CHECK_FLOOR=""; RW_TEST_FLOOR=""; RW_BLOCK_NOTE=""
rw_lookup_floor() {
  local failures="$1" line fw reason
  RW_LOOKUP_FLOOR=""; RW_LOOKUP_NOTE=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    fw="${line%%	*}"
    reason="${line#*	}"
    case "$reason" in
      no-recipe)
        [ -n "$RW_LOOKUP_FLOOR" ] || RW_LOOKUP_FLOOR="undeclared"
        RW_LOOKUP_NOTE="$RW_LOOKUP_NOTE $fw declares no recipe for this point."
        ;;
      *)
        RW_LOOKUP_FLOOR="unknown"
        RW_LOOKUP_NOTE="$RW_LOOKUP_NOTE Nobody looked for $fw's recipe ($reason)."
        ;;
    esac
  done <<RW_FAILURES
$failures
RW_FAILURES
  RW_LOOKUP_NOTE="$(pc_trim "$RW_LOOKUP_NOTE")"
}

# One check row, as JSON. $1 id, $2 verdict, $3 detail, and the rest optional: $4 exit code or the
# empty string, $5 output, $6 framework, $7 `absent` when the recipe declared the row absent.
rw_check_row() {
  jq -n --arg id "$1" --arg verdict "$2" --arg detail "$3" \
        --arg exitCode "${4:-}" --arg output "${5:-}" --arg framework "${6:-}" \
        --arg absent "${7:-}" '
    {id: $id, verdict: $verdict, detail: $detail}
    + (if $framework == "" then {} else {framework: $framework} end)
    + (if $exitCode   == "" then {} else {exitCode: ($exitCode | tonumber), output: $output} end)
    + (if $absent     == "" then {} else {absent: true} end)'
}

# The worst of two verdicts, through the library's own ranking, so nothing here carries a second
# order for the four words.
rw_worse() {
  [ -n "$1" ] || { printf '%s' "$2"; return; }
  [ -n "$2" ] || { printf '%s' "$1"; return; }
  br_worst_verdict "$(jq -nc --arg a "$1" --arg b "$2" '[$a, $b]')"
}

RW_CHANGED_JSON="[]"; RW_CHANGED_COUNT=0; RW_RANGE=""; RW_HEAD=""
RW_VALUES=""; RW_CATALOG_NOTES="[]"

# One catalog note. Review writes nothing to the catalog: it records what it saw and names the count
# at close, and a person decides whether a note becomes a proposal.
rw_catalog_note() {
  RW_CATALOG_NOTES="$(jq -nc --argjson have "$RW_CATALOG_NOTES" --arg seen "$1" --arg where "$2" \
    '$have + [{seen: $seen, where: $where}]')"
}

# One commanded row's own run, in one place. Four callers repeat the same ladder otherwise: the
# temporary file, br_run_resolved, the two fields it prints, and the faults that decide nothing.
# $1 the argv array, $2 the JSON array a {paths} or {file} token expands to, $3 the tab-separated
# --value list, $4 the row's own `signal` or the empty string.
#
# Sets RW_RUN_KIND (UNRESOLVED, EMPTY or RAN), RW_RUN_PAYLOAD, RW_RUN_RC, RW_RUN_OUTPUT,
# RW_RUN_STDOUT_LEN and RW_RUN_OUTFILE. A caller reads its own verdict off those, calls rw_run_fault
# for the faults every caller words alike, and calls rw_run_done when it has finished with the file.
RW_RUN_KIND=""; RW_RUN_PAYLOAD=""; RW_RUN_RC=""; RW_RUN_OUTPUT=""
RW_RUN_STDOUT_LEN=0; RW_RUN_OUTFILE=""; RW_RUN_ERRFILE=""
RW_RUN_VERDICT=""; RW_RUN_DETAIL=""
# The surfaces a person accepted a baseline for and the accept rows that ran for them. Both are read
# back after every kind has answered: a surface nothing accepted refuses, and a row that already
# answered is not reported twice.
RW_ACCEPTED_DONE=""; RW_ACCEPTED_ROWS=""
rw_run_row() {
  local argv_json="$1" paths_json="$2" values="$3" signal="$4" result
  RW_RUN_KIND=""; RW_RUN_PAYLOAD=""; RW_RUN_RC=""; RW_RUN_OUTPUT=""; RW_RUN_STDOUT_LEN=0
  RW_RUN_OUTFILE="$(mktemp)" || die 3 "a temporary file for the command's output could not be created"
  RW_RUN_ERRFILE=""
  if [ -n "$signal" ]; then
    RW_RUN_ERRFILE="$(mktemp)" || die 3 "a temporary file for the command's standard error could not be created"
    result="$(br_run_resolved "$argv_json" "$RV_CODEPATH" "$RW_RUN_OUTFILE" "$paths_json" "$values" "$RW_RUN_ERRFILE")"
  else
    result="$(br_run_resolved "$argv_json" "$RV_CODEPATH" "$RW_RUN_OUTFILE" "$paths_json" "$values")"
  fi
  RW_RUN_KIND="$(printf '%s' "$result" | cut -f1)"
  RW_RUN_PAYLOAD="$(printf '%s' "$result" | cut -f2-)"
  [ "$RW_RUN_KIND" = "RAN" ] || return 0
  RW_RUN_RC="$RW_RUN_PAYLOAD"
  if [ -n "$signal" ]; then
    RW_RUN_STDOUT_LEN="$(wc -c <"$RW_RUN_OUTFILE" 2>/dev/null | tr -d '[:space:]')"
    case "$RW_RUN_STDOUT_LEN" in ''|*[!0-9]*) RW_RUN_STDOUT_LEN=0 ;; esac
    RW_RUN_OUTPUT="$(cat "$RW_RUN_OUTFILE" "$RW_RUN_ERRFILE" 2>/dev/null)"
  else
    RW_RUN_OUTPUT="$(cat "$RW_RUN_OUTFILE" 2>/dev/null)"
  fi
}

rw_run_done() {
  [ -z "$RW_RUN_OUTFILE" ] || rm -f "$RW_RUN_OUTFILE"
  [ -z "$RW_RUN_ERRFILE" ] || rm -f "$RW_RUN_ERRFILE"
  RW_RUN_OUTFILE=""; RW_RUN_ERRFILE=""
}

# The verdict and the detail for a run that decided nothing, worded once for every caller: a
# placeholder nothing supplied a value for, an argv with no token, a command that is not there, and
# an argv list that came out empty. Sets RW_RUN_VERDICT and RW_RUN_DETAIL, and clears both when the
# exit status is the caller's own to read. $1 the row's own label, $2 where a catalog note points, or
# empty for a caller that raises none.
rw_run_fault() {
  local label="$1" where="$2"
  RW_RUN_VERDICT=""; RW_RUN_DETAIL=""
  case "$RW_RUN_KIND" in
    UNRESOLVED)
      RW_RUN_VERDICT="unknown"
      RW_RUN_DETAIL="the token {$RW_RUN_PAYLOAD} in the $label command has no supplied value; pass --value $RW_RUN_PAYLOAD=<value>."
      return 0 ;;
    EMPTY)
      RW_RUN_VERDICT="unknown"
      RW_RUN_DETAIL="the $label command came out with no token at all, so nothing ran and nothing was decided."
      return 0 ;;
  esac
  case "$RW_RUN_RC" in
    127)
      RW_RUN_VERDICT="unknown"
      RW_RUN_DETAIL="the $label command could not be found (exit 127), so nothing ran and nothing was decided."
      [ -z "$where" ] || rw_catalog_note "the $label command the recipe declares could not be found" "$where" ;;
    126)
      RW_RUN_VERDICT="unknown"
      RW_RUN_DETAIL="the $label command list came out empty, so nothing ran and nothing was decided." ;;
  esac
}

# Check 3, the half a script can decide: a changed file no order owns is work no order asked for.
# The hunk half is the reviewer's, and its finding cites an id or is not acted on.
rw_check_serves() {
  local owned owned_count one matched gi glob unmatched=""
  owned="$(rw_owned_files)"
  owned_count="$(printf '%s' "$owned" | jq 'length')"
  if [ "$RW_CHANGED_COUNT" -eq 0 ]; then
    rw_check_row "$CHECK_SERVES" "met" "the range $RW_RANGE changed no file, so no file in it fails to match an order. The range itself is reported separately: a finished task whose range is empty is worth a person's attention."
    return 0
  fi
  matched=false; gi=0; glob=""
  while IFS= read -r one; do
    [ -n "$one" ] || continue
    matched=false
    gi=0
    while [ "$gi" -lt "$owned_count" ]; do
      glob="$(printf '%s' "$owned" | jq -r --argjson gi "$gi" '.[$gi]')"
      tf_path_matches_catalog_glob "$one" "$glob" && matched=true
      [ "$matched" = "true" ] && break
      gi=$((gi + 1))
    done
    [ "$matched" = "true" ] || unmatched="$unmatched$one, "
  done <<RW_CHANGED
$(printf '%s' "$RW_CHANGED_JSON" | jq -r '.[]')
RW_CHANGED
  if [ -n "$unmatched" ]; then
    rw_check_row "$CHECK_SERVES" "unmet" "these changed files match no work order's own ownedFiles, so nothing in the design asked for them: ${unmatched%, }"
  else
    rw_check_row "$CHECK_SERVES" "met" "every one of the $RW_CHANGED_COUNT changed files in $RW_RANGE matches some order's own ownedFiles."
  fi
}

# Check 4's script half: every criterion is covered by a frozen test naming it or by a checklist a
# person reads. A criterion covered by neither was signed off on nothing.
rw_check_coverage_verdict() {
  local criteria count i cid covered uncovered=""
  criteria="$(rw_alignment | jq -c '.criteria // []')"
  count="$(printf '%s' "$criteria" | jq 'length')"
  i=0; cid=""; covered=""
  while [ "$i" -lt "$count" ]; do
    cid="$(printf '%s' "$criteria" | jq -r --argjson i "$i" '.[$i].id')"
    covered="$(jq -nr --argjson rows "$RW_TEST_ROWS" --arg id "$cid" '
      [ $rows[] | select(.criterion == $id)
        | select(((.kind == "machine") and (((.tests // []) | length) > 0))
                 or ((.kind == "person") and ((.checklist // "") != ""))) ] | length > 0')"
    [ "$covered" = "true" ] || uncovered="$uncovered$cid, "
    i=$((i + 1))
  done
  if [ "$count" -eq 0 ]; then
    printf 'unknown\tthe frozen contract holds no criterion, so there is nothing a test could cover.'
    return 0
  fi
  if [ -n "$uncovered" ]; then
    printf 'unmet\tthese criteria are covered by no frozen test and no checklist row, so each was signed off on nothing: %s' "${uncovered%, }"
  else
    printf 'met\tevery one of the %s criteria carries a frozen test naming it or a checklist row a person reads.' "$count"
  fi
}

# The mutation row, run over the changed files. The score is the tool's own line, verbatim: the first
# output line naming a score, never a number parsed out of it, because no key in a recipe row declares
# the shape a score is printed in and the four tools print four shapes. A survivor is a line of that
# output naming one of the changed files, which is a string comparison and not a guess.
# Sets RW_MUTATION.
RW_MUTATION=""
rw_run_mutation() {
  local fw_count fwi fw_obj fw row outfile rc
  local detail output survivors score combined
  verdict=""; detail=""; output=""; survivors='[]'; score=""; combined=""
  fw_count="$(printf '%s' "$CR_DOC" | jq '(.frameworks // []) | length')"
  case "$fw_count" in ''|*[!0-9]*) fw_count=0 ;; esac
  fwi=0
  while [ "$fwi" -lt "$fw_count" ]; do
    fw_obj="$(printf '%s' "$CR_DOC" | jq -c --argjson i "$fwi" '.frameworks[$i]')"
    fw="$(printf '%s' "$fw_obj" | jq -r '.framework')"
    row="$(cr_row_command "$(printf '%s' "$fw_obj" | jq -c '.testCommandsRows // []')" "mutation" "mutation")"
    if [ "$(printf '%s' "$row" | jq -r 'has("argv")')" != "true" ]; then
      combined="$(rw_worse "$combined" "undeclared")"
      detail="$detail $fw: $(printf '%s' "$row" | jq -r '.absent // .missing')"
      fwi=$((fwi + 1))
      continue
    fi
    rw_run_row "$(printf '%s' "$row" | jq -c '.argv')" "$RW_CHANGED_JSON" "$RW_VALUES" ""
    rw_run_fault "mutation" "the test-execution recipe for $fw"
    if [ -n "$RW_RUN_VERDICT" ]; then
      combined="$(rw_worse "$combined" "$RW_RUN_VERDICT")"
      detail="$detail $fw: $RW_RUN_DETAIL"
      rw_run_done
      fwi=$((fwi + 1))
      continue
    fi
    rc="$RW_RUN_RC"
    output="$RW_RUN_OUTPUT"
    outfile="$RW_RUN_OUTFILE"
    score="$(printf '%s' "$output" | grep -i 'score' | head -1)"
    # The criterion a survivor belongs to, by exact path: the frozen test records say which test file
    # belongs to which criterion, and the frozen orders say which source file belongs to which order
    # and what that order serves. A survivor no path attaches is still recorded, because the
    # reviewer reads the whole list and a survivor nobody can attach is a fact rather than a finding.
    survivors="$(jq -Rn --argjson changed "$RW_CHANGED_JSON" --argjson rows "$RW_TEST_ROWS" \
      --argjson orders "$(printf '%s' "$RW_SNAPSHOT_DOC" | jq -c '.workOrders // []')" \
      --rawfile out "$outfile" '
      [ ($out | split("\n"))[]
        | . as $line
        | ($changed[]) as $f
        | select($line | contains($f))
        | {text: $line, file: $f,
           criterion: (([ $rows[] | select([ (.tests // [])[] | .path ] | index($f)) | .criterion ][0])
                       // ([ $orders[] | select((.ownedFiles // []) | index($f))
                             | ((.criteriaOwned // []) + (.criteriaServed // []))[] ][0])
                       // "")} ]
      | unique_by(.text)')"
    [ -n "$survivors" ] || survivors='[]'
    if [ "$(printf '%s' "$survivors" | jq 'length')" -gt 0 ]; then
      combined="$(rw_worse "$combined" "unmet")"
      detail="$detail $fw: the mutation command reported $(printf '%s' "$survivors" | jq 'length') line(s) naming a changed file, and a surviving mutant is a test nothing can fail."
    elif [ "$rc" = "0" ]; then
      combined="$(rw_worse "$combined" "met")"
      detail="$detail $fw: the mutation command exited 0 and named no changed file, so it reported no survivor in this change."
    else
      combined="$(rw_worse "$combined" "unknown")"
      detail="$detail $fw: the mutation command exited $rc and named no changed file, so nothing here can tell a failed run from a clean one."
      rw_catalog_note "the mutation command the recipe declares exited $rc" "the test-execution recipe for $fw"
    fi
    rw_run_done
    fwi=$((fwi + 1))
  done
  [ -n "$combined" ] || { combined="undeclared"; detail=" no framework recipe was resolved, so no mutation row was read."; }
  combined="$(rw_worse "$combined" "$RW_LOOKUP_FLOOR")"
  combined="$(rw_worse "$combined" "$RW_TEST_FLOOR")"
  detail="$detail $RW_LOOKUP_NOTE $RW_BLOCK_NOTE"
  RW_MUTATION="$(jq -n --arg verdict "$combined" --arg detail "$(pc_trim "$detail")" \
    --arg score "$score" --argjson survivors "$survivors" --arg output "$output" '
    {verdict: $verdict, detail: $detail, score: $score, survivors: $survivors}
    + (if $output == "" then {} else {output: $output} end)')"
}

# The baseline field that holds one tool row's own earlier verdict, or the empty string for a row
# the baseline has no field for. baseline-schema.json carries three tool fields and no more, so a
# duplication or design-metrics row the recipe declares has no baseline to subtract, and this says
# so rather than reading its absence as a clean one.
rw_baseline_field_for() {
  case "$1" in
    coding-standards) printf 'codingStandards' ;;
    static-analysis)  printf 'staticAnalysis' ;;
    security)         printf 'security' ;;
    *) printf '' ;;
  esac
}

# One tool row from the check commands block, run over the changed files. Every row the recipe
# declares is run, whatever its id. Prints the check row.
#
# The command, its `signal` and its `extensions` all come from the resolved recipe, never from a
# flag: a caller retyping a row drops a key, and a dropped `signal` turns a tool that cannot fail by
# exit status into a check that always passes. A failure is compared against the baseline step two
# took, because a finding that predates this build is not this task's, and blocking on it blocks
# every task forever.
rw_tool_row_check() {
  local row="$1" row_id framework argv signal exts scoped scoped_count has_paths
  local rc output failed how
  local verdict detail field baseline_doc baseline_verdict
  row_id="$(printf '%s' "$row" | jq -r '.id')"
  framework="$(printf '%s' "$row" | jq -r '.framework // ""')"
  verdict=""; detail=""; output=""; rc=""

  if [ "$(printf '%s' "$row" | jq -r '.absent // false')" = "true" ]; then
    rw_check_row "$row_id" "undeclared" "$(printf '%s' "$row" | jq -r '.absentReason // "the recipe declares this row absent"')" "" "" "$framework" "absent"
    return 0
  fi
  if [ "$(printf '%s' "$row" | jq -r 'has("missing")')" = "true" ]; then
    rw_check_row "$row_id" "undeclared" "$(printf '%s' "$row" | jq -r '.missing')" "" "" "$framework"
    return 0
  fi

  argv="$(printf '%s' "$row" | jq -c '.argv // []')"
  signal="$(printf '%s' "$row" | jq -r '.signal // ""')"
  exts="$(printf '%s' "$row" | jq -c 'if has("extensions") then .extensions else empty end')"
  has_paths=false
  printf '%s' "$argv" | jq -e 'any(.[]; . == "{paths}" or . == "{file}")' >/dev/null 2>&1 && has_paths=true
  scoped="$RW_CHANGED_JSON"
  [ -z "$exts" ] || scoped="$(br_filter_extensions "$RW_CHANGED_JSON" "$exts")"
  scoped_count="$(printf '%s' "$scoped" | jq 'length')"

  if [ "$has_paths" = "true" ] && [ "$RW_CHANGED_COUNT" -eq 0 ]; then
    rw_check_row "$row_id" "unknown" "the $row_id command holds a path placeholder, and $RW_RANGE changed no file, so the command would run over no path at all and answer about the whole repository." "" "" "$framework"
    return 0
  fi
  if [ "$has_paths" = "true" ] && [ -n "$exts" ] && [ "$scoped_count" -eq 0 ]; then
    rw_check_row "$row_id" "undeclared" "the $row_id command reads only $(printf '%s' "$exts" | jq -r 'join(", ")'), and this change touches no file with one of those extensions, so the row does not apply to it." "" "" "$framework"
    return 0
  fi

  rw_run_row "$argv" "$scoped" "$RW_VALUES" "$signal"
  rw_run_fault "$row_id" "the review recipe for ${framework:-this project}"
  verdict="$RW_RUN_VERDICT"; detail="$RW_RUN_DETAIL"
  if [ -z "$verdict" ]; then
    rc="$RW_RUN_RC"
    output="$RW_RUN_OUTPUT"
    failed=false; how=""
    if [ "$rc" = "0" ] && [ -n "$signal" ] && [ "$RW_RUN_STDOUT_LEN" -gt 0 ]; then
      failed=true
      how="exited 0 and printed on standard output, which its row's own signal empty-stdout makes a finding"
    elif [ "$rc" != "0" ]; then
      failed=true
      how="exited $rc"
    fi
    if [ "$failed" = "false" ]; then
      verdict="met"
      detail="the $row_id command exited 0 over the files this change touched."
    else
      field="$(rw_baseline_field_for "$row_id")"
      baseline_verdict=""
      if [ -n "$field" ] && [ -f "$BASELINE_FILE" ]; then
        baseline_doc="$(jq -c '.' "$BASELINE_FILE" 2>/dev/null)"
        [ -z "$baseline_doc" ] || baseline_verdict="$(printf '%s' "$baseline_doc" | jq -r --arg f "$field" '.[$f].verdict // ""')"
      fi
      case "${field:+$baseline_verdict}" in
        met)
          verdict="unmet"
          detail="the $row_id command $how, and the baseline recorded this tool met at the commit the build started from; this task introduced the finding." ;;
        unmet|unknown|undeclared)
          verdict="unknown"
          detail="the $row_id command $how, and the baseline recorded this tool $baseline_verdict at the commit the build started from, so this cannot tell an old finding from an old one plus a new one." ;;
        *)
          # Two ways to get here, and the detail tells them apart: the baseline holds no field for
          # this row at all, which is every row beyond the three the baseline knows, or it holds one
          # and the file could not be read.
          verdict="unknown"
          detail="the $row_id command $how, and ${field:+$BASELINE_FILE could not be read for the baseline verdict of this tool}${field:-the baseline holds no field for this row}, so this cannot tell a finding this task introduced from one that predates it." ;;
      esac
    fi
  fi
  rw_run_done
  verdict="$(rw_worse "$verdict" "$RW_LOOKUP_FLOOR")"
  verdict="$(rw_worse "$verdict" "$RW_CHECK_FLOOR")"
  detail="$detail $RW_LOOKUP_NOTE $RW_BLOCK_NOTE"
  rw_check_row "$row_id" "$verdict" "$(pc_trim "$detail")" "$rc" "$output" "$framework"
}

# Check 8: the whole suite, at the final commit, once per framework. It reads the recipe's own
# outcome words and not the exit status alone: three of the five frameworks print that nothing was
# selected and exit zero, and a silent pass reads unknown, never met.
rw_check_suite() {
  local fw_count fwi fw_obj fw cmd outfile rc output
  local verdict detail marker combined outputs exit_max
  combined=""; detail=""; outputs=""; exit_max=""
  fw_count="$(printf '%s' "$CR_DOC" | jq '(.frameworks // []) | length')"
  case "$fw_count" in ''|*[!0-9]*) fw_count=0 ;; esac
  fwi=0; marker=""
  while [ "$fwi" -lt "$fw_count" ]; do
    fw_obj="$(printf '%s' "$CR_DOC" | jq -c --argjson i "$fwi" '.frameworks[$i]')"
    fw="$(printf '%s' "$fw_obj" | jq -r '.framework')"
    cmd="$(printf '%s' "$fw_obj" | jq -c '.suite // {}')"

    verdict=""; rc=""
    if [ "$(printf '%s' "$cmd" | jq -r 'has("argv")')" != "true" ]; then
      verdict="undeclared"
      detail="$detail $fw: $(printf '%s' "$cmd" | jq -r '.absent // .missing')"
    else
      rw_run_row "$(printf '%s' "$cmd" | jq -c '.argv')" '[]' "$RW_VALUES" ""
      rw_run_fault "suite" "the test-execution recipe for $fw"
      outfile="$RW_RUN_OUTFILE"
      if [ -n "$RW_RUN_VERDICT" ]; then
        verdict="$RW_RUN_VERDICT"
        detail="$detail $fw: $RW_RUN_DETAIL"
      else
        rc="$RW_RUN_RC"
        output="$RW_RUN_OUTPUT"
        outputs="$outputs$output
"
        # The worst exit status across the frameworks, never the last one. Two frameworks where the
        # first fails and the second passes would otherwise record a zero beside a verdict of unmet.
        if [ -z "$exit_max" ] || [ "$rc" -gt "$exit_max" ]; then exit_max="$rc"; fi
        # The first marker the recipe declares that this output holds, asked once. The markers are
        # the recipe's own words for a run that selected nothing, harvested by the library.
        marker="$(jq -rn --argjson m "$(printf '%s' "$fw_obj" | jq -c '.silentPass // []')" \
          --rawfile out "$outfile" '[ $m[] as $one | select($out | contains($one)) | $one ][0] // ""')"
        if [ -n "$marker" ]; then
          verdict="unknown"
          detail="$detail $fw: the suite output holds the recipe's own silent-pass marker ('$marker'), so an exit status cannot decide a run that selected nothing."
        elif [ "$rc" = "0" ]; then
          verdict="met"
          detail="$detail $fw: the suite exited 0 at the final commit."
        else
          verdict="unmet"
          detail="$detail $fw: the suite exited $rc at the final commit, so the finished task fails its own tests."
        fi
      fi
      rw_run_done
    fi
    combined="$(rw_worse "$combined" "$verdict")"
    fwi=$((fwi + 1))
  done
  if [ -z "$combined" ]; then
    combined="undeclared"
    detail=" no framework recipe was resolved, so the suite was not run."
  fi
  combined="$(rw_worse "$combined" "$RW_LOOKUP_FLOOR")"
  combined="$(rw_worse "$combined" "$RW_TEST_FLOOR")"
  detail="$detail $RW_LOOKUP_NOTE $RW_BLOCK_NOTE"
  rw_check_row "$CHECK_SUITE" "$combined" "$(pc_trim "$detail")" "$exit_max" "$outputs"
}

do_checks() {
  local task_arg="" recipes="" check_recipes="" failures="" values=""
  local frameworks fw lookup recipes_json rows_file parts_file
  local range base head_end head_now coverage cov_verdict cov_detail
  local mut_verdict tool_count ti one checks_json record_json today floor_id
  local upstream empty_range

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --recipe)
        [ "$#" -ge 2 ] || die 3 "checks: --recipe needs <framework>=<path>"
        cr_recipe_pair "checks" "--recipe" "$2"
        recipes="$recipes$CR_PAIR
"
        shift 2 ;;
      --check-recipe)
        [ "$#" -ge 2 ] || die 3 "checks: --check-recipe needs <framework>=<path>"
        cr_recipe_pair "checks" "--check-recipe" "$2"
        check_recipes="$check_recipes$CR_PAIR
"
        shift 2 ;;
      --lookup-failed)
        [ "$#" -ge 2 ] || die 3 "checks: --lookup-failed needs <framework>=<reason>"
        cr_lookup_failure_pair "checks" "--lookup-failed" "$2"
        failures="$failures$CR_PAIR
"
        shift 2 ;;
      --value)
        [ "$#" -ge 2 ] || die 3 "checks: --value needs <name>=<value>"
        case "$2" in *=*) ;; *) die 3 "checks: --value takes <name>=<value>, got: $2" ;; esac
        pc_refuse_forged_value "checks" "$2"
        values="$values$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      -*) die 3 "checks: unrecognized argument: $1" ;;
      *)
        [ -z "$task_arg" ] || die 3 "checks: more than one task folder given"
        task_arg="$1"; shift ;;
    esac
  done

  rw_paths "checks" "$task_arg"
  rw_require_finished "checks"
  rw_require_frozen "checks"
  rv_load_codepath "checks"
  rw_load_project "checks"

  # The range is a claim about what the repository holds, and uncommitted work makes it a claim
  # about something else. `finish` refuses this way already, and this is that same refusal.
  br_require_clean_tree "checks" "$RV_CODEPATH"

  frameworks="$(printf '%s' "$RW_PROJECT_DOC" | jq -r '.frameworks // [] | .[]')"
  [ -n "$frameworks" ] \
    || die 77 "checks: $RV_PROJECT_FOLDER/project.json is valid and records no framework, so no recipe can be chosen for this project. Exit 14 is the separate fact that the file is not valid JSON."

  # A framework nobody answered for either way is a caller that did not look. Guessing here would
  # turn a lookup nobody ran into a recipe that declared nothing.
  recipes_json='[]'
  lookup=""
  while IFS= read -r fw; do
    [ -n "$fw" ] || continue
    lookup="$(cr_lookup "$failures" "$fw")"
    if [ -n "$(cr_lookup "$recipes" "$fw")" ] || [ -n "$(cr_lookup "$check_recipes" "$fw")" ]; then
      [ -z "$lookup" ] \
        || die 3 "checks: framework $fw was given both a recipe and a --lookup-failed ($lookup). One of the two is wrong, and nothing here may choose."
      lookup="resolved"
    fi
    [ -n "$lookup" ] \
      || die 3 "checks: nothing was said about the recipes for framework $fw; pass --recipe and --check-recipe for it, or --lookup-failed with the reason its lookup failed."
    recipes_json="$(jq -nc --argjson have "$recipes_json" --arg fw "$fw" --arg lookup "$lookup" \
      --arg test "$(cr_lookup "$recipes" "$fw")" --arg check "$(cr_lookup "$check_recipes" "$fw")" \
      '$have + [{framework: $fw, testRecipe: $test, checkRecipe: $check, lookup: $lookup}]')"
  done <<RW_FRAMEWORKS
$frameworks
RW_FRAMEWORKS

  rw_lookup_floor "$failures"
  RW_VALUES="$values"
  # shellcheck disable=SC2034 # read by the sourced library
  CR_WHO="checks"
  # shellcheck disable=SC2034 # read by the sourced library
  CR_TEST_RECIPES="$recipes"
  # shellcheck disable=SC2034 # read by the sourced library
  CR_CHECK_RECIPES="$check_recipes"
  # Every row the check commands block declares is run and recorded, not only the three tool ids
  # implementation reads.
  # shellcheck disable=SC2034 # read by the sourced library
  CR_TOOL_IDS_ALL=true
  cr_resolve
  # Exit 73. Checks 5 to 7 subtract the baseline, and that subtraction is only honest while both runs
  # read the same check recipe. A catalog refresh between the build and the review is ordinary, and
  # the same refusal implementation makes is what keeps review from calling a finding this task's
  # when a different tool produced it.
  cr_require_baseline_recipes "checks" "$BASELINE_FILE"
  RW_CHECK_FLOOR=""; RW_TEST_FLOOR=""; RW_BLOCK_NOTE=""
  if [ "$(printf '%s' "$CR_DOC" | jq '[ (.frameworks // [])[] | select(.checkCommandsState == "unparseable") ] | length')" -gt 0 ]; then
    RW_CHECK_FLOOR="unknown"
    RW_BLOCK_NOTE="The check commands block could not be read: its heading is there and its key never opens under it."
    rw_catalog_note "the check commands block's heading is there and its key never opens under it" "$(printf '%s' "$CR_DOC" | jq -r '[ (.frameworks // [])[] | select(.checkCommandsState == "unparseable") | .checkRecipe ] | join(", ")')"
  fi
  if [ "$(printf '%s' "$CR_DOC" | jq '[ (.frameworks // [])[] | select(.testCommandsState == "unparseable") ] | length')" -gt 0 ]; then
    RW_TEST_FLOOR="unknown"
    RW_BLOCK_NOTE="$RW_BLOCK_NOTE The test commands block could not be read the same way."
    rw_catalog_note "the test commands block's heading is there and its key never opens under it" "$(printf '%s' "$CR_DOC" | jq -r '[ (.frameworks // [])[] | select(.testCommandsState == "unparseable") | .testRecipe ] | join(", ")')"
  fi
  RW_BLOCK_NOTE="$(pc_trim "$RW_BLOCK_NOTE")"

  # --- the change set, read and never derived -----------------------------------------------------
  range="$(printf '%s' "$RW_FINISHED_DOC" | jq -r '.commitRange // ""')"
  case "$range" in
    *..*) ;;
    *) die 3 "checks: $FINISHED_FILE holds no usable commitRange ('$range'). That field is the change set, and review computes none of its own." ;;
  esac
  base="${range%%..*}"
  head_end="${range##*..}"
  git -C "$RV_CODEPATH" rev-parse --verify "$base^{commit}" >/dev/null 2>&1 \
    || die 3 "checks: the commit $base, the left end of the range in $FINISHED_FILE, is not a commit in $RV_CODEPATH."
  git -C "$RV_CODEPATH" rev-parse --verify "$head_end^{commit}" >/dev/null 2>&1 \
    || die 3 "checks: the commit $head_end, the right end of the range in $FINISHED_FILE, is not a commit in $RV_CODEPATH."
  head_now="$(git -C "$RV_CODEPATH" rev-parse HEAD 2>/dev/null)"
  [ -n "$head_now" ] \
    || die 3 "checks: could not capture the current commit (git rev-parse HEAD failed in $RV_CODEPATH)."
  [ "$head_now" = "$(git -C "$RV_CODEPATH" rev-parse "$head_end^{commit}" 2>/dev/null)" ] \
    || die 3 "checks: $RV_CODEPATH is at $head_now, and the range in $FINISHED_FILE ends at $head_end. Checks 5 to 8 run over the files on disk, so a tree that is not the final commit would answer about different code than the diff describes. Check that commit out, or run the implement skill's finish step again."
  RW_RANGE="$range"; RW_HEAD="$head_now"

  mark_task_in_progress "$TASK_PATH" "review started"
  mkdir -p "$REVIEW_DIR" || die 3 "checks: could not create $REVIEW_DIR"
  git -C "$RV_CODEPATH" diff --no-renames "$base" "$head_end" >"$DIFF_FILE" 2>/dev/null \
    || die 3 "checks: could not write the diff for $range to $DIFF_FILE"
  # --no-renames: git reads a delete plus an add as one rename by default, and a rename shows only
  # the new path, so a deleted file no order owns would never appear in the changed list.
  RW_CHANGED_JSON="$(git -C "$RV_CODEPATH" diff --no-renames --name-only "$base" "$head_end" 2>/dev/null \
    | jq -Rsc 'split("\n") | map(select(length > 0))')"
  [ -n "$RW_CHANGED_JSON" ] || RW_CHANGED_JSON='[]'
  RW_CHANGED_COUNT="$(printf '%s' "$RW_CHANGED_JSON" | jq 'length')"
  empty_range="no"
  [ "$base" = "$RW_HEAD" ] && empty_range="yes"
  upstream="$(git -C "$RV_CODEPATH" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"

  rw_load_test_rows "checks"

  # --- the checks a script decides ----------------------------------------------------------------
  parts_file="$(mktemp)" || die 3 "checks: could not create a temporary file"
  rw_check_serves >>"$parts_file"

  coverage="$(rw_check_coverage_verdict)"
  cov_verdict="$(printf '%s' "$coverage" | cut -f1)"
  cov_detail="$(printf '%s' "$coverage" | cut -f2-)"
  rw_run_mutation
  mut_verdict="$(printf '%s' "$RW_MUTATION" | jq -r '.verdict')"
  rw_check_row "$CHECK_TEST_MUTATION" "$(rw_worse "$cov_verdict" "$mut_verdict")" \
    "$cov_detail The mutation row: $(printf '%s' "$RW_MUTATION" | jq -r '.detail')" >>"$parts_file"

  tool_count="$(printf '%s' "$CR_DOC" | jq '(.tools // []) | length')"
  case "$tool_count" in ''|*[!0-9]*) tool_count=0 ;; esac
  ti=0; one=""
  while [ "$ti" -lt "$tool_count" ]; do
    one="$(printf '%s' "$CR_DOC" | jq -c --argjson i "$ti" '.tools[$i]')"
    rw_tool_row_check "$one" >>"$parts_file"
    ti=$((ti + 1))
  done
  # The three ids below are a floor the recipe may add to and never a list it may shorten, so each one
  # no row declared still gets a row of its own. A check with no row at all is a check a reader cannot
  # see was never answered, and version 5 printed that four times.
  for floor_id in coding-standards static-analysis security; do
    if [ "$(printf '%s' "$CR_DOC" | jq --arg id "$floor_id" '[ (.tools // [])[] | select(.id == $id) ] | length')" -eq 0 ]; then
      rw_check_row "$floor_id" \
        "$(rw_worse "$(rw_worse "undeclared" "$RW_LOOKUP_FLOOR")" "$RW_CHECK_FLOOR")" \
        "$(pc_trim "no resolved review recipe carries a check commands row with this id, so this tool did not run. The three tool ids are a floor, never a list a recipe may shorten. $RW_LOOKUP_NOTE $RW_BLOCK_NOTE")" >>"$parts_file"
    fi
  done

  rw_check_suite >>"$parts_file"

  checks_json="$(jq -s '.' "$parts_file")" || die 3 "checks: could not assemble the check rows"
  rm -f "$parts_file"

  # A re-review archives the record the previous pass closed before anything is written.
  rw_load_record "checks"
  rw_archive_closed_record "checks"

  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -n --arg takenAt "$today" --arg task "$RW_TASK_ID" \
    --arg range "$range" --arg commit "$head_now" --arg runMode "$RW_RUN_MODE" \
    --argjson hasUpstream "$([ -n "$upstream" ] && echo true || echo false)" \
    --argjson recipes "$recipes_json" --argjson checks "$checks_json" \
    --argjson resolved "$CR_DOC" \
    --argjson mutation "$RW_MUTATION" --argjson notes "$RW_CATALOG_NOTES" '
    {schemaVersion: 1, takenAt: $takenAt, task: $task,
     reviewedRange: $range, reviewedAt: $commit, hasUpstream: $hasUpstream, runMode: $runMode,
     # The sha of each recipe this run read sits beside its path, the way the baseline records its
     # own, so a reader can compare the two files rather than take a refusal'"'"'s word for it.
     recipes: [ $recipes[] | . as $row
                | ([ ($resolved.frameworks // [])[] | select(.framework == $row.framework) ][0]) as $fw
                | $row + {checkRecipeSha256: ($fw.checkRecipeSha256 // ""),
                          testRecipeSha256: ($fw.testRecipeSha256 // "")} ],
     checks: $checks,
     criteria: [], findings: [], surfaces: [],
     mutation: $mutation, catalogNotes: $notes}')"
  [ -n "$record_json" ] || die 3 "checks: could not assemble the review record for $RW_TASK_ID."
  rw_write_record "checks" "$record_json"

  rw_print_summary "$record_json" "checks"
  printf 'changedFiles: %s\n' "$RW_CHANGED_COUNT"
  printf 'diff: %s\n' "$DIFF_FILE"
  echo "CHECKS: the diff for $range is at $DIFF_FILE ($RW_CHANGED_COUNT changed files)." >&2
  if [ "$empty_range" = "yes" ]; then
    echo "CHECKS: the range $range holds no commit. It resolved, and the two ends are the same commit, so this task committed nothing." >&2
  fi
  if [ -z "$upstream" ]; then
    echo "CHECKS: the branch checked out in $RV_CODEPATH has no upstream, so this work is on one machine only." >&2
  fi
  [ -z "$RW_LOOKUP_NOTE" ] || echo "CHECKS: $RW_LOOKUP_NOTE" >&2
  exit 0
}

# ------------------------------------------------------------------------------------------------
# `brief`: everything the architecture reviewer may see, and nothing else.
# ------------------------------------------------------------------------------------------------

do_brief() {
  [ "$#" -ge 1 ] || die 3 "brief: a task folder is required"
  [ "$#" -le 1 ] || die 3 "brief: unrecognized extra argument: $2"
  rw_paths "brief" "$1"
  rw_require_finished "brief"
  rw_require_frozen "brief"
  # The reviewer reads the code at the final commit where a lens needs more than the diff, so the
  # brief names the repository it may read.
  rv_load_codepath "brief"
  rw_load_record "brief"
  rw_require_step "brief" "$CHECK_SERVES" "checks"

  local research_json list one doc brief_json
  research_json='[]'
  list="$(find "$TASK_PATH/research" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)"
  while IFS= read -r one; do
    [ -n "$one" ] || continue
    doc="$(jq -c '.' "$one" 2>/dev/null)"
    [ -n "$doc" ] \
      || die 3 "brief: $one exists but could not be read as JSON. Repair or remove it by hand before running this again."
    research_json="$(jq -nc --argjson have "$research_json" --argjson doc "$doc" --arg file "$one" '
      $have + [{file: $file, search: ($doc.search // ""), searchedFor: ($doc.searchedFor // ""),
                findings: [ ($doc.findings // [])[]
                  | {text, source, lookedAt, criteriaServed: (.criteriaServed // [])} ]}]')"
  done <<RW_RESEARCH
$list
RW_RESEARCH
  # Whether each cited source is on disk, so the reviewer names a body it could not open as unread
  # rather than answering as though it had read it. The paths are tested once, in one pass, and one
  # jq marks every finding from that list: a test per finding reran jq twice for each one.
  local src on_disk
  on_disk='[]'
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    if [ -e "$src" ] || [ -e "$RV_CODEPATH/$src" ]; then
      on_disk="$(jq -nc --argjson have "$on_disk" --arg s "$src" '$have + [$s]')"
    fi
  done <<RW_SOURCES
$(printf '%s' "$research_json" | jq -r '[ .[].findings[].source ] | unique | .[]')
RW_SOURCES
  research_json="$(printf '%s' "$research_json" | jq -c --argjson found "$on_disk" '
    [ .[] | .findings = [ .findings[] | . as $f | .onDisk = (($found | index($f.source)) != null) ] ]')"

  brief_json="$(jq -n --arg task "$RW_TASK_ID" --arg diff "$DIFF_FILE" \
    --arg findings "$FINDINGS_TARGET" --arg codePath "$RV_CODEPATH" \
    --argjson alignment "$(rw_alignment)" --argjson snap "$RW_SNAPSHOT_DOC" \
    --argjson record "$RW_RECORD_DOC" --argjson research "$research_json" \
    --argjson finished "$RW_FINISHED_DOC" --arg lenses "$LENS_WORDS" '
    {task: $task,
     codePath: $codePath,
     reviewedRange: $record.reviewedRange,
     reviewedAt: $record.reviewedAt,
     runMode: $record.runMode,
     diffPath: $diff,
     findingsPath: $findings,
     lenses: ($lenses | split(" ")),
     criteria: [ ($alignment.criteria // [])[] | {id, text, verification, verifiedBy} ],
     nonGoals: ($alignment.nonGoals // []),
     workOrders: ($snap.workOrders // []),
     research: $research,
     deferredFindings: ($finished.deferred // []),
     checks: [ ($record.checks // [])[]
               | select(.id != "serves-a-criterion")
               | {id, verdict, detail, framework: (.framework // ""), output: (.output // "")} ],
     mutation: $record.mutation}')"
  [ -n "$brief_json" ] || die 3 "brief: could not assemble the brief for $RW_TASK_ID."
  mkdir -p "$REVIEW_DIR" || die 3 "brief: could not create $REVIEW_DIR"
  # The brief is a file the dispatch names, never text printed through this conversation: it carries
  # the contract, every order and every research finding, and printing it would spend the reviewer's
  # own context twice over.
  write_atomic "$BRIEF_FILE" "$brief_json"
  printf '%s' "$brief_json" | jq -r --arg brief "$BRIEF_FILE" --arg findings "$FINDINGS_TARGET" \
    --arg diff "$DIFF_FILE" --arg code "$RV_CODEPATH" '
    def line($k; $v): "\($k): \($v)";
    [ line("action"; "brief"),
      line("brief"; $brief),
      line("findingsPath"; $findings),
      line("diff"; $diff),
      line("codePath"; $code),
      line("criteria"; (.criteria | length)),
      line("nonGoals"; (.nonGoals | length)),
      line("workOrders"; (.workOrders | length)),
      line("lenses"; (.lenses | join(" "))),
      line("researchFiles"; (.research | length)),
      line("researchPaths(onDisk)"; ([ .research[].findings[] | select(.onDisk) ] | length)),
      line("researchPaths(notOnDisk)"; ([ .research[].findings[] | select(.onDisk | not) ] | length)),
      line("deferredFindings"; (.deferredFindings | length)) ] | .[]'
  echo "BRIEF: give the reviewer $BRIEF_FILE, and tell it to write its findings to $FINDINGS_TARGET and nowhere else." >&2
  exit 0
}

# ------------------------------------------------------------------------------------------------
# `findings`: what the reviewer found, and the six checks that read their verdict off a lens.
# ------------------------------------------------------------------------------------------------

# The check each lens answers. One word in, one check id out, and nothing else maps the two.
rw_check_for_lens() {
  case "$1" in
    non-goals)    printf 'non-goals' ;;
    solid)        printf 'solid' ;;
    dry)          printf 'dry' ;;
    architecture) printf 'architecture-fit' ;;
    guides)       printf 'guides' ;;
    practices)    printf 'framework-practices' ;;
    mutation)     printf 'test-and-mutation' ;;
    *)            printf '' ;;
  esac
}

do_findings() {
  local task_arg="" findings_path=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --findings)
        [ "$#" -ge 2 ] || die 3 "findings: --findings needs a path to the file the reviewer wrote"
        looks_like_flag "$2" && die 3 "findings: --findings was given another flag, not a path: $2"
        findings_path="$2"; shift 2 ;;
      -*) die 3 "findings: unrecognized argument: $1" ;;
      *)
        [ -z "$task_arg" ] || die 3 "findings: more than one task folder given"
        task_arg="$1"; shift ;;
    esac
  done
  [ -n "$task_arg" ]      || die 3 "findings: a task folder is required"
  [ -n "$findings_path" ] || die 3 "findings: --findings is required. An absent findings file is never a clean review."

  rw_paths "findings" "$task_arg"
  rw_require_finished "findings"
  rw_require_frozen "findings"
  rv_load_codepath "findings"
  rw_load_record "findings"
  rw_require_step "findings" "$CHECK_SERVES" "checks"
  rw_refuse_moved_code "findings" "clean"

  local raw count i one lens cid linked disposition built findings_json alignment
  rv_read_findings_array "$findings_path" "findings" "findings"
  raw="$RV_FINDINGS_ARRAY"
  alignment="$(rw_alignment)"
  findings_json='[]'
  count="$(printf '%s' "$raw" | jq 'length')"
  i=0; lens=""; linked=""; disposition=""; built=""; cid=""
  while [ "$i" -lt "$count" ]; do
    one="$(printf '%s' "$raw" | jq -c --argjson i "$i" '.[$i]')"
    cid="$(printf '%s' "$one" | jq -r '.id')"
    lens="$(printf '%s' "$one" | jq -r '.lens // ""')"
    case " $LENS_WORDS " in
      *" $lens "*) ;;
      *) die 52 "findings: finding $cid in $findings_path names the lens '$lens'. The seven lens words are $LENS_WORDS, and each of six checks reads its verdict off its own lens, so a word outside that list would leave a check reading met on a findings file that is not empty." ;;
    esac
    linked="$(printf '%s' "$one" | jq -r '.linkedTo // ""')"
    disposition="$(jq -nr --argjson a "$alignment" --arg l "$linked" '
      if $l == "" then "follow-up"
      elif (($a.criteria // []) | map(.id) | index($l)) != null then "criterion"
      elif (($a.nonGoals // []) | map(.id) | index($l)) != null then "non-goal"
      else "follow-up" end')"
    built="$(printf '%s' "$one" | jq -c --arg disposition "$disposition" '
      {id, lens, severity, file: (.file // ""), lines: (.lines // ""),
       linkedTo: (.linkedTo // ""), evidence, disposition: $disposition}')"
    findings_json="$(jq -nc --argjson have "$findings_json" --argjson one "$built" '$have + [$one]')"
    i=$((i + 1))
  done

  # Each check reads its verdict off its own lens: met when that lens returned nothing, unmet when
  # it returned a finding. An absent verdict is never a clean one, and version 5 paid for that four
  # times, which is why every one of the six is written here rather than left out.
  local rows_file lens_word check_id hits updated
  rows_file="$(mktemp)" || die 3 "findings: could not create a temporary file"
  for lens_word in non-goals solid dry architecture guides practices; do
    check_id="$(rw_check_for_lens "$lens_word")"
    # Met when this lens returned nothing, unmet when it returned a finding. An absent verdict is
    # never a clean one, which is why every one of the six is written whatever the file held.
    hits="$(printf '%s' "$findings_json" | jq -r --arg l "$lens_word" \
      '[ .[] | select(.lens == $l) | (.id + " cites " + (if .linkedTo == "" then "nothing" else .linkedTo end)) ] | join(", ")')"
    if [ -n "$hits" ]; then
      rw_check_row "$check_id" "unmet" "the $lens_word lens raised these findings: $hits" >>"$rows_file"
    else
      rw_check_row "$check_id" "met" "the $lens_word lens returned no finding over the diff at $(printf '%s' "$RW_RECORD_DOC" | jq -r '.reviewedAt')." >>"$rows_file"
    fi
  done
  # The reviewer adds a catalog note the same way the script does: a guide the code contradicts, a
  # recipe whose command no longer runs, a pattern the framework wants and no guide names. Review
  # writes nothing to the catalog, so a note is kept as evidence and named at close. A findings file
  # with no such key adds none, which is the ordinary case.
  local reviewer_notes
  reviewer_notes="$(jq -c 'if ((.catalogNotes // []) | type) == "array"
    then [ (.catalogNotes // [])[] | select((.seen // "") != "" and (.where // "") != "")
           | {seen: .seen, where: .where} ]
    else [] end' "$findings_path" 2>/dev/null)"
  [ -n "$reviewer_notes" ] || reviewer_notes='[]'
  updated="$(jq -s -c --argjson record "$RW_RECORD_DOC" --argjson findings "$findings_json" \
    --argjson notes "$reviewer_notes" '
    . as $rows
    | $record
    | .findings = $findings
    | .catalogNotes = ((.catalogNotes // []) + $notes)
    | .checks = ((.checks | map(. as $c | select(([ $rows[] | .id ] | index($c.id)) == null))) + $rows)' "$rows_file")"
  rm -f "$rows_file"
  [ -n "$updated" ] || die 3 "findings: could not update the record with what the reviewer found."

  # A survivor the reviewer read as a finding is a test nothing can fail, so check 4 reads unmet
  # however its own script half answered. The lens is one more reading of the same check, never a
  # check of its own.
  local mutation_hits
  mutation_hits="$(printf '%s' "$findings_json" | jq -c '[ .[] | select(.lens == "mutation") ]')"
  if [ "$(printf '%s' "$mutation_hits" | jq 'length')" -gt 0 ]; then
    updated="$(printf '%s' "$updated" | jq -c --argjson hits "$mutation_hits" '
      .checks = (.checks | map(if .id == "test-and-mutation"
        then (.verdict = "unmet"
              | .detail = (.detail + " The mutation lens raised "
                           + ($hits | length | tostring) + " finding(s) on surviving mutants: "
                           + ([ $hits[] | (.id + " cites " + (if .linkedTo == "" then "nothing" else .linkedTo end)) ] | join(", ")) + "."))
        else . end))')"
  fi

  rw_write_record "findings" "$updated"
  rw_print_summary "$updated" "findings"
  printf 'findingsRead: %s\n' "$findings_path"
  local follow_up high_security
  follow_up="$(printf '%s' "$findings_json" | jq -r '[ .[] | select(.disposition == "follow-up") | .id ] | join(", ")')"
  high_security="$(printf '%s' "$findings_json" | jq -r '[ .[] | select(.disposition == "follow-up" and .severity == "high") | .id ] | join(", ")')"
  [ -z "$follow_up" ] \
    || echo "FINDINGS: these findings cite neither a criterion nor a non-goal and are recorded as follow-up work nobody has a task for: $follow_up" >&2
  [ -z "$high_security" ] \
    || echo "FINDINGS: these follow-up findings are high severity and go to the person now, because leaving one queued ships it: $high_security" >&2
  exit 0
}

# ------------------------------------------------------------------------------------------------
# `surfaces`: checks 13 to 15, the registry, and the person's walk.
# ------------------------------------------------------------------------------------------------

# The surface rows the review recipe declares, across every framework the record resolved one for,
# each tagged with its framework. One surface row may carry a command from one framework only, the
# same rule cr_resolve applies to a tool row and the same refusal (exit 72), because nothing here
# may choose between two answers to one question. Sets RW_SURFACE_ROWS and RW_SURFACE_BLOCK_STATE.
RW_SURFACE_ROWS="[]"; RW_SURFACE_BLOCK_STATE="undeclared"
rw_load_surface_rows() {
  local who="$1" count i fw recipe_file rows_file all one_id commanded
  RW_SURFACE_ROWS='[]'; RW_SURFACE_BLOCK_STATE="undeclared"
  count="$(printf '%s' "$RW_RECORD_DOC" | jq '(.recipes // []) | length')"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  rows_file="$(mktemp)" || die 3 "$who: could not create a temporary file"
  i=0; fw=""; recipe_file=""
  while [ "$i" -lt "$count" ]; do
    fw="$(printf '%s' "$RW_RECORD_DOC" | jq -r --argjson i "$i" '.recipes[$i].framework')"
    recipe_file="$(printf '%s' "$RW_RECORD_DOC" | jq -r --argjson i "$i" '.recipes[$i].checkRecipe')"
    if [ -n "$recipe_file" ] && [ -f "$recipe_file" ]; then
      : >"$rows_file.one"
      cc_parse_recipe "$recipe_file" "Surface commands" "surface_commands" "$rows_file.one"
      [ "$RECIPE_STATE" = "undeclared" ] || RW_SURFACE_BLOCK_STATE="$RECIPE_STATE"
      jq -c --arg fw "$fw" '. + {framework: $fw}' "$rows_file.one" >>"$rows_file" 2>/dev/null
      rm -f "$rows_file.one"
    fi
    i=$((i + 1))
  done
  all="$(jq -s '.' "$rows_file" 2>/dev/null)" || all='[]'
  rm -f "$rows_file"
  one_id=""
  while IFS= read -r one_id; do
    [ -n "$one_id" ] || continue
    commanded="$(printf '%s' "$all" | jq -c --arg id "$one_id" \
      '[ .[] | select(.id == $id and (has("argv")) and (((.unreadable // []) | index("argv")) == null)) ]')"
    if [ "$(printf '%s' "$commanded" | jq 'length')" -gt 1 ]; then
      die 72 "$who: $(printf '%s' "$commanded" | jq -r '[ .[].framework ] | join(" and ")') each declare a $one_id surface command, and nothing here may choose between two answers to one question. Resolve one review recipe for this task, or split the frameworks into two tasks."
    fi
    i=0
  done <<RW_SURFACE_IDS
$(printf '%s' "$all" | jq -r '[ .[].id ] | unique | .[]')
RW_SURFACE_IDS
  RW_SURFACE_ROWS="$all"
}

# The registry's surfaces, as a JSON array of {id, gates}. The registry is a YAML file whose
# version 6 producer does not exist yet, so this reads the shape version 5 writes: a `surfaces:`
# list of `- id:` rows, each with a `gates:` list. A file it cannot read that way yields an empty
# list, and the caller records unknown with the reason rather than reading an unreadable registry as
# a project with no surfaces. Sets RW_REGISTRY_SURFACES and RW_REGISTRY_STATE.
RW_REGISTRY_SURFACES="[]"; RW_REGISTRY_STATE="absent"
rw_load_registry() {
  local registry_file="$1" block line trimmed current gates out
  RW_REGISTRY_SURFACES='[]'; RW_REGISTRY_STATE="absent"
  [ -n "$registry_file" ] || return 0
  if [ ! -f "$registry_file" ]; then
    RW_REGISTRY_STATE="missing"
    return 0
  fi
  block="$(sed -n '/^surfaces:/,$p' "$registry_file" 2>/dev/null | sed '1d')"
  if [ -z "$block" ]; then
    RW_REGISTRY_STATE="unreadable"
    return 0
  fi
  RW_REGISTRY_STATE="ok"
  out='[]'; current=""; gates='[]'
  while IFS= read -r line; do
    trimmed="$(pc_trim "$line")"
    case "$trimmed" in
      '- id:'*)
        if [ -n "$current" ]; then
          out="$(jq -nc --argjson have "$out" --arg id "$current" --argjson gates "$gates" \
            '$have + [{id: $id, gates: $gates}]')"
        fi
        current="$(pc_trim "${trimmed#- id:}")"
        gates='[]'
        ;;
      'gates:'*)
        gates="$(printf '%s' "$(pc_trim "${trimmed#gates:}")" \
          | jq -Rc 'gsub("[\\[\\]]"; "") | split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0))' 2>/dev/null)"
        [ -n "$gates" ] || gates='[]'
        ;;
    esac
  done <<RW_REGISTRY
$block
RW_REGISTRY
  if [ -n "$current" ]; then
    out="$(jq -nc --argjson have "$out" --arg id "$current" --argjson gates "$gates" \
      '$have + [{id: $id, gates: $gates}]')"
  fi
  RW_REGISTRY_SURFACES="$out"
}

# One kind of surface: its row, its run, its registry surfaces and the walk. $1 the check id, $2 the
# surface row id in the recipe, $3 the registry gate word, $4 whether the project has this kind on,
# $5 the walked list, $6 the accepted list. Appends the check row to $7 and the surface rows to $8.
rw_surface_kind() {
  local check_id="$1" row_id="$2" gate="$3" enabled="$4" walked="$5" accepted="$6"
  local checks_out="$7" surfaces_out="$8"
  local row rc output mine count i sid verdict rows
  local ran row_verdict detail worst missing_walk accept_here accept_row

  mine="$(printf '%s' "$RW_REGISTRY_SURFACES" | jq -c --arg g "$gate" \
    '[ .[] | select((.gates // []) | index($g)) ]')"
  count="$(printf '%s' "$mine" | jq 'length')"
  row="$(printf '%s' "$RW_SURFACE_ROWS" | jq -c --arg id "$row_id" '[ .[] | select(.id == $id) ][0] // null')"

  if [ "$enabled" = "unavailable" ]; then
    # Visual parity has no recipe row, no project field to switch it on and no harness, so version 6
    # records it as unavailable rather than reporting a check that passed. A recipe that does command
    # the row reaches the ordinary path below instead.
    rw_check_row "$check_id" "undeclared" "visual parity has no recipe row, no project field and no harness in version 6, so nothing ran and nothing is claimed. It is recorded as unavailable." >>"$checks_out"
    return 0
  fi
  if [ "$enabled" != "on" ]; then
    rw_check_row "$check_id" "undeclared" "the project record says $gate is $enabled, so review ran nothing for it. Review runs nothing that is off." >>"$checks_out"
    return 0
  fi
  if [ "$RW_SURFACE_BLOCK_STATE" = "unparseable" ]; then
    # The heading is there and the key never opens under it. Nobody looked, rather than a framework
    # that declared nothing, so the word is unknown and it fails the review.
    rw_check_row "$check_id" "unknown" "the surface commands block in the review recipe could not be read: the heading is there and its key never opens under it. Nothing ran, and nothing here can tell what the recipe meant to declare." >>"$checks_out"
    return 0
  fi
  if [ "$RW_SURFACE_BLOCK_STATE" != "ok" ] || [ "$row" = "null" ]; then
    rw_check_row "$check_id" "undeclared" "the review recipe declares no $row_id surface row (the surface commands block reads $RW_SURFACE_BLOCK_STATE), so there is no command to run. Every command waits for the recipe." >>"$checks_out"
    return 0
  fi
  if [ "$(printf '%s' "$row" | jq -r '.absent // false')" = "true" ]; then
    rw_check_row "$check_id" "undeclared" "$(printf '%s' "$row" | jq -r '.absentReason // "the recipe declares this surface row absent"')" "" "" "$(printf '%s' "$row" | jq -r '.framework // ""')" "absent" >>"$checks_out"
    return 0
  fi
  if [ "$RW_REGISTRY_STATE" != "ok" ]; then
    rw_check_row "$check_id" "unknown" "the recipe commands a $row_id run and the registry is $RW_REGISTRY_STATE, so nobody could say which surfaces to answer about." >>"$checks_out"
    return 0
  fi
  if [ "$count" -eq 0 ]; then
    rw_check_row "$check_id" "undeclared" "the registry holds no surface carrying the $gate gate, so this project has nothing for this check to run." >>"$checks_out"
    return 0
  fi

  # A person accepted a new baseline for one of this kind's own surfaces, so the row that writes one
  # runs. The accept row is a second id, never a new key, which is what the recipe ask declares. A
  # kind with no accept row declared does nothing here, and the caller refuses for the surface.
  accept_here=""
  i=0
  while [ "$i" -lt "$count" ]; do
    sid="$(printf '%s' "$mine" | jq -r --argjson i "$i" '.[$i].id')"
    case " $accepted " in *" $sid "*) accept_here="$accept_here $sid" ;; esac
    i=$((i + 1))
  done
  if [ -n "$accept_here" ]; then
    accept_row="$(printf '%s' "$RW_SURFACE_ROWS" | jq -c --arg id "$row_id-accept" \
      '[ .[] | select(.id == $id and (has("argv")) and ((.absent // false) == false)) ][0] // null')"
    if [ "$accept_row" != "null" ]; then
      RW_ACCEPTED_ROWS="$RW_ACCEPTED_ROWS $row_id-accept"
      rw_surface_row_check "$accept_row" "$row_id-accept" "ran over the surfaces a person accepted,${accept_here}," >>"$checks_out"
      if [ -z "$RW_RUN_VERDICT" ] && [ "$RW_RUN_RC" = "0" ]; then
        RW_ACCEPTED_DONE="$RW_ACCEPTED_DONE$accept_here"
      fi
    fi
  fi

  # {paths} expands to nothing here on purpose: version 6 runs every registered surface, which is
  # why the change-impact globs stay unparsed, so a row ending in {paths} runs the whole set.
  rw_run_row "$(printf '%s' "$row" | jq -c '.argv')" '[]' "" ""
  rw_run_fault "$row_id" "the review recipe for $(printf '%s' "$row" | jq -r '.framework // "this project"')"
  output="$RW_RUN_OUTPUT"
  ran=false; rc=""; row_verdict="$RW_RUN_VERDICT"; detail="$RW_RUN_DETAIL"
  if [ -z "$row_verdict" ]; then
    ran=true
    rc="$RW_RUN_RC"
    if [ "$rc" = "0" ]; then
      row_verdict="met"
      detail="the $row_id command exited 0."
    else
      row_verdict="unmet"
      detail="the $row_id command exited $rc."
    fi
  fi

  # One row per registered surface of this kind, in one pass. A surface the run said nothing about
  # reads unmet rather than borrowing the run's own verdict: a gate that cannot notice its subject
  # going absent cannot inform.
  rows="$(jq -nc --argjson mine "$mine" --arg out "$output" --arg v "$row_verdict" \
    --argjson ran "$ran" --arg walked " $walked " --arg accepted " $RW_ACCEPTED_DONE " '
    [ $mine[] | .id as $sid
      | {id: $sid,
         verdict: (if $ran and (($out | contains($sid)) | not) then "unmet" else $v end),
         ran: $ran,
         walked: ($walked | contains(" " + $sid + " ")),
         reportPath: ""}
        + (if ($accepted | contains(" " + $sid + " ")) then {baselineAccepted: true} else {} end) ]')"
  printf '%s' "$rows" | jq -c '.[]' >>"$surfaces_out"
  worst=""
  while IFS= read -r verdict; do
    [ -n "$verdict" ] || continue
    worst="$(rw_worse "$worst" "$verdict")"
  done <<RW_SURFACE_KIND
$(printf '%s' "$rows" | jq -r '.[].verdict')
RW_SURFACE_KIND
  missing_walk="$(printf '%s' "$rows" | jq -r '[ .[] | select(.walked | not) | .id ] | join(", ")')"
  rw_run_done

  if [ -n "$missing_walk" ]; then
    worst="$(rw_worse "$worst" "unknown")"
    detail="$detail Nobody walked these surfaces, and the walk is half the answer: $missing_walk"
  fi
  rw_check_row "$check_id" "$worst" "$detail" "$rc" "$output" "$(printf '%s' "$row" | jq -r '.framework // ""')" >>"$checks_out"
}

# Runs one surface row and prints its check row: the wording rw_run_fault gives a run that decided
# nothing, met on exit 0, unmet on anything else. $1 the row, $2 the id to record it under, $3 what
# the detail says the row did. The caller reads RW_RUN_VERDICT and RW_RUN_RC afterwards when it needs
# to know whether the command really ran.
rw_surface_row_check() {
  local one="$1" id="$2" did="$3" fw
  fw="$(printf '%s' "$one" | jq -r '.framework // ""')"
  rw_run_row "$(printf '%s' "$one" | jq -c '.argv // []')" '[]' "" ""
  rw_run_fault "$id" "the review recipe for ${fw:-this project}"
  if [ -n "$RW_RUN_VERDICT" ]; then
    rw_check_row "$id" "$RW_RUN_VERDICT" "$RW_RUN_DETAIL" "" "" "$fw"
  elif [ "$RW_RUN_RC" = "0" ]; then
    rw_check_row "$id" "met" "the $id command $did and exited 0." "$RW_RUN_RC" "$RW_RUN_OUTPUT" "$fw"
  else
    rw_check_row "$id" "unmet" "the $id command $did and exited $RW_RUN_RC." "$RW_RUN_RC" "$RW_RUN_OUTPUT" "$fw"
  fi
  rw_run_done
}

# Every surface row the recipe declares that no kind above answered. The check commands block gets
# this treatment already: the ids are a floor and never the list, so a row a framework invents is run
# and recorded rather than dropped in silence. $1 the check rows file, $2 the ids already answered.
#
# An accept row is the one exception. It writes a new baseline, so it runs only when a person accepts
# one, and a row nobody asked for is recorded as not run rather than run unasked.
rw_surface_extra_rows() {
  local checks_out="$1" answered="$2" count i one row_id
  count="$(printf '%s' "$RW_SURFACE_ROWS" | jq 'length')"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  i=0; one=""; row_id=""
  while [ "$i" -lt "$count" ]; do
    one="$(printf '%s' "$RW_SURFACE_ROWS" | jq -c --argjson i "$i" '.[$i]')"
    row_id="$(printf '%s' "$one" | jq -r '.id')"
    i=$((i + 1))
    case " $answered " in *" $row_id "*) continue ;; esac
    case "$row_id" in
      *-accept)
        rw_check_row "$row_id" "undeclared" "this row writes a new baseline, so it runs only when a person accepts one. Nobody accepted one in this review, and it was not run." >>"$checks_out"
        continue ;;
    esac
    if [ "$(printf '%s' "$one" | jq -r '.absent // false')" = "true" ]; then
      rw_check_row "$row_id" "undeclared" "$(printf '%s' "$one" | jq -r '.absentReason // "the recipe declares this surface row absent"')" "" "" "$(printf '%s' "$one" | jq -r '.framework // ""')" "absent" >>"$checks_out"
      continue
    fi
    rw_surface_row_check "$one" "$row_id" "ran as the recipe declares it" >>"$checks_out"
  done
}

do_surfaces() {
  local task_arg="" walked="" accepted=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --walked)
        [ "$#" -ge 2 ] || die 3 "surfaces: --walked needs a surface id"
        looks_like_flag "$2" && die 3 "surfaces: --walked was given another flag, not a surface id: $2"
        walked="$walked $2"; shift 2 ;;
      --accept-baseline)
        [ "$#" -ge 2 ] || die 3 "surfaces: --accept-baseline needs a surface id"
        looks_like_flag "$2" && die 3 "surfaces: --accept-baseline was given another flag, not a surface id: $2"
        accepted="$accepted $2"; shift 2 ;;
      -*) die 3 "surfaces: unrecognized argument: $1" ;;
      *)
        [ -z "$task_arg" ] || die 3 "surfaces: more than one task folder given"
        task_arg="$1"; shift ;;
    esac
  done

  rw_paths "surfaces" "$task_arg"
  rw_require_finished "surfaces"
  rw_require_frozen "surfaces"
  rv_load_codepath "surfaces"
  rw_load_project "surfaces"
  rw_load_record "surfaces"
  rw_require_step "surfaces" "solid" "brief, then the reviewer, then findings"
  rw_refuse_moved_code "surfaces" "commit-only"

  [ -z "$(pc_trim "$accepted")" ] \
    || rw_require_person "surfaces" "--accept-baseline" "a person accepted a new baseline for a surface"
  [ -z "$(pc_trim "$walked")" ] \
    || rw_require_person "surfaces" "--walked" "a person looked at a surface at every viewport"

  RW_CATALOG_NOTES="$(printf '%s' "$RW_RECORD_DOC" | jq -c '.catalogNotes // []')"
  RW_ACCEPTED_DONE=""; RW_ACCEPTED_ROWS=""
  rw_load_surface_rows "surfaces"

  local e2e_on vr_on parity_on registry_path setup checks_file surfaces_file checks_json surfaces_json updated
  local one_accept all_rows si one_surface merged one_verdict
  e2e_on="$(printf '%s' "$RW_PROJECT_DOC" | jq -r 'if (.e2e // null) == null then "not set up" elif (.e2e.enabled // false) then "on" else "off" end')"
  vr_on="$(printf '%s' "$RW_PROJECT_DOC" | jq -r 'if (.visualRegression // null) == null then "not set up" elif (.visualRegression.enabled // false) then "on" else "off" end')"
  registry_path="$(printf '%s' "$RW_PROJECT_DOC" | jq -r '.visualRegression.registryPath // ""')"
  rw_load_registry "$registry_path"

  # The offer, which the skill makes and this action only records what it can decide. Rows that are
  # not absent are how review knows the framework has surfaces at all.
  if [ "$RW_REGISTRY_STATE" = "ok" ]; then
    setup="registered"
  elif [ "$(printf '%s' "$RW_SURFACE_ROWS" | jq '[ .[] | select((.absent // false) == false) ] | length')" -gt 0 ]; then
    if [ "$RW_RUN_MODE" = "autonomous" ]; then setup="not-offered-autonomous"; else setup="available"; fi
  else
    setup="not-applicable"
  fi

  checks_file="$(mktemp)" || die 3 "surfaces: could not create a temporary file"
  surfaces_file="$(mktemp)" || die 3 "surfaces: could not create a temporary file"
  # Visual parity has no project field, so the recipe is the only thing that can say whether it runs:
  # a commanded row reaches the ordinary path, and anything else reads unavailable.
  parity_on="unavailable"
  [ "$(printf '%s' "$RW_SURFACE_ROWS" | jq --arg id "visual-parity" '[ .[] | select(.id == $id and (has("argv")) and ((.absent // false) == false)) ] | length')" -gt 0 ] \
    && parity_on="on"
  rw_surface_kind "$CHECK_E2E" "e2e" "e2e" "$e2e_on" "$walked" "$accepted" "$checks_file" "$surfaces_file"
  rw_surface_kind "$CHECK_VR" "visual-regression" "visual_regression" "$vr_on" "$walked" "$accepted" "$checks_file" "$surfaces_file"
  rw_surface_kind "$CHECK_PARITY" "visual-parity" "visual_parity" "$parity_on" "$walked" "$accepted" "$checks_file" "$surfaces_file"
  rw_surface_extra_rows "$checks_file" "e2e visual-regression visual-parity$RW_ACCEPTED_ROWS"

  # A person accepted a baseline for a surface whose kinds declare no accept row. Recording a boolean
  # and writing nothing would say a baseline was replaced when none was.
  while IFS= read -r one_accept; do
    [ -n "$one_accept" ] || continue
    case " $RW_ACCEPTED_DONE " in
      *" $one_accept "*) ;;
      *) die 3 "surfaces: --accept-baseline named $one_accept, and no surface row the review recipe declares writes a baseline for the gates that surface carries. The recipe needs a row whose id is the kind's own id with -accept after it. Nothing was written." ;;
    esac
  done <<RW_ACCEPTED_IN
$(printf '%s' "$accepted" | tr ' ' '\n')
RW_ACCEPTED_IN

  checks_json="$(jq -s '.' "$checks_file")" || die 3 "surfaces: could not assemble the check rows"
  # One row per surface, not one per gate. A surface carrying two gates is answered once per gate
  # above, and the walk is per surface rather than per gate: a person looks at the page once, at every
  # viewport. So the answers merge, keeping the worse verdict, and the worse of two verdicts is
  # br_worst_verdict's to decide rather than a second ranking of the four words written here.
  all_rows="$(jq -s -c '[ group_by(.id)[] | {id: .[0].id, rows: .} ]' "$surfaces_file")" \
    || die 3 "surfaces: could not assemble the surface rows"
  surfaces_json='[]'
  si=0; one_surface=""; merged=""
  while [ "$si" -lt "$(printf '%s' "$all_rows" | jq 'length')" ]; do
    one_surface="$(printf '%s' "$all_rows" | jq -c --argjson i "$si" '.[$i]')"
    merged=""
    while IFS= read -r one_verdict; do
      [ -n "$one_verdict" ] || continue
      merged="$(rw_worse "$merged" "$one_verdict")"
    done <<RW_SURFACE_VERDICTS
$(printf '%s' "$one_surface" | jq -r '.rows[].verdict')
RW_SURFACE_VERDICTS
    surfaces_json="$(jq -nc --argjson have "$surfaces_json" --argjson g "$one_surface" \
      --arg verdict "$merged" '
      $have + [ {id: $g.id, verdict: $verdict,
                 ran: ([ $g.rows[].ran ] | any),
                 walked: ([ $g.rows[].walked ] | all),
                 reportPath: ([ $g.rows[].reportPath ] | map(select(. != "")) | (.[0] // ""))}
                + (if ([ $g.rows[] | (.baselineAccepted // false) ] | any) then {baselineAccepted: true} else {} end) ]')"
    si=$((si + 1))
  done
  rm -f "$checks_file" "$surfaces_file"

  updated="$(jq -n --argjson record "$RW_RECORD_DOC" --argjson rows "$checks_json" \
    --argjson surfaces "$surfaces_json" --arg setup "$setup" --argjson notes "$RW_CATALOG_NOTES" '
    $record
    | .checks = ((.checks | map(. as $c | select(([ $rows[] | .id ] | index($c.id)) == null))) + $rows)
    | .surfaces = $surfaces
    | .surfaceSetup = $setup
    | .catalogNotes = $notes')"
  [ -n "$updated" ] || die 3 "surfaces: could not update the record with the surface rows."
  rw_write_record "surfaces" "$updated"
  rw_print_summary "$updated" "surfaces"
  printf 'registry: %s\n' "${registry_path:-none} ($RW_REGISTRY_STATE)"
  echo "SURFACES: end to end is $e2e_on, visual regression is $vr_on, the registry is $RW_REGISTRY_STATE${registry_path:+ at $registry_path}, and the surface commands block reads $RW_SURFACE_BLOCK_STATE." >&2
  case "$setup" in
    available)              echo "SURFACES: this framework's recipe carries surface rows and this project has no registry. The setup offer belongs here, once." >&2 ;;
    not-offered-autonomous) echo "SURFACES: this framework's recipe carries surface rows and this project has no registry. Nobody is present, so the offer was not made." >&2 ;;
  esac
  exit 0
}

# ------------------------------------------------------------------------------------------------
# `close`: check 1, the criterion verdicts, the contract write and the verdict.
# ------------------------------------------------------------------------------------------------

do_close() {
  local task_arg="" rows="" arg cid value
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --row)
        [ "$#" -ge 2 ] || die 3 "close: --row needs <criterion>=met|unmet"
        case "$2" in *=*) ;; *) die 3 "close: --row takes <criterion>=met|unmet, got: $2" ;; esac
        cid="${2%%=*}"; value="${2#*=}"
        [ -n "$cid" ] || die 3 "close: --row was given no criterion id: $2"
        case "$value" in
          met|unmet) ;;
          *) die 3 "close: --row takes met or unmet, not: $value. A row nobody could answer is left out, and it reads unanswered." ;;
        esac
        rows="$rows$(printf '%s\t%s' "$cid" "$value")
"
        shift 2 ;;
      -*) die 3 "close: unrecognized argument: $1" ;;
      *)
        [ -z "$task_arg" ] || die 3 "close: more than one task folder given"
        task_arg="$1"; shift ;;
    esac
  done

  rw_paths "close" "$task_arg"
  rw_require_finished "close"
  rw_require_frozen "close"
  rv_load_codepath "close"
  rw_load_record "close"
  rw_require_step "close" "$CHECK_E2E" "surfaces"
  rw_refuse_moved_code "close" "commit-only"
  [ -z "$rows" ] || rw_require_person "close" "--row" "a person read a checklist row and judged it"

  local alignment criteria count i one kind state verdict answered suite_verdict suite_output
  local hit rows_out criteria_json bad_rows unanswered=0 unmet_count=0
  alignment="$(rw_alignment)"
  criteria="$(printf '%s' "$alignment" | jq -c '.criteria // []')"
  count="$(printf '%s' "$criteria" | jq 'length')"
  suite_verdict="$(printf '%s' "$RW_RECORD_DOC" | jq -r '[ (.checks // [])[] | select(.id == "suite") ][0].verdict // "unknown"')"
  suite_output="$(printf '%s' "$RW_RECORD_DOC" | jq -r '[ (.checks // [])[] | select(.id == "suite") ][0].output // ""')"
  rw_load_test_rows "close"

  rows_out="$(mktemp)" || die 3 "close: could not create a temporary file"
  i=0; cid=""; kind=""; state=""; verdict=""; answered=""; hit="false"
  while [ "$i" -lt "$count" ]; do
    cid="$(printf '%s' "$criteria" | jq -r --argjson i "$i" '.[$i].id')"
    kind="$(printf '%s' "$criteria" | jq -r --argjson i "$i" '.[$i].verifiedBy')"
    verdict=""; answered="nobody"
    if [ "$kind" = "person" ]; then
      verdict="$(cr_lookup "$rows" "$cid")"
      if [ -n "$verdict" ]; then
        answered="person"
      else
        verdict="unanswered"
      fi
    else
      answered="script"
      state="$(printf '%s' "$RW_FINISHED_DOC" | jq -r --arg id "$cid" \
        '[ (.criteria // [])[] | select(.id == $id) ][0].rowState // ""')"
      # Check 1 joins on the test name: implementation puts the criterion id at the end of each
      # test's name, delimited, so this compares strings and never re-derives the join. One question
      # per criterion: does the suite output name any test this criterion froze.
      hit="$(jq -nr --argjson rows "$RW_TEST_ROWS" --arg id "$cid" --arg out "$suite_output" '
        [ $rows[] | select(.criterion == $id) | (.tests // [])[] | .name
          | select($out | contains(.)) ] | length > 0')"
      case "$suite_verdict" in
        met)
          case "$state" in
            confirmed) verdict="met" ;;
            rejected)  verdict="unmet" ;;
            *)         verdict="unanswered" ;;
          esac
          ;;
        unmet)
          if [ "$hit" = "true" ]; then verdict="unmet"; else verdict="unanswered"; fi
          ;;
        *) verdict="unanswered" ;;
      esac
    fi
    case "$verdict" in
      unanswered) unanswered=$((unanswered + 1)) ;;
      unmet)      unmet_count=$((unmet_count + 1)) ;;
    esac
    jq -nc --arg id "$cid" --arg verifiedBy "$kind" --arg verdict "$verdict" --arg answeredBy "$answered" \
      '{id: $id, verifiedBy: $verifiedBy, verdict: $verdict, answeredBy: $answeredBy}' >>"$rows_out"
    i=$((i + 1))
  done
  criteria_json="$(jq -s '.' "$rows_out")" || die 3 "close: could not assemble the criterion rows"
  rm -f "$rows_out"

  # A --row for a criterion the contract does not hold, or one a machine verifies, is a caller
  # answering a question nobody asked. Every id is checked in one question rather than one per row.
  bad_rows="$(jq -Rrn --argjson c "$criteria" --rawfile given /dev/stdin '
    [ ($given | split("\n"))[] | split("\t")[0] | select(length > 0)
      | . as $id | select(([ $c[] | select(.id == $id and .verifiedBy == "person") ] | length) == 0) ]
    | unique | join(", ")' <<RW_ROWS
$rows
RW_ROWS
)"
  [ -z "$bad_rows" ] \
    || die 3 "close: --row named $bad_rows, and the frozen contract holds no person-verified criterion with that id. A machine-verified criterion is answered by the suite join, never by a flag."

  local check_one_verdict check_one_detail
  if [ "$unmet_count" -gt 0 ]; then
    check_one_verdict="unmet"
    check_one_detail="$unmet_count criterion row(s) read unmet, so the task is not done."
  elif [ "$unanswered" -gt 0 ]; then
    check_one_verdict="unknown"
    check_one_detail="$unanswered criterion row(s) read unanswered, and a criterion nobody could reach is never a pass."
  else
    check_one_verdict="met"
    check_one_detail="every criterion in the frozen contract reads met."
  fi

  rw_archive_closed_record "close"
  if [ -z "$RW_RECORD_DOC" ]; then
    # The archive moved the record this call was about to close a second time. Its rows are what
    # this verdict was computed from, so it is read back from the archive rather than lost.
    die 63 "close: the record was archived and there is nothing left to write to. Run checks again to start a fresh pass."
  fi

  local updated verdict_word failing
  updated="$(jq -n --argjson record "$RW_RECORD_DOC" --argjson criteria "$criteria_json" \
    --argjson one "$(rw_check_row "$CHECK_EVERY_CRITERION" "$check_one_verdict" "$check_one_detail")" '
    $record
    | .criteria = $criteria
    | .checks = ([$one] + (.checks | map(select(.id != "every-criterion"))))')"
  [ -n "$updated" ] || die 3 "close: could not update the record with the criterion rows."

  # The verdict rules. A check reading unmet fails, a check reading unknown fails, met and
  # undeclared both pass, and a criterion reading unmet or unanswered means no sign off whatever the
  # checks said.
  failing="$(printf '%s' "$updated" | jq -r '
    ([ (.checks // [])[] | select(.verdict == "unmet" or .verdict == "unknown") | (.id + " reads " + .verdict) ]
     + [ (.criteria // [])[] | select(.verdict == "unmet" or .verdict == "unanswered") | (.id + " reads " + .verdict) ])
    | join("; ")')"
  if [ -n "$failing" ]; then verdict_word="failed"; else verdict_word="passed"; fi
  updated="$(printf '%s' "$updated" | jq -c --arg v "$verdict_word" '.verdict = $v')"
  rw_write_record "close" "$updated"

  # The one field review writes into the contract. The hash covers the whole file, so the next
  # `start` reports the contract as changed; that drift is review's own, and the report says so.
  local live_state written missing_ids new_alignment
  written=0; missing_ids=""
  live_state="$(json_file_state "$ALIGNMENT_FILE")"
  if [ "$live_state" = "ok" ]; then
    new_alignment="$(jq -c --argjson rows "$criteria_json" '
      .criteria = [ (.criteria // [])[] | . as $c
        | ([ $rows[] | select(.id == $c.id) ][0]) as $row
        | if $row == null then $c else ($c | .verdict = $row.verdict) end ]' "$ALIGNMENT_FILE")"
    if [ -n "$new_alignment" ]; then
      write_atomic "$ALIGNMENT_FILE" "$new_alignment"
      written="$(printf '%s' "$new_alignment" | jq '[ (.criteria // [])[] ] | length')"
    fi
    missing_ids="$(jq -nr --argjson rows "$criteria_json" --slurpfile live "$ALIGNMENT_FILE" '
      [ $rows[] | . as $r | select(((($live[0].criteria // []) | map(.id)) | index($r.id)) == null) | .id ] | join(", ")')"
  fi

  rw_print_summary "$updated" "close"
  printf 'contract: %s\n' "$ALIGNMENT_FILE"
  local undeclared_list unknown_list note_count
  undeclared_list="$(printf '%s' "$updated" | jq -r '[ (.checks // [])[] | select(.verdict == "undeclared") | .id ] | join(", ")')"
  unknown_list="$(printf '%s' "$updated" | jq -r '[ (.checks // [])[] | select(.verdict == "unknown") | .id ] | join(", ")')"
  note_count="$(printf '%s' "$updated" | jq '(.catalogNotes // []) | length')"
  echo "CLOSE: the review $verdict_word. ${failing:+What caused it: $failing.} Checks nothing declared: ${undeclared_list:-none}. Checks nobody could read: ${unknown_list:-none}. Criteria reading unanswered: $unanswered. Catalog notes: $note_count." >&2
  case "$live_state" in
    ok) echo "CLOSE: review wrote one verdict per criterion into $ALIGNMENT_FILE, across $written criteria. That write moves the contract hash, so the next start reports the contract as changed; the drift is review's own and it halts no order.${missing_ids:+ These criteria are in the frozen contract and not in the live one, so nothing was written for them: $missing_ids.}" >&2 ;;
    *)  echo "CLOSE: $ALIGNMENT_FILE is $live_state, so no criterion verdict was written into the contract. The record holds them." >&2 ;;
  esac
  exit 0
}

# ------------------------------------------------------------------------------------------------
# `step`: print one step file.
# ------------------------------------------------------------------------------------------------

do_step() {
  local names
  names="$(md_basenames_in "$STEPS_DIR")"
  [ "$#" -ge 1 ] || die 3 "step: a step name is required. The steps are: $names"
  [ "$#" -le 1 ] || die 3 "step: unrecognized extra argument: $2"
  case "$1" in
    */*|.|..|'') die 3 "step: a step name is one name and never a path; got: $1. The steps are: $names" ;;
  esac
  [ -f "$STEPS_DIR/$1.md" ] \
    || die 3 "step: this skill ships no step file named $1. The steps are: $names"
  cat "$STEPS_DIR/$1.md" || die 3 "step: $STEPS_DIR/$1.md could not be read."
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
[ -n "$ACTION" ] || { usage; die 3 "no action given"; }
shift

case "$ACTION" in
  read)     do_read     "$@" ;;
  checks)   do_checks   "$@" ;;
  brief)    do_brief    "$@" ;;
  findings) do_findings  "$@" ;;
  surfaces) do_surfaces "$@" ;;
  close)    do_close    "$@" ;;
  step)     do_step     "$@" ;;
  *) usage; die 3 "unknown action: $ACTION" ;;
esac
