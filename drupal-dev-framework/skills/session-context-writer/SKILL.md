---
name: session-context-writer
description: Write session_context.json with active project/task so compaction hooks can restore context. Called by framework commands after resolving project and task.
user-invocable: false
version: 1.0.0
model: haiku
---

# Session Context Writer

Write the active project and task to `~/.claude/drupal-dev-framework/session_context.json` so that compaction hooks can guide Claude to restore context from live project state files.

## When Called

You receive the resolved project and task values from the calling command. Write them immediately.

## Action

Run this bash command with the provided values:

```bash
mkdir -p ~/.claude/drupal-dev-framework
cat > ~/.claude/drupal-dev-framework/session_context.json << EOF
{
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
- `{TASK_NAME_OR_NULL}` — the task name if known, or `null` if only project is resolved
- `{TASK_PATH_OR_NULL}` — absolute path to the task directory if known, or `null`

Do not output anything to the user. This is a silent background operation.
