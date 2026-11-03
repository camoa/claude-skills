#!/usr/bin/env bash
# session.sh: whether a person is taken to be at this session.
#
# Two gates ask it: task_attended in task-helpers.sh, for a step of a task, and cr_require_person
# in recipes.sh, for a recipe step that may have no task. Neither library sources the other, so the
# one reader of the variable lives here (gap row 481).
#
# Public function:
#
#   session_attended            true when the session reports itself attended

# Claude Code sets CLAUDE_CODE_SESSION_ATTENDED but does not document it. Any value other than 1
# reads unattended, so if the variable goes away a person step needs the recorded answer again.
session_attended() {
  [ "${CLAUDE_CODE_SESSION_ATTENDED:-}" = 1 ]
}
