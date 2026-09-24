#!/usr/bin/env bash
# project-findings.sh: two findings about a project that more than the project check must see.
#
# check-project.sh reports both. project-actions.sh repairs them. hooks/session-start.sh names
# them before the first turn, because a session can follow a stale rule before anyone runs the
# check (live-run row 191). Each of the three sources this file, so each finding is detected in
# one place. No library they already shared fitted: the check sources only schema-check.sh, and
# the hook and the actions share registry.sh, which is the directory store.
#
# Public:
#
#   TASK_RULE_V5_BEGIN, TASK_RULE_V5_END
#     The markers version 5 wrote around its task rule in a code repository's CLAUDE.md.
#
#   pf_block_lines <file> <begin marker> <end marker>
#     Prints `<begin line> 0` for the first begin marker that no end marker closes before the next
#     begin marker or the end of the file. When every block closes, it prints `<begin line> <end
#     line>` for the first block. Prints nothing when the file holds no begin marker. An open block
#     is never rewritten or removed blind: the rest of the file below it may be the person's text.
#
#   pf_task_rule_v5 <codePath> <project file>
#     Prints `malformed <line>` when <codePath>/CLAUDE.md holds a version 5 begin marker on that
#     line and no end marker after it, whatever the project file records. Otherwise it prints
#     `open` for a version 5 block with no decline recorded, `declined` when one is recorded, and
#     nothing when there is no block.
#
#   pf_retired_fields <project schema> <project file>
#     Prints one compact JSON array, [{field, detail}], naming each top-level field of the project
#     file that the schema lists under `retired`, with the schema's reason. Prints `[]` when there
#     are none. Returns 1 and prints nothing when either file cannot be read as JSON.
#
# Portability: bash 3.2+ and zsh. This file is a library. Source it; do not run it.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file) : ;;
    *)
      printf 'project-findings.sh: this is a library, meant to be sourced, not run directly.\n' >&2
      exit 1
      ;;
  esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'project-findings.sh: this is a library, meant to be sourced, not run directly.\n' >&2
  exit 1
fi

TASK_RULE_V5_BEGIN="<!-- ai-dev-assistant:task-rule:begin -->"
TASK_RULE_V5_END="<!-- ai-dev-assistant:task-rule:end -->"

pf_block_lines() {
  local begins ends b e nb first=""
  begins="$(grep -n -F -e "$2" "$1" 2>/dev/null | cut -d: -f1)"
  [ -n "$begins" ] || return 0
  ends="$(grep -n -F -e "$3" "$1" 2>/dev/null | cut -d: -f1)"
  while IFS= read -r b; do
    e="$(printf '%s\n' "$ends" | while IFS= read -r x; do [ -n "$x" ] && [ "$x" -gt "$b" ] && { echo "$x"; break; }; done)"
    nb="$(printf '%s\n' "$begins" | while IFS= read -r x; do [ "$x" -gt "$b" ] && { echo "$x"; break; }; done)"
    if [ -z "$e" ] || { [ -n "$nb" ] && [ "$nb" -lt "$e" ]; }; then
      printf '%s 0\n' "$b"
      return 0
    fi
    [ -n "$first" ] || first="$b $e"
  done <<PF_BEGINS
$begins
PF_BEGINS
  printf '%s\n' "$first"
}

pf_task_rule_v5() {
  local code_path="$1" project_file="$2" lines
  lines="$(pf_block_lines "${code_path%/}/CLAUDE.md" "$TASK_RULE_V5_BEGIN" "$TASK_RULE_V5_END")"
  [ -n "$lines" ] || return 0
  if [ "${lines#* }" = "0" ]; then
    echo "malformed ${lines%% *}"
    return 0
  fi
  if jq -e '(.taskRule | type) == "object" and .taskRule.offered == true and .taskRule.accepted == false' \
       "$project_file" >/dev/null 2>&1; then
    echo "declined"
  else
    echo "open"
  fi
}

pf_retired_fields() {
  jq -c --slurpfile s "$1" '
    ($s[0].retired // {}) as $r
    | [ keys_unsorted[] as $k | select($r | has($k)) | {field: $k, detail: $r[$k]} ]' "$2" 2>/dev/null
}
