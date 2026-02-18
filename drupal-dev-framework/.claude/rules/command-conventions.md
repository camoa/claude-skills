---
paths:
  - "commands/**"
---

# Command Conventions

## Required Frontmatter
- `description` — what the command does, concise
- `allowed-tools` — restrict to minimum needed

## Optional Frontmatter
- `argument-hint` — shown during autocomplete (e.g., `<task-name>`)

## Body Rules
- Clear instructions for what Claude should do when command is invoked
- Support `$ARGUMENTS` for user-provided arguments
- Reference skills/agents for complex workflows rather than inlining logic

## Session Context Tracking

When a command resolves which project and/or task the user is working on, **write the session context file** so it survives context compaction:

```bash
mkdir -p ~/.claude/drupal-dev-framework
cat > ~/.claude/drupal-dev-framework/session_context.json << EOF
{
  "project": "{project_name}",
  "projectPath": "{project_path}",
  "task": "{task_name_or_null}",
  "taskPath": "{task_path_or_null}",
  "updatedAt": "$(date -I)"
}
EOF
```

- Write after the user selects/confirms a project and task (not before)
- Set `task` and `taskPath` to `null` if only the project is known
- On `/complete`, clear `task` and `taskPath` (set to `null`) since the task moved to completed
- The pre-compact hook reads this file to inject accurate context into the compacted prompt
