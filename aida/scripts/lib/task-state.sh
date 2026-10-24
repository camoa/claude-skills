#!/usr/bin/env bash
# task-state.sh: the one reading of a task's open state, for next's listing and the project close.
# Its own file, because project-actions.sh needs this rule without task-helpers.sh's load-time
# version warnings: check-machine prints no stderr line. task-helpers.sh sources it for its callers.

# A task is open until its state reads complete. A file jq cannot read answers true; a caller that
# skips such a file tests it first. $1 the task.json. Calls no die function.
task_is_open() {
  [ "$(jq -r '.state // "new"' "$1" 2>/dev/null)" != "complete" ]
}
