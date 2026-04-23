---
name: session-context-writer
description: Use when a framework command has resolved the active project and/or task and needs to persist that context for hooks. Writes per-workspace session_context.json so compaction hooks and the context-reminder hook can restore the right project/task context. Preserves loadedGuides[], lastPhase, and currentEpic across writes.
user-invocable: false
version: 1.4.0
model: haiku
allowed-tools: Bash
---

# Session Context Writer

Persist session context keyed by the current workspace so hooks can restore the correct project/task context. Each Claude Code window gets its own session file — no conflicts between windows.

## When Called

You receive the resolved project and task values from the calling command. Write them immediately. Preserve any `loadedGuides` and `lastPhase` already in the file.

## File Shape

```json
{
  "workspace": "/abs/path/to/cwd",
  "project": "my_project",
  "projectPath": "/abs/path/to/project",
  "task": "my_task",
  "taskPath": "/abs/path/to/task",
  "updatedAt": "2026-04-22",
  "loadedGuides": ["drupal/forms/form-validation"],
  "lastPhase": "research",
  "currentEpic": "dev_framework_improvements_epic"
}
```

`loadedGuides`, `lastPhase`, and `currentEpic` are managed by other components (`guide-integrator`, `task-frontmatter-reader`, the `context-reminder` hook) — this skill must not clobber them.

`currentEpic`, added in v1.4.0, is the folder name (not URI) of the epic that contains the active task, or `null` if the task is `kind: flat` or is itself the top-level epic. Callers set this value when they've resolved the epic ancestor via `task-frontmatter-reader`.

## Action

Run this bash command with the provided values. It merges the new core fields over any existing file, seeding `loadedGuides: []` and `lastPhase: null` only when the file is first created.

```bash
WORKSPACE_HASH=$(echo -n "$PWD" | md5sum | cut -d' ' -f1)
SESS_DIR=~/.claude/drupal-dev-framework/sessions
SESS_FILE=$SESS_DIR/${WORKSPACE_HASH}.json
mkdir -p "$SESS_DIR"

NEW_CORE=$(jq -n \
  --arg workspace "$PWD" \
  --arg project "{PROJECT_NAME}" \
  --arg projectPath "{PROJECT_PATH}" \
  --arg task "{TASK_NAME_OR_NULL}" \
  --arg taskPath "{TASK_PATH_OR_NULL}" \
  --arg updatedAt "$(date -I)" \
  '{
    workspace: $workspace,
    project: $project,
    projectPath: $projectPath,
    task: (if $task == "null" or $task == "" then null else $task end),
    taskPath: (if $taskPath == "null" or $taskPath == "" then null else $taskPath end),
    updatedAt: $updatedAt
  }')

NEW_EPIC_ARG='{CURRENT_EPIC_OR_NULL}'

if [ -s "$SESS_FILE" ] && jq -e . "$SESS_FILE" >/dev/null 2>&1; then
  # Preserve loadedGuides, lastPhase, and currentEpic; overwrite core fields.
  # currentEpic behavior: if the caller passed an explicit value (not the literal "{CURRENT_EPIC_OR_NULL}" placeholder), use it; otherwise preserve existing.
  jq --argjson new "$NEW_CORE" --arg epic "$NEW_EPIC_ARG" \
    '. * $new
     | .loadedGuides = (.loadedGuides // [])
     | .lastPhase = (.lastPhase // null)
     | .currentEpic = (
         if $epic == "{CURRENT_EPIC_OR_NULL}" then (.currentEpic // null)
         elif $epic == "null" or $epic == "" then null
         else $epic
         end
       )' \
    "$SESS_FILE" > "$SESS_FILE.tmp" && mv "$SESS_FILE.tmp" "$SESS_FILE"
else
  # First write, empty, or corrupt JSON — reseed from scratch with fresh core + preserved-field defaults.
  echo "$NEW_CORE" | jq --arg epic "$NEW_EPIC_ARG" '. + {
    loadedGuides: [],
    lastPhase: null,
    currentEpic: (if $epic == "{CURRENT_EPIC_OR_NULL}" or $epic == "null" or $epic == "" then null else $epic end)
  }' > "$SESS_FILE"
fi
```

Replace placeholders:
- `{PROJECT_NAME}` — resolved project name (e.g., `wasatch_update`)
- `{PROJECT_PATH}` — absolute project path
- `{TASK_NAME_OR_NULL}` — task name if known, or the literal string `null`
- `{TASK_PATH_OR_NULL}` — absolute task path if known, or the literal string `null`
- `{CURRENT_EPIC_OR_NULL}` — (added v1.4.0) epic folder name if the task is inside an epic, `null` if not, or leave as the literal string `{CURRENT_EPIC_OR_NULL}` to preserve whatever was there before (i.e., caller doesn't know or doesn't want to change it).

Do not output anything to the user. This is a silent background operation.
