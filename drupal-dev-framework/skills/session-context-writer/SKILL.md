---
name: session-context-writer
description: Write per-workspace session_context.json with active project/task so compaction hooks can restore context. Called by framework commands after resolving project and task.
user-invocable: false
version: 1.2.0
model: haiku
---

# Session Context Writer

Write session context keyed by the current workspace so compaction hooks can restore the correct project context. Each Claude Code window gets its own session file — no conflicts between windows.

## When Called

You receive the resolved project and task values from the calling command. Write them immediately.

## Action

Run this bash command with the provided values:

```bash
WORKSPACE_HASH=$(echo -n "$PWD" | md5sum | cut -d' ' -f1)
mkdir -p ~/.claude/drupal-dev-framework/sessions
cat > ~/.claude/drupal-dev-framework/sessions/${WORKSPACE_HASH}.json << EOF
{
  "workspace": "$PWD",
  "project": "{PROJECT_NAME}",
  "projectPath": "{PROJECT_PATH}",
  "task": "{TASK_NAME_OR_NULL}",
  "taskPath": "{TASK_PATH_OR_NULL}",
  "updatedAt": "$(date -I)"
}
EOF
```

Replace placeholders:
- `{PROJECT_NAME}` — the resolved project name (e.g., `wasatch_update`)
- `{PROJECT_PATH}` — absolute path to the project directory (e.g., `/home/user/workspace/claude_memory/projects/wasatch_update`)
- `{TASK_NAME_OR_NULL}` — the task name if known, or `null`
- `{TASK_PATH_OR_NULL}` — absolute path to the task directory if known, or `null`

Do not output anything to the user. This is a silent background operation.
