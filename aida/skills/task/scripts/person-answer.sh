#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# person-answer.sh: the one action that records a person's answer, for a step only a person decides.
#
#   person-answer.sh --project <path> <task-id> --step <step> [--order <id>] -- <words...>
#
# It appends one entry to the task's answer record (task_answer_file in task-helpers.sh), and the
# step refuses without it. The step is "<skill> <action>", such as "implement redo". The
# words are the exact text the step carries, after `--`, or @/<file> when they run over one line.
# Nothing here checks the step's name: an entry no step matches is never used.
#
# The plugin's hook makes Claude Code show its permission prompt for every call of this script,
# and refuses it where no prompt can show, so a denied prompt writes nothing. It is a script of its
# own, outside task-actions.sh, so no skill's allowed-tools rule pre-approves it.
#
# Exit 3 on a usage fault or a record it cannot read, 1 when the task does not exist.

set -uo pipefail
die3() { printf 'person-answer: %s\n' "$1" >&2; exit 3; }
# shellcheck source=/dev/null
source "${PLUGIN_ROOT}/scripts/lib/task-helpers.sh" || die3 "the task-helpers library failed to load"
command -v jq >/dev/null 2>&1 || die3 "jq is required and was not found on PATH"

text_args "$@"
set -- ${TEXT_ARGS[@]+"${TEXT_ARGS[@]}"}
project_path="" id="" step="" order=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) project_path="${2:?--project needs a value}"; shift 2 ;;
    --step) step="${2:?--step needs a value}"; shift 2 ;;
    --order) order="${2:?--order needs a value}"; shift 2 ;;
    --) shift; break ;;
    *)
      if [ -z "$id" ]; then id="$1"; shift
      else die3 "unrecognized argument: $1"
      fi
      ;;
  esac
done
[ -n "$project_path" ] || die3 "--project is required"
project_path="$(cd "$project_path" 2>/dev/null && pwd -P)" || die3 "--project is not a folder"
[ -n "$id" ] || die3 "a task id is required"
is_blank "$step" && die3 "--step is required, such as 'implement redo'"
is_blank "$*" && die3 "the person's words are required after --"
task_dir="$project_path/tasks/$id"
[ -f "$task_dir/task.json" ] || { echo "NOT FOUND: ${id}" >&2; exit 1; }

file="$(task_answer_file "$task_dir")"
[ -f "$file" ] || printf '[]\n' >"$file" || die3 "could not create $file"
written="$(jq --arg step "$step" --arg order "$order" --arg words "$*" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  'if type == "array" then . + [{step: $step, order: $order, words: $words, answeredAt: $at}] else empty end' "$file")"
[ -n "$written" ] || die3 "$file is not a readable list of answers. Nothing was written. Repair it by hand"
write_atomic "$file" "$written"
commit_task_change "$project_path" "Record a person's answer for ${step} on ${id}" "a person answered Claude Code's prompt" "" "" "$id" "answer" \
  || printf 'person-answer: %s was written but not committed. Commit it by hand.\n' "$file" >&2
echo "ANSWER: ${step}${order:+ ${order}}"
echo "record: $file"
echo "unused: $(jq '[ .[] | select((.usedAt // null) == null) ] | length' "$file")"
