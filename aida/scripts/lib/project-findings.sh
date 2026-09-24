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
#   pf_task_rule_v5 <codePath> <project file>
#     Prints `open` when <codePath>/CLAUDE.md holds a version 5 block and the project file records
#     no decline, `declined` when it records one, and nothing when there is no block.
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
# shellcheck disable=SC2034 # read by project-actions.sh, which removes and replaces the block
TASK_RULE_V5_END="<!-- ai-dev-assistant:task-rule:end -->"

pf_task_rule_v5() {
  local code_path="$1" project_file="$2"
  grep -qF "$TASK_RULE_V5_BEGIN" "${code_path%/}/CLAUDE.md" 2>/dev/null || return 0
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
