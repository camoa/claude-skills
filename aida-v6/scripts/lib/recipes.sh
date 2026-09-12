#!/usr/bin/env bash
# recipes.sh: the recipe blocks, the commands they declare, and the repository facts every stage
# that runs one of those commands needs first.
#
# Two stages run a command a process recipe declares: implementation, per work order, and review,
# over the whole task. Every function here was written once inside
# skills/implement/scripts/implement-actions.sh and is moved here unchanged, so the two stages
# share one parser, one resolver, one command runner, one clean-tree refusal and one code-path
# loader. A second copy of any of them is the duplication this rewrite removes
# (ideal/review.md, "How this part gets built").
#
# Two changes came with the move, and nothing else changed:
#   * cc_parse_recipe takes its heading and its key as arguments, the way recipe_block_into
#     already does, so review can read a `## Surface commands` block with the same parser.
#   * cr_resolve reads CR_TOOL_IDS_ALL. False, its own default, keeps implementation's three tool
#     rows. True resolves every row id the recipes declare, which is what review needs: the check
#     commands block is a floor of three ids, never the list (ideal/review.md, "The recipe ask").
#
# Public functions, in the order they appear below:
#
#   resolve_project_folder <task folder>      the project folder two levels up, or returns 1
#   rv_load_codepath <action>                 sets RV_PROJECT_FOLDER and RV_CODEPATH, or dies
#   project_code_path_state <project folder>  missing | unreadable | ok
#   project_code_path_value <project folder>  the codePath recorded there, or empty
#   is_git_repo <path>                        true when it is a git work tree
#   pc_trim <text>                            the text with leading and trailing space removed
#   pc_output_holds <file> <needle>           true when the file holds that literal text
#   tc_indent <line>                          how many leading whitespace characters it has
#   recipe_block_into <recipe> <heading> <key> <file>   cuts one YAML block out; prints the state
#   tc_parse_recipe <recipe> <out>            one JSON object per `## Test commands` row
#   cc_parse_recipe <recipe> <heading> <key> <out>      the same for a check or surface block
#   cc_silent_pass_markers <recipe>           the literal markers of a run that selected nothing
#   cr_recipe_pair <action> <flag> <value>    parses <framework>=<path> into CR_PAIR
#   cr_resolve                                resolves the recipes into CR_DOC
#   cr_lookup <tab list> <name>               the value that name was given, as whole text
#   cr_row_command <rows> <row id> <label>    one row's argv, or why there is none
#   cr_require_baseline_recipes <action> <baseline file>  exit 73 on a changed check recipe
#   tf_sha256_of <file>                       the sha256 of that file, lowercase hex
#   tf_path_matches_glob <path> <glob>        one segment against one glob segment
#   tf_path_matches_catalog_glob <path> <glob>  a whole path against a catalog glob
#   br_run_resolved <argv> <dir> <out> <paths> <values> [<err>]   runs one resolved command
#   br_filter_extensions <paths> <extensions>  the paths a row's own extensions list keeps
#   br_require_clean_tree <action> <repo> [<unit> <run mode> <ledger file> <ledger doc>]  exit 61
#   br_worst_verdict <verdicts>               the verdict that wins across several frameworks
#   pc_refuse_forged_value <action> <pair>    exit 3 on a --value carrying a tab or a newline
#   rv_is_finding_id <id>                     true for `f` and then digits, no leading zero
#   rv_refuse_duplicate_keys <file> <action>  exit 52 on a JSON file naming one key twice
#   rv_read_findings_array <file> <key> <action>  sets RV_FINDINGS_ARRAY, or exits 52
#
# What this library takes from its caller, and never defines itself:
#
#   die <exit code> <message>   the one refusal function, with the caller's own script name in the
#                               message. Every exit code used below keeps the meaning
#                               implement-actions.sh's own table gives it, so one number never
#                               means two things in two scripts: 3 could not do its job, 5 the
#                               codePath is not a git repository, 14 project.json will not parse,
#                               15 the codePath is not on disk, 61 the working tree is dirty, 72
#                               two frameworks each command one tool, 73 the check recipe is not
#                               the one the baseline was taken with, and 52 a findings file that
#                               cannot be read as a findings file.
#   write_atomic, halt_order_in  read by br_require_clean_tree only on the branch an autonomous
#                               caller asks for by passing its ledger. A caller that passes no
#                               ledger never reaches them.
#   scripts/lib/records-hash.sh  sourced by the caller before this file: cr_resolve and
#                               tf_sha256_of both run RECORDS_HASH_SHA256_CMD, and one place
#                               decides which of sha256sum or `shasum -a 256` exists.
#   IMPL_DIR, TASK_PATH          rv_load_codepath reads TASK_PATH. It is declared below so a
#                               caller under `set -u` never reads it unset.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, and the five
# zsh traps implement-actions.sh's own header lists hold here too: never a variable named `path` or
# `fpath`, no reliance on word splitting an unquoted expansion, no variable used as a case pattern
# without GLOB_SUBST scoped to a subshell, no `local a b="$a"` statement, and no `local` inside a
# loop body.
#
# This file is a library. Source it; do not run it.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file) : ;;
    *)
      printf 'recipes.sh: this is a library, meant to be sourced, not run directly.\n' >&2
      exit 1
      ;;
  esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'recipes.sh: this is a library, meant to be sourced, not run directly.\n' >&2
  exit 1
fi

# ------------------------------------------------------------------------------------------------
# The task's project, and the code repository it records.
# ------------------------------------------------------------------------------------------------

# Resolves the project folder for a task folder shaped <projectPath>/tasks/<task-id>, per
# task-actions.sh's own task_dir_for. Prints the project path and returns 0, or prints nothing and
# returns 1, when two folders up holds no project.json. Never dies: callers decide the failure's
# meaning, since `read` reports it and `start` refuses on it.
resolve_project_folder() {
  local task_path="$1" p
  p="$(cd "$task_path/../.." 2>/dev/null && pwd -P)" || return 1
  [ -f "$p/project.json" ] || return 1
  printf '%s' "$p"
}

# The task's own project, and the code repository it records. $1 the action's own name. Sets
# RV_PROJECT_FOLDER and RV_CODEPATH. Every action that needs either asks here, so all of them name
# the same facts in the same words: a project folder that cannot be resolved, a project.json that
# will not parse, one with no codePath, a codePath that is not on disk, and one that is not a git
# repository are five different refusals with five different exit codes.
TASK_PATH=""
RV_PROJECT_FOLDER=""; RV_CODEPATH=""
rv_load_codepath() {
  local who="$1"
  RV_PROJECT_FOLDER="$(resolve_project_folder "$TASK_PATH")" \
    || die 3 "$who: could not resolve a project folder two levels up from $TASK_PATH, or it has no project.json"
  case "$(project_code_path_state "$RV_PROJECT_FOLDER")" in
    unreadable) die 14 "$who: $RV_PROJECT_FOLDER/project.json exists but is not valid JSON, so its codePath cannot be read." ;;
    missing)    die 3 "$who: $RV_PROJECT_FOLDER/project.json not found, though it was found moments ago." ;;
  esac
  RV_CODEPATH="$(project_code_path_value "$RV_PROJECT_FOLDER")"
  [ -n "$RV_CODEPATH" ] || die 3 "$who: $RV_PROJECT_FOLDER/project.json is valid JSON but has no usable codePath field."
  [ -d "$RV_CODEPATH" ] || die 15 "$who: the recorded codePath does not exist on disk: $RV_CODEPATH"
  command -v git >/dev/null 2>&1 || die 3 "$who: git is required and was not found on PATH"
  is_git_repo "$RV_CODEPATH" \
    || die 5 "$who: this task's project code at $RV_CODEPATH is not a git repository."
}

# Prints one of: missing, unreadable, ok, for the project.json under $1. Never dies: a caller
# decides the meaning. "unreadable" means not valid JSON; a well-formed file with no codePath
# field is "ok" with an empty value from project_code_path_value, a different fact the caller
# checks next. Missing and unreadable are never folded into the same word here.
project_code_path_state() {
  local f="$1/project.json"
  [ -f "$f" ] || { printf 'missing'; return; }
  [ -r "$f" ] || { printf 'unreadable'; return; }
  jq empty "$f" 2>/dev/null || { printf 'unreadable'; return; }
  printf 'ok'
}

# The codePath recorded in a project.json already known to be valid JSON, or empty when the field
# is absent or blank. Never dies. Call only after project_code_path_state prints "ok".
project_code_path_value() {
  jq -r '.codePath // empty' "$1/project.json" 2>/dev/null
}

is_git_repo() {
  command -v git >/dev/null 2>&1 || return 1
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}


pc_trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }


# True when the file at $1 holds the literal string $2 anywhere in it. The needle is quoted inside
# the pattern, so nothing in it is read as a glob.
pc_output_holds() {
  local haystack
  haystack="$(cat "$1" 2>/dev/null)"
  case "$haystack" in
    *"$2"*) return 0 ;;
  esac
  return 1
}


# The count of leading whitespace characters in $1. Used only to tell a folded scalar's own
# continuation lines (indented further than the key that opened them) from the line that ends it
# (indented the same or less). A bracket-expression glob against a parameter expansion, never a
# regular expression, so it stays inside this file's own portability rule.
tc_indent() {
  local line="$1" lead
  lead="${line%%[^[:space:]]*}"
  printf '%s' "${#lead}"
}

# The state the two recipe parsers last read: undeclared, unparseable or ok. A global rather than a
# printed value, because a `$(...)` capture runs the parser in a subshell, and the refusal each one
# makes on a row it cannot record would exit that subshell alone and let the caller carry on with a
# tool recorded undeclared. That is the same rule br_seven_checks states, and both parsers were
# written the wrong way round.
RECIPE_STATE=""

# Cuts the YAML block a recipe writes under one H2 into the file $4, and prints the section own
# state: `undeclared` when the heading is absent, `unparseable` when the heading is there but the
# key never opens under it, or `ok`. $1 the recipe file, $2 the heading text, $3 the key.
#
# `## Test commands` and `## Check commands` are the same shape read the same way, and the three
# state words are the same three, so the cut lives here once rather than in each parser. Each
# parser then holds only its own per-line field dispatch, which is the half that really differs.
recipe_block_into() {
  local recipe_file="$1" heading="$2" key="$3" block_file="$4" section_file
  section_file="$block_file.section"
  sed -n "/^##[[:space:]]*$heading[[:space:]]*\$/,/^##[[:space:]]/p" "$recipe_file" >"$section_file" 2>/dev/null
  if [ ! -s "$section_file" ]; then
    rm -f "$section_file"
    printf 'undeclared'
    return 0
  fi
  if ! grep -q "^$key:" "$section_file"; then
    rm -f "$section_file"
    printf 'unparseable'
    return 0
  fi
  sed -n "/^$key:/,\$p" "$section_file" | sed '1d' >"$block_file"
  rm -f "$section_file"
  printf 'ok'
}

# The entry being read, held between lines, the same reason PC_* is held between lines above.
TC_ID=""; TC_ARGV_RAW=""; TC_COST=""; TC_ABSENT=0; TC_NEAREST_RAW=""

# Appends one JSON object to $1 for the held row and clears it, so a second call with nothing held
# writes nothing. `argv` and `nearest` are read as JSON, through jq, never split by hand; a value
# that is present but does not parse as an array of strings is not dropped, it is named in
# `unreadable`, because a malformed row in a recipe is a defect worth reporting, not a reason to
# report fewer rows than the recipe wrote. `absent` is a boolean fact, true whenever the row
# carried an `absent:` key at all; its own folded prose is never read here, only its presence.
tc_flush_entry() {
  local out="$1"
  [ -n "$TC_ID" ] || return 0
  local argv_json='null' cost="$TC_COST" nearest_json='null' unreadable='[]' parsed
  if [ -n "$TC_ARGV_RAW" ]; then
    parsed="$(printf '%s' "$TC_ARGV_RAW" | jq -e -c 'if (type == "array") and (all(.[]; type == "string")) then . else empty end' 2>/dev/null)"
    if [ -n "$parsed" ]; then
      argv_json="$parsed"
    else
      unreadable="$(printf '%s' "$unreadable" | jq -c '. + ["argv"]')"
    fi
  fi
  if [ -n "$TC_NEAREST_RAW" ]; then
    parsed="$(printf '%s' "$TC_NEAREST_RAW" | jq -e -c 'if (type == "array") and (all(.[]; type == "string")) then . else empty end' 2>/dev/null)"
    if [ -n "$parsed" ]; then
      nearest_json="$parsed"
    else
      unreadable="$(printf '%s' "$unreadable" | jq -c '. + ["nearest"]')"
    fi
  fi
  jq -n --arg id "$TC_ID" --argjson argv "$argv_json" --arg cost "$cost" \
        --argjson absent "$([ "$TC_ABSENT" = "1" ] && printf true || printf false)" \
        --argjson nearest "$nearest_json" --argjson unreadable "$unreadable" '
    {id: $id}
    + (if $argv       == null  then {} else {argv: $argv} end)
    + (if $cost       == ""    then {} else {cost: $cost} end)
    + (if $absent     == false then {} else {absent: true} end)
    + (if $nearest    == null  then {} else {nearest: $nearest} end)
    + (if ($unreadable | length) == 0 then {} else {unreadable: $unreadable} end)
  ' >>"$out" || die 3 "preconditions: could not record the test-command row $TC_ID"
  TC_ID=""; TC_ARGV_RAW=""; TC_COST=""; TC_ABSENT=0; TC_NEAREST_RAW=""
}

# Reads the `## Test commands` section of the recipe at $1, appending one JSON object per row to
# $2. Prints the section's own state: `undeclared` when the heading is absent (no key either,
# because there is nowhere for one to be), `unparseable` when the heading is there but
# `test_commands:` never opens under it (the same shape a misspelled key leaves), or `ok` when the
# key is there, however many rows it holds. Never runs a check and never substitutes a placeholder;
# this function only reads what the recipe wrote.
tc_parse_recipe() {
  local recipe_file="$1" out="$2"
  local block_file line trimmed indent skip_indent

  block_file="$out.tcblock"
  RECIPE_STATE="$(recipe_block_into "$recipe_file" "Test commands" "test_commands" "$block_file")"
  [ "$RECIPE_STATE" = "ok" ] || return 0

  TC_ID=""; TC_ARGV_RAW=""; TC_COST=""; TC_ABSENT=0; TC_NEAREST_RAW=""
  skip_indent=-1
  while IFS= read -r line; do
    trimmed="$(pc_trim "$line")"
    # A folded scalar (`trap:`, `id_form:`, or `absent:`'s own text) continues on every following
    # line indented further than the key that opened it. Those lines are prose for a person and a
    # model reading the recipe itself; they are skipped here, never parsed as a new field or a new
    # row. A blank line inside or around the block stays in skip mode rather than ending it, since
    # a folded scalar may carry a paragraph break.
    if [ "$skip_indent" -ge 0 ]; then
      [ -n "$trimmed" ] || continue
      indent="$(tc_indent "$line")"
      if [ "$indent" -gt "$skip_indent" ]; then continue; fi
      skip_indent=-1
    fi
    [ -n "$trimmed" ] || continue
    case "$trimmed" in
      '##'*) break ;;
    esac
    case "$trimmed" in
      '- id:'*)   tc_flush_entry "$out"; TC_ID="$(pc_trim "${trimmed#- id:}")" ;;
      'argv:'*)   TC_ARGV_RAW="$(pc_trim "${trimmed#argv:}")" ;;
      'cost:'*)   TC_COST="$(pc_trim "${trimmed#cost:}")" ;;
      'nearest:'*) TC_NEAREST_RAW="$(pc_trim "${trimmed#nearest:}")" ;;
      'absent:'*)
        TC_ABSENT=1
        case "$trimmed" in *'>-') skip_indent="$(tc_indent "$line")" ;; esac
        ;;
      'trap:'*)
        case "$trimmed" in *'>-') skip_indent="$(tc_indent "$line")" ;; esac
        ;;
      'id_form:'*)
        case "$trimmed" in *'>-') skip_indent="$(tc_indent "$line")" ;; esac
        ;;
    esac
  done <"$block_file"
  tc_flush_entry "$out"
  rm -f "$block_file"
}


# ------------------------------------------------------------------------------------------------
# The `## Check commands` block, and the recipe resolution every commanded check now runs from
# (dev-guides, process-recipes, "`## Check commands` is parsed, and it fails closed").
#
# The five commanded checks used to arrive as argv flags a model typed while reading a recipe's
# prose. Nothing compared them against the recipe, so a dropped `signal` key turned a tool that
# cannot fail by exit status into a check that always passed, and a dropped `--order-tests` turned
# an order nobody tested into one that passed. Every command is read from the recipe file here
# instead, and the caller hands over the recipe path rather than the command.
# ------------------------------------------------------------------------------------------------

# The entry being read, held between lines, the same way PC_* and TC_* are held above.
CC_ID=""; CC_ARGV_RAW=""; CC_ABSENT=0; CC_ABSENT_TEXT=""; CC_SIGNAL=""; CC_EXTS_RAW=""

# Appends one JSON object to $1 for the held row and clears it. `argv` and `extensions` are read as
# JSON through jq, never split by hand, and a value that does not parse as an array of strings is
# named in `unreadable` rather than dropped: a malformed row is a defect worth reporting, not a
# reason to report fewer rows than the recipe wrote. `absent` carries its own folded reason text,
# because that text is what a person reads when they ask why this check never ran.
cc_flush_entry() {
  local out="$1"
  [ -n "$CC_ID" ] || return 0
  local argv_json='null' exts_json='null' unreadable='[]' parsed
  if [ -n "$CC_ARGV_RAW" ]; then
    parsed="$(printf '%s' "$CC_ARGV_RAW" | jq -e -c 'if (type == "array") and (all(.[]; type == "string")) then . else empty end' 2>/dev/null)"
    if [ -n "$parsed" ]; then
      argv_json="$parsed"
    else
      unreadable="$(printf '%s' "$unreadable" | jq -c '. + ["argv"]')"
    fi
  fi
  if [ -n "$CC_EXTS_RAW" ]; then
    parsed="$(printf '%s' "$CC_EXTS_RAW" | jq -e -c 'if (type == "array") and (all(.[]; type == "string")) and (length > 0) then . else empty end' 2>/dev/null)"
    if [ -n "$parsed" ]; then
      exts_json="$parsed"
    else
      unreadable="$(printf '%s' "$unreadable" | jq -c '. + ["extensions"]')"
    fi
  fi
  jq -n --arg id "$CC_ID" --argjson argv "$argv_json" --argjson exts "$exts_json" \
        --argjson absent "$([ "$CC_ABSENT" = "1" ] && printf true || printf false)" \
        --arg absentText "$CC_ABSENT_TEXT" --arg signal "$CC_SIGNAL" \
        --argjson unreadable "$unreadable" '
    {id: $id}
    + (if $argv   == null  then {} else {argv: $argv} end)
    + (if $exts   == null  then {} else {extensions: $exts} end)
    + (if $absent == false then {} else {absent: true, absentReason: $absentText} end)
    + (if $signal == ""    then {} else {signal: $signal} end)
    + (if ($unreadable | length) == 0 then {} else {unreadable: $unreadable} end)
  ' >>"$out" || die 3 "the check-command row $CC_ID could not be recorded"
  CC_ID=""; CC_ARGV_RAW=""; CC_ABSENT=0; CC_ABSENT_TEXT=""; CC_SIGNAL=""; CC_EXTS_RAW=""
}

# Reads the section of the recipe at $1 that heading $2 opens and key $3 holds, appending one JSON
# object per row to $4. Prints the section's own state: `undeclared` when the heading is absent,
# `unparseable` when the heading is there but the key never opens under it, or `ok` when the key is
# there. The same three words, and the same folded-scalar handling, tc_parse_recipe already uses:
# one block shape, read one way, so the two parsers cannot drift.
#
# The heading and the key are arguments, the way recipe_block_into already takes them, because two
# blocks carry rows of this exact five-key shape: `## Check commands`, with key `check_commands`,
# and `## Surface commands`, with key `surface_commands` (ideal/review.md, "The recipe ask"). A
# second parser for the second block is the duplication this move removes.
cc_parse_recipe() {
  local recipe_file="$1" heading="$2" key="$3" out="$4"
  local block_file line trimmed indent skip_indent

  block_file="$out.ccblock"
  RECIPE_STATE="$(recipe_block_into "$recipe_file" "$heading" "$key" "$block_file")"
  [ "$RECIPE_STATE" = "ok" ] || return 0

  CC_ID=""; CC_ARGV_RAW=""; CC_ABSENT=0; CC_ABSENT_TEXT=""; CC_SIGNAL=""; CC_EXTS_RAW=""
  skip_indent=-1
  while IFS= read -r line; do
    trimmed="$(pc_trim "$line")"
    # A folded scalar continues on every line indented further than the key that opened it. For
    # `absent:` those lines are the reason itself, so they are kept rather than skipped.
    if [ "$skip_indent" -ge 0 ]; then
      if [ -z "$trimmed" ]; then continue; fi
      indent="$(tc_indent "$line")"
      if [ "$indent" -gt "$skip_indent" ]; then
        if [ "$CC_ABSENT" = "1" ]; then
          if [ -z "$CC_ABSENT_TEXT" ]; then
            CC_ABSENT_TEXT="$trimmed"
          else
            CC_ABSENT_TEXT="$CC_ABSENT_TEXT $trimmed"
          fi
        fi
        continue
      fi
      skip_indent=-1
    fi
    [ -n "$trimmed" ] || continue
    case "$trimmed" in
      '##'*) break ;;
    esac
    case "$trimmed" in
      '- id:'*)   cc_flush_entry "$out"; CC_ID="$(pc_trim "${trimmed#- id:}")" ;;
      'argv:'*)   CC_ARGV_RAW="$(pc_trim "${trimmed#argv:}")" ;;
      'signal:'*) CC_SIGNAL="$(pc_trim "${trimmed#signal:}")" ;;
      'extensions:'*) CC_EXTS_RAW="$(pc_trim "${trimmed#extensions:}")" ;;
      'absent:'*)
        CC_ABSENT=1
        CC_ABSENT_TEXT="$(pc_trim "${trimmed#absent:}")"
        case "$CC_ABSENT_TEXT" in '>-'|'>'|'|-'|'|') CC_ABSENT_TEXT="" ;; esac
        case "$trimmed" in *'>-'|*'>'|*'|-'|*'|') skip_indent="$(tc_indent "$line")" ;; esac
        ;;
    esac
  done <"$block_file"
  cc_flush_entry "$out"
  rm -f "$block_file"
}

# Prints, one per line, the literal markers the recipe at $1 declares for a run that passed while
# nothing was selected (`failure_signal:`, `silent_pass:`). A marker is a backtick-quoted token in
# that folded text. A token holding a `<placeholder>` is not printed: it is a shape for a person to
# read, never a literal substring anything can search for. Prints nothing when the recipe declares
# no silent-pass text, which is when the caller's own `--nothing-ran` flag still applies.
cc_silent_pass_markers() {
  local recipe_file="$1" block
  # Bounded twice, because one bound is not enough. The range ends at the closing fence, and
  # inside it the first line that opens another key ends the scalar. Without the second bound the
  # range ran to the next key at column 0, which is past the fence, and the Drupal recipe then
  # returned twelve markers harvested from its own prose, one of them ", ": every passing test run
  # held it, so every green read unknown.
  block="$(sed -n '/^[[:space:]]*silent_pass:/,/^```/p' "$recipe_file" 2>/dev/null \
    | sed -n '1p; 1!{ /^```/q; /^[[:space:]]*[a-z_][a-z_]*:/q; p; }')"
  [ -n "$block" ] || return 0
  printf '%s' "$block" | tr '\n' ' ' \
    | grep -o '`[^`]*`' 2>/dev/null \
    | sed 's/^`//; s/`$//' \
    | grep -v '<' \
    | grep -v '^$'
  return 0
}

# Parses one `<framework>=<path>` flag value and sets CR_PAIR to the tab-separated line the caller
# appends to its own list. $1 the action, $2 the flag, $3 the value.
#
# A global rather than a printed value, because a `$(...)` capture runs this in a subshell and a
# refusal inside it would exit that subshell alone, leaving the caller to carry on with an empty
# entry. That is the same rule br_seven_checks states above, and this function was written the
# wrong way round once already.
CR_PAIR=""
cr_recipe_pair() {
  local who="$1" flag="$2" value="$3" fw rp
  case "$value" in *=*) ;; *) die 3 "$who: $flag takes <framework>=<path>, got: $value" ;; esac
  fw="${value%%=*}"
  rp="${value#*=}"
  [ -n "$fw" ] || die 3 "$who: $flag was given no framework name: $value"
  [ -n "$rp" ] || die 3 "$who: $flag was given no path for framework $fw."
  [ -f "$rp" ] || die 3 "$who: the recipe handed over for $fw is not a file: $rp"
  CR_PAIR="$(printf '%s\t%s' "$fw" "$rp")"
}

# Resolves the recipes into the commands the checks run. The caller sets these globals first,
# because a `$(...)` capture would run this in a subshell and a refusal inside it would exit that
# subshell alone, which is the rule br_seven_checks already states.
#   CR_WHO              the action's own name, for a message
#   CR_TEST_RECIPES     newline list of <framework><TAB><path>, the `## Test commands` source
#   CR_CHECK_RECIPES    the same, for `## Check commands`
#   CR_SELECTED_JSON    a JSON array of the paths the selected-tests row runs, empty array when
#                       this caller has none (the baseline, which runs the suite whole)
# Sets CR_DOC.
#
# One tool row may carry a command from one framework only. A project on two frameworks whose
# recipes both name a coding-standards tool has two answers to one question, and nothing here may
# choose between them (exit 72). A row every framework declares absent is absent, and its reasons
# are joined.
CR_WHO=""; CR_TEST_RECIPES=""; CR_CHECK_RECIPES=""; CR_SELECTED_JSON="[]"; CR_DOC=""
# False resolves implementation's three tool rows. True resolves every row id the check recipes
# declare, which is review's own reading of the same block.
CR_TOOL_IDS_ALL=false
# The tab-separated --value list bl_tool_result reads. A global, because that function already
# takes five arguments and a sixth read only by one caller is a list read wrong sooner than right.
PC_VALUES=""
cr_resolve() {
  local work fw_file tools_file fw names
  local test_path check_path tc_rows cc_rows rows_file
  local tc_state cc_state markers marker_json
  local suite_json order_json tool_id tool_row
  local test_sha check_sha
  local all_tools tools_out commanded count absent_rows tool_ids

  records_hash__resolve_sha256_cmd \
    || die 3 "$CR_WHO: neither sha256sum nor 'shasum -a 256' was found on PATH"
  work="$(mktemp -d)" || die 3 "$CR_WHO: could not create a temporary folder"
  fw_file="$work/frameworks"
  tools_file="$work/tools"
  rows_file="$work/rows"
  : >"$fw_file"
  : >"$tools_file"

  names="$(printf '%s\n%s' "$CR_TEST_RECIPES" "$CR_CHECK_RECIPES" | cut -f1 | grep -v '^$' | sort -u)"
  while IFS= read -r fw; do
    [ -n "$fw" ] || continue
    test_path="$(cr_lookup "$CR_TEST_RECIPES" "$fw")"
    check_path="$(cr_lookup "$CR_CHECK_RECIPES" "$fw")"

    tc_rows='[]'; tc_state="not-given"; test_sha=""; marker_json='[]'
    suite_json='{"missing":"no --test-recipe named this framework, so no suite command was read"}'
    order_json='{"missing":"no --test-recipe named this framework, so no selected-tests command was read"}'
    if [ -n "$test_path" ]; then
      test_sha="$(tf_sha256_of "$test_path")"
      : >"$rows_file"
      tc_parse_recipe "$test_path" "$rows_file"
      tc_state="$RECIPE_STATE"
      tc_rows="$(jq -s '.' "$rows_file" 2>/dev/null)" || tc_rows='[]'
      markers="$(cc_silent_pass_markers "$test_path")"
      marker_json="$(printf '%s' "$markers" | jq -Rsc 'split("\n") | map(select(length > 0))')"
      [ -n "$marker_json" ] || marker_json='[]'
      if [ "$tc_state" != "ok" ]; then
        suite_json="$(jq -nc --arg s "$tc_state" '{missing: ("the recipe test-commands section could not be read (state: " + $s + ")")}')"
        order_json="$suite_json"
      else
        suite_json="$(cr_row_command "$tc_rows" "suite" "suite")"
        # Two rows can run a named set of tests. `changed` takes a path list whole and is the exact
        # shape this needs, so it is read first; `file` is the fallback where a framework declares
        # `changed` absent. A framework declaring both absent leaves order-tests undeclared, and an
        # order whose own tests nothing runs never passes its checks.
        order_json="$(cr_row_command "$tc_rows" "changed" "selected-tests")"
        case "$order_json" in
          '{"missing"'*|'{"absent"'*) order_json="$(cr_row_command "$tc_rows" "file" "selected-tests")" ;;
        esac
      fi
    fi

    cc_rows='[]'; cc_state="not-given"; check_sha=""
    if [ -n "$check_path" ]; then
      check_sha="$(tf_sha256_of "$check_path")"
      : >"$rows_file"
      cc_parse_recipe "$check_path" "Check commands" "check_commands" "$rows_file"
      cc_state="$RECIPE_STATE"
      cc_rows="$(jq -s '.' "$rows_file" 2>/dev/null)" || cc_rows='[]'
      printf '%s' "$cc_rows" | jq -c --arg fw "$fw" '.[] | . + {framework: $fw}' >>"$tools_file"
    fi

    jq -nc --arg framework "$fw" --arg tcState "$tc_state" --arg ccState "$cc_state" \
      --arg testSha "$test_sha" --arg checkSha "$check_sha" \
      --arg testRecipe "$test_path" --arg checkRecipe "$check_path" \
      --argjson suite "$suite_json" --argjson orderTests "$order_json" \
      --argjson silentPass "$marker_json" --argjson testRows "$tc_rows" '
      {framework: $framework,
       testRecipe: $testRecipe, testRecipeSha256: $testSha, testCommandsState: $tcState,
       testCommandsRows: $testRows,
       checkRecipe: $checkRecipe, checkRecipeSha256: $checkSha, checkCommandsState: $ccState,
       suite: $suite, orderTests: $orderTests, silentPass: $silentPass}' >>"$fw_file" \
      || die 3 "$CR_WHO: the resolved recipe entry for $fw could not be recorded"
  done <<CR_NAMES
$names
CR_NAMES
  rm -f "$rows_file"

  # --- one command per tool row, across every framework -------------------------------------------
  all_tools="$(jq -s '.' "$tools_file" 2>/dev/null)" || all_tools='[]'
  tools_out='[]'
  # The three ids below are implementation's own floor, and they are the whole list while
  # CR_TOOL_IDS_ALL is false. Review sets it true, because a framework that declares a duplication
  # tool or a design-metrics tool gets one row each and review runs every row (ideal/review.md,
  # "The check commands block is not fixed at three rows"). The ids are then read off the resolved
  # rows themselves, so nothing here carries a second list to keep in step. Walked as a
  # here-document rather than `for id in $list`, because zsh does not word-split an unquoted
  # expansion.
  tool_ids='coding-standards
static-analysis
security'
  if [ "$CR_TOOL_IDS_ALL" = "true" ]; then
    tool_ids="$(printf '%s' "$all_tools" | jq -r '[ .[].id ] | unique | .[]')"
  fi
  while IFS= read -r tool_id; do
    [ -n "$tool_id" ] || continue
    commanded="$(printf '%s' "$all_tools" | jq -c --arg id "$tool_id" \
      '[ .[] | select(.id == $id and (has("argv")) and (((.unreadable // []) | index("argv")) == null)) ]')"
    count="$(printf '%s' "$commanded" | jq 'length')"
    if [ "$count" -gt 1 ]; then
      die 72 "$CR_WHO: $(printf '%s' "$commanded" | jq -r '[ .[].framework ] | join(" and ")') each declare a $tool_id command, and nothing here may choose between two answers to one question. Resolve one check recipe for this task, or split the frameworks into two tasks."
    fi
    if [ "$count" -eq 1 ]; then
      tools_out="$(jq -nc --argjson out "$tools_out" --argjson row "$(printf '%s' "$commanded" | jq -c '.[0]')" '$out + [$row]')"
      continue
    fi
    absent_rows="$(printf '%s' "$all_tools" | jq -c --arg id "$tool_id" \
      '[ .[] | select(.id == $id and (.absent // false)) ]')"
    if [ "$(printf '%s' "$absent_rows" | jq 'length')" -gt 0 ]; then
      tools_out="$(jq -nc --argjson out "$tools_out" --arg id "$tool_id" --argjson rows "$absent_rows" '
        $out + [{id: $id, absent: true,
                 absentReason: ([ $rows[] | (.framework + ": " + (.absentReason // "no reason given")) ] | join(" ")) }]')"
      continue
    fi
    tools_out="$(jq -nc --argjson out "$tools_out" --arg id "$tool_id" '
      $out + [{id: $id, missing: "no resolved check recipe carries a row for this tool"}]')"
  done <<CR_TOOL_IDS_IN
$tool_ids
CR_TOOL_IDS_IN

  CR_DOC="$(jq -s --argjson tools "$tools_out" '{frameworks: ., tools: $tools}' "$fw_file")" \
    || die 3 "$CR_WHO: the resolved recipe document could not be assembled"
  rm -rf "$work"
}

# The path $2 was given for in the tab-separated list $1, compared as whole text. Prints it, or
# nothing when the name is not there. A `grep` pattern built from a framework name reads a
# metacharacter in that name as a regular expression and matches the wrong row or none, which is
# why every lookup over a name this script does not control is a string comparison instead.
cr_lookup() {
  local list="$1" want="$2" line name
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="${line%%	*}"
    if [ "$name" = "$want" ]; then
      printf '%s' "${line#*	}"
      return 0
    fi
  done <<CR_LOOKUP
$list
CR_LOOKUP
  return 0
}

# The command one test-command row declares, as the object cr_resolve records. $1 the parsed rows,
# $2 the row id to read, $3 a word for the message. Prints one of three shapes: a command, an
# absent row with its own reason, or missing with why.
cr_row_command() {
  local rows="$1" row_id="$2" label="$3" row argv
  row="$(printf '%s' "$rows" | jq -c --arg id "$row_id" '[ .[] | select(.id == $id) ][0] // null')"
  if [ "$row" = "null" ]; then
    jq -nc --arg l "$label" --arg r "$row_id" '{missing: ("the recipe carries no test-commands row with id " + $r + ", so there is no " + $l + " command")}'
    return 0
  fi
  if [ "$(printf '%s' "$row" | jq -r '.absent // false')" = "true" ]; then
    jq -nc --arg r "$row_id" '{absent: ("the recipe declares its " + $r + " row absent")}'
    return 0
  fi
  if printf '%s' "$row" | jq -e '(.unreadable // []) | index("argv")' >/dev/null 2>&1; then
    jq -nc --arg r "$row_id" '{missing: ("the " + $r + " row argv did not parse as a JSON array of strings")}'
    return 0
  fi
  argv="$(printf '%s' "$row" | jq -c '.argv // empty')"
  if [ -z "$argv" ] || [ "$argv" = "null" ]; then
    jq -nc --arg r "$row_id" '{missing: ("the " + $r + " row declares no argv to run")}'
    return 0
  fi
  jq -nc --argjson argv "$argv" --arg r "$row_id" '{row: $r, argv: $argv}'
}


# The sha256 of file $1, lowercase hex, through the same tool records-hash.sh already resolved into
# RECORDS_HASH_SHA256_CMD: one place decides which of sha256sum or `shasum -a 256` exists, and nothing
# here carries a second copy of that decision.
tf_sha256_of() {
  "${RECORDS_HASH_SHA256_CMD[@]}" <"$1" 2>/dev/null | cut -d' ' -f1
}

# True when path $1 matches the case glob $2. bash always treats an unquoted variable used as a
# case pattern as a glob; zsh, by default, does not, and matches it as the literal text instead
# (Honesty: this script runs under both). GLOB_SUBST restores the glob reading, scoped to the
# subshell this runs in only, the same discipline pc_run_check already applies to SH_WORD_SPLIT, so
# it never changes how the rest of the script's own case statements behave.
tf_path_matches_glob() {
  (
    if [ -n "${ZSH_VERSION:-}" ]; then
      setopt GLOB_SUBST 2>/dev/null
    fi
    case "$1" in
      $2) exit 0 ;;
      *)  exit 1 ;;
    esac
  )
}

# The text of $1 up to its first "/", or all of $1 when it holds none.
tf_first_segment() {
  case "$1" in
    */*) printf '%s' "${1%%/*}" ;;
    *)   printf '%s' "$1" ;;
  esac
}

# The text of $1 after its first "/", or empty when it holds none. Paired with tf_first_segment to
# peel a "/"-joined string apart one segment at a time without ever word-splitting an unquoted
# expansion, the same reasoning tf_name_carries already states for its own comma list.
tf_rest_segments() {
  case "$1" in
    */*) printf '%s' "${1#*/}" ;;
    *)   printf '%s' "" ;;
  esac
}

# True when path (a "/"-joined list of segments, $1) matches glob (the same shape, $2) under the
# catalog's own `**` semantics (drupal/standards-and-tests.md: a leading `**/` is an optional path
# prefix, added so the same pattern also covers a test tree at the repository root). Plain `case`
# cannot express this on its own: there, `**` is nothing more than one `*`, and a lone `*` there
# crosses `/` freely, both wrong for what the catalog declares. So a `**` segment is handled here,
# once, before either string ever reaches a `case`: it may consume zero path segments or, when at
# least one remains, one more and try again, which is why this recurses rather than looping. Every
# other segment consumes exactly one path segment and is matched against it, alone, through
# tf_path_matches_glob, which is where a bounded `*` (one that cannot cross `/`, because there is
# none left inside a single segment) is exactly the semantics `case` already gives for free.
tf_segments_match() {
  # Never named "path": zsh ties that exact name to $PATH as a special array (Honesty: this script
  # runs under zsh too), and that tie, combined with this file's own KSH_ARRAYS and nounset, made a
  # bare `[ -z "$path" ]` on this variable report "parameter not set" even immediately after it was
  # plainly assigned. "walk" is the segments still left to match; every other local name here is
  # checked against zsh's own special-parameter list before use.
  local walk glob gseg grest wseg wrest
  walk="$1"
  glob="$2"
  if [ -z "$glob" ]; then
    [ -z "$walk" ]
    return $?
  fi
  gseg="$(tf_first_segment "$glob")"
  grest="$(tf_rest_segments "$glob")"
  if [ "$gseg" = "**" ]; then
    tf_segments_match "$walk" "$grest" && return 0
    [ -n "$walk" ] || return 1
    wrest="$(tf_rest_segments "$walk")"
    tf_segments_match "$wrest" "$glob"
    return $?
  fi
  [ -n "$walk" ] || return 1
  wseg="$(tf_first_segment "$walk")"
  wrest="$(tf_rest_segments "$walk")"
  tf_path_matches_glob "$wseg" "$gseg" || return 1
  tf_segments_match "$wrest" "$grest"
}

# True when path $1 matches catalog glob $2, stripping a leading or trailing "/" from each first so
# an incidental one never creates a spurious empty segment before the two are compared segment by
# segment through tf_segments_match. Parameter kept out of a variable named "path" for the same
# zsh-special-parameter reason tf_segments_match states.
tf_path_matches_catalog_glob() {
  local walk glob
  walk="$1"
  glob="$2"
  case "$walk" in /*) walk="${walk#/}" ;; esac
  case "$walk" in */) walk="${walk%/}" ;; esac
  case "$glob" in /*) glob="${glob#/}" ;; esac
  case "$glob" in */) glob="${glob%/}" ;; esac
  tf_segments_match "$walk" "$glob" && return 0
  # design-schema.json lets an owned entry be a file or a directory. A directory covers its own
  # subtree, which is the rule hooks/deny-prior-source.sh already applies to the same values; this
  # matcher read it as one path and answered no to every file under it, so an order owning a
  # directory failed owned-files on every attempt. A pattern holding a glob character keeps the
  # segment behaviour above and never takes this branch, because a glob names a set, not a root.
  case "$glob" in
    *'*'*|*'?'*|*'['*) return 1 ;;
  esac
  case "$walk" in
    "$glob"/*) return 0 ;;
  esac
  return 1
}


# Runs the argv array $1 from inside $2, writing what the command printed to $3. $4 is the JSON
# array a token that is exactly `{paths}` or `{file}` expands to, one argv token per entry. $5 is
# the tab-separated `--value` list every other single-placeholder token is read from. $6, when
# given, receives standard error on its own, for a row whose recipe declares `signal: empty-stdout`.
#
# Prints one of three tab-separated results and never dies:
#   UNRESOLVED<TAB><name>  a placeholder token nothing supplied a value for, naming it
#   EMPTY<TAB>             the argv holds no token at all. An exec with no operands returns 0
#                          without replacing the shell, so this is a refusal and never a run
#   RAN<TAB><exit status>  once the command actually ran, whatever it exited with
br_run_resolved() {
  local argv_json="$1" dir="$2" outfile="$3" paths_json="$4" values="$5" errfile="${6:-}"
  local count i tok name pcount pi rc
  set --
  count="$(printf '%s' "$argv_json" | jq 'length' 2>/dev/null)"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  pcount="$(printf '%s' "$paths_json" | jq 'length' 2>/dev/null)"
  case "$pcount" in ''|*[!0-9]*) pcount=0 ;; esac
  i=0
  while [ "$i" -lt "$count" ]; do
    tok="$(printf '%s' "$argv_json" | jq -r --argjson i "$i" '.[$i]' 2>/dev/null)"
    case "$tok" in
      '{paths}'|'{file}')
        pi=0
        while [ "$pi" -lt "$pcount" ]; do
          set -- "$@" "$(printf '%s' "$paths_json" | jq -r --argjson pi "$pi" '.[$pi]')"
          pi=$((pi + 1))
        done
        ;;
      '{'*'}')
        name="${tok#\{}"; name="${name%\}}"
        tok="$(cr_lookup "$values" "$name")"
        if [ -z "$tok" ]; then
          printf 'UNRESOLVED\t%s' "$name"
          return 0
        fi
        set -- "$@" "$tok"
        ;;
      *) set -- "$@" "$tok" ;;
    esac
    i=$((i + 1))
  done
  if [ "$#" -eq 0 ]; then
    printf 'EMPTY\t'
    return 0
  fi
  if [ -n "$errfile" ]; then
    ( cd "$dir" || exit 127; exec "$@" ) >"$outfile" 2>"$errfile"
    rc=$?
  else
    ( cd "$dir" || exit 127; exec "$@" ) >"$outfile" 2>&1
    rc=$?
  fi
  printf 'RAN\t%s' "$rc"
}

# Prints the entries of $1, a JSON array of paths, that end in one of the extensions in $2, a JSON
# array of extension strings. A tool handed a file type it does not read either skips it in silence
# or parses it as its own language and fails on it, which is why a row that names its extensions is
# never given anything else (dev-guides, process-recipes, `## Check commands` is parsed).
br_filter_extensions() {
  jq -cn --argjson paths "$1" --argjson exts "$2" '
    [ $paths[] as $f | select([ $exts[] as $e | select($f | endswith($e)) ] | length > 0) | $f ]
  '
}


# Exit 73. Every tool check compares its own result against the baseline that step two took, and
# that comparison is only honest while both ran the same command. The baseline records the check
# recipe it read and a sha256 of that file, per framework; a later run resolving a different file
# refuses rather than compare one tool output against another tool baseline.
# $1 the action, $2 the baseline file. Reads CR_DOC.
cr_require_baseline_recipes() {
  local who="$1" baseline_file="$2" baseline_doc count idx fw now_sha was_sha was_path
  [ -f "$baseline_file" ] || return 0
  baseline_doc="$(jq -c '.' "$baseline_file" 2>/dev/null)"
  [ -n "$baseline_doc" ] || return 0
  count="$(printf '%s' "$CR_DOC" | jq '(.frameworks // []) | length')"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  idx=0
  while [ "$idx" -lt "$count" ]; do
    fw="$(printf '%s' "$CR_DOC" | jq -r --argjson i "$idx" '.frameworks[$i].framework')"
    now_sha="$(printf '%s' "$CR_DOC" | jq -r --argjson i "$idx" '.frameworks[$i].checkRecipeSha256')"
    was_sha="$(printf '%s' "$baseline_doc" | jq -r --arg f "$fw" '[ (.checkRecipes // [])[] | select(.framework == $f) ][0].sha256 // ""')"
    was_path="$(printf '%s' "$baseline_doc" | jq -r --arg f "$fw" '[ (.checkRecipes // [])[] | select(.framework == $f) ][0].path // ""')"
    if [ -n "$now_sha" ] && [ -n "$was_sha" ] && [ "$now_sha" != "$was_sha" ]; then
      die 73 "$who: the check recipe resolved for $fw is not the one the baseline was taken with. The baseline read $was_path (sha256 $was_sha) and this run reads sha256 $now_sha. Every tool check compares itself against that baseline, so take the baseline again before recording this."
    fi
    idx=$((idx + 1))
  done
}

# Exit 61. Every check but one reads the working tree: the tools run over the files on disk, the
# tests run on disk, and frozen-tests hashes the file on disk. The owned-files check is the one
# that compares two commits, so a write nobody committed is invisible to it alone and reads as met.
# The same uncommitted write then leaves the round's diff empty, and a verifier reading an empty
# diff can call a finding addressed. So both record steps refuse a tree that is not clean before
# any check runs. $1 the action's own name, $2 the code repository.
#
# Modified, staged and untracked all count. An untracked file is a file this order may have added
# and never declared, which is exactly what the owned-files check exists to catch.
# $3 the unit id, $4 the run mode, $5 the ledger file and $6 the ledger document are optional, and
# together they are what an unattended run needs. Interactive, the refusal is enough: a person is
# there to commit and run the step again. Unattended there is nobody, so the order would sit in
# flight with no reason on it, which is the halt nobody sees until they ask. So an autonomous run
# writes haltedBecause first and then refuses. `close` passes none of the four and only refuses,
# because an order reaching close has already been recorded and judged.
br_require_clean_tree() {
  local who="$1" repo="$2" unit_id="${3:-}" run_mode="${4:-}" ledger_file="${5:-}" ledger_doc="${6:-}"
  local dirty why halted_doc
  # Not --ignored. A gitignored file an implementer wrote can change a test outcome while leaving
  # a clean tree, and that is a real gap, but --ignored lists node_modules and every other build
  # product a repository ignores on purpose, so every record step refused. The gap stands.
  dirty="$(git -C "$repo" status --porcelain 2>/dev/null)"
  [ -z "$dirty" ] && return 0
  # The reason never carries the filenames. A path holding the text this stage joins halt reasons
  # with would forge a segment, and the reason is read back by split. The count is the fact a halt
  # needs; the names go to standard error, where nothing parses them.
  local dirty_count
  dirty_count="$(printf '%s' "$dirty" | grep -c '.' 2>/dev/null)"
  case "$dirty_count" in ''|*[!0-9]*) dirty_count=0 ;; esac
  why="uncommitted changes in the code repository ($dirty_count paths, listed on stderr)"
  printf '%s: the uncommitted paths in %s are:\n%s\n' "$who" "$repo" "$dirty" >&2
  if [ "$run_mode" = "autonomous" ] && [ -n "$ledger_file" ] && [ -n "$ledger_doc" ] && [ -n "$unit_id" ]; then
    halted_doc="$(halt_order_in "$ledger_doc" "$unit_id" "$why")"
    [ -n "$halted_doc" ] || die 3 "$who: the ledger update for $unit_id failed."
    write_atomic "$ledger_file" "$halted_doc"
    echo "$(printf '%s' "$who" | tr '[:lower:]' '[:upper:]'): $unit_id is halted. $why" >&2
  fi
  die 61 "$who: the working tree at $repo is not clean, and the checks below would read a tree the record cannot describe. The owned-files check compares two commits, so an uncommitted change passes it while staying in the tree. Commit this role's work, then write the record. What is uncommitted: $(printf '%s' "$dirty" | tr '\n' ' ')"
}


# The verdict that wins when several frameworks answer one check. Undeclared ranks lowest, so a
# framework that declared nothing never drags down one that ran and passed; unmet ranks highest,
# because a definite failure outranks a question. $1 the JSON array of per-framework verdicts.
#
# This is deliberately not pc_rank's order, which puts met below undeclared. There the question is
# what a whole run may report, and a recipe declaring nothing must not read as a pass. Here the
# question is what one check answered across several frameworks, and a framework with no row to run
# has said nothing about it. Collapsing the two would make one of the two questions answer wrongly.
br_worst_verdict() {
  printf '%s' "$1" | jq -r '
    def rank: if . == "undeclared" then 0 elif . == "met" then 1 elif . == "unknown" then 2 else 3 end;
    (. + ["undeclared"]) | max_by(rank)'
}



# ------------------------------------------------------------------------------------------------
# The one --value flag, and the findings file a reviewer writes. Both stages take the same flag and
# read a findings file of the same shape, so both refusals live here rather than in each script.
# ------------------------------------------------------------------------------------------------

# Refuses a --value whose name or value carries a newline or a tab. The value table this script
# builds is newline and tab delimited, so either character inside a value forges a row and answers
# a placeholder the caller never supplied. $1 the action, $2 the flag value as given.
pc_refuse_forged_value() {
  local who="$1" pair="$2"
  case "$pair" in
    *"$(printf '\t')"*)
      die 3 "$who: --value was given text holding a tab, and the table this builds is tab delimited, so a tab inside a value forges a row: $pair"
      ;;
  esac
  # Counted, never matched as a pattern: command substitution strips trailing newlines, so
  # `*"$(printf '\n')"*` is `*""*`, which matches every value and refused all of them.
  [ "$(printf '%s' "$pair" | wc -l | tr -d '[:space:]')" = "0" ] \
    || die 3 "$who: --value was given text holding a newline, and the table this builds is newline delimited, so a newline inside a value forges a row: $pair"
  [ -n "${pair%%=*}" ] || die 3 "$who: --value was given no name: $pair"
}

# The one place a finding id's shape is decided: `f` and then digits, with no leading zero, which
# is what scripts/review-record-schema.json requires of the field this id lands in. Returns 0 when
# the id is that shape. A glob of `f[1-9]*` would pass `f1a` and `f9 foo`, and such an id then
# reads as zero where verify-record mints the next one, so a record already holding `f3a` would
# mint `f1` again and two findings would answer to one verdict.
rv_is_finding_id() {
  local id="$1" rest
  case "$id" in
    f*) rest="${id#f}" ;;
    *) return 1 ;;
  esac
  [ -n "$rest" ] || return 1
  case "$rest" in
    *[!0-9]*) return 1 ;;
    0*) return 1 ;;
  esac
  return 0
}

# Reads $1, a file the reviewer wrote, and sets RV_FINDINGS_ARRAY to the array under key $2 after
# checking every entry's own shape. $3 the action's own name. Dies (exit 52) on anything it cannot
# read as that shape, because a findings file this script half understands is worse than none.
#
# It sets a global rather than printing, and every caller calls it as a plain statement. A function
# that refuses must never be called with `$(...)`: a command substitution runs in a subshell, so the
# refusal would exit that subshell alone and the caller would carry on with an empty list. That is
# the same rule br_seven_checks states above, and this function was written the wrong way once.
RV_FINDINGS_ARRAY=""
# Refuses a hand-written JSON file that names one key twice. jq resolves a duplicate to the last
# occurrence and says nothing, so a findings file carrying `findings` twice silently discards the
# earlier array, and a review with findings records as clean.
#
# `jq --stream` reports every path as it reads it, duplicates included, while the parsed document
# has already lost them. So the file is streamed twice, once from disk and once from the document
# jq parsed out of it, and a difference in the paths read is a key written more than once. The
# message names the paths that appeared too often.
# $1 the file, $2 the action. Never returns on a duplicate.
RV_STREAM_PATHS_JQ='[ inputs | .[0] | map(tostring) | join(".") ] | sort'
rv_refuse_duplicate_keys() {
  local file="$1" who="$2" from_file from_doc dup
  from_file="$(jq -cn --stream "$RV_STREAM_PATHS_JQ" "$file" 2>/dev/null)"
  [ -n "$from_file" ] || return 0
  from_doc="$(jq -c '.' "$file" 2>/dev/null | jq -cn --stream "$RV_STREAM_PATHS_JQ" 2>/dev/null)"
  [ -n "$from_doc" ] || return 0
  [ "$from_file" = "$from_doc" ] && return 0
  dup="$(jq -rn --argjson a "$from_file" --argjson b "$from_doc" '
    [ ($a | group_by(.) | map({k: .[0], n: length})[]) as $x
      | ($b | map(select(. == $x.k)) | length) as $m
      | select($x.n > $m) | $x.k ] | unique | join(", ")')"
  [ -n "$dup" ] || dup="a key this reader could not name"
  die 52 "$who: $file writes the same key more than once, at: $dup. A duplicate key resolves to the last one and throws the earlier value away in silence, so this is refused rather than half read."
}

rv_read_findings_array() {
  local file="$1" key="$2" who="$3" doc arr count i one id severity evidence seen_ids=""
  [ -f "$file" ] || die 52 "$who: $file not found. The file named on the command line has to exist."
  [ -s "$file" ] || die 52 "$who: $file is empty. An empty file is not an empty findings list; write { \"$key\": [] } instead."
  doc="$(jq -c '.' "$file" 2>/dev/null)"
  [ -n "$doc" ] || die 52 "$who: $file is not valid JSON."
  rv_refuse_duplicate_keys "$file" "$who"
  arr="$(printf '%s' "$doc" | jq -c --arg k "$key" 'if (.[$k] | type) == "array" then .[$k] else null end')"
  [ -n "$arr" ] && [ "$arr" != "null" ] \
    || die 52 "$who: $file holds no $key array. The shape is { \"$key\": [ ... ] }."
  count="$(printf '%s' "$arr" | jq 'length')"
  i=0
  while [ "$i" -lt "$count" ]; do
    one="$(printf '%s' "$arr" | jq -c --argjson i "$i" '.[$i]')"
    [ "$(printf '%s' "$one" | jq -r 'type')" = "object" ] \
      || die 52 "$who: entry $i of $key in $file is not an object."
    id="$(printf '%s' "$one" | jq -r '.id // ""')"
    rv_is_finding_id "$id" \
      || die 52 "$who: entry $i of $key in $file has the id '$id'. A finding id is f and then digits, with no leading zero: f1, f2, f10."
    severity="$(printf '%s' "$one" | jq -r '.severity // ""')"
    case "$severity" in
      high|medium|low) ;;
      *) die 52 "$who: finding $id in $file has the severity '$severity'. The three words are high, medium and low." ;;
    esac
    evidence="$(printf '%s' "$one" | jq -r '.evidence // ""')"
    [ -n "$evidence" ] \
      || die 52 "$who: finding $id in $file carries no evidence. A finding with nothing to read is not a finding."
    # Two findings under one id are two findings nothing can tell apart. One verdict would answer
    # both, and one ruling would close both, so the list is refused rather than half read.
    case " $seen_ids " in
      *" $id "*) die 52 "$who: $file names the finding $id more than once. Each finding carries its own id." ;;
    esac
    seen_ids="$seen_ids $id"
    i=$((i + 1))
  done
  RV_FINDINGS_ARRAY="$arr"
}
