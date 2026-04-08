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

When a command resolves which project and/or task the user is working on, **invoke the `session-context-writer` skill** so compaction hooks can guide Claude to restore context from live project state files.

- Invoke after the user selects/confirms a project and task (not before)
- Pass `null` for task/taskPath if only the project is known
- On `/complete`, invoke with task set to `null` since the task moved to completed
- Session context is per-workspace (keyed by `$PWD` hash) — multiple Claude windows don't conflict
- The pre/post-compact hooks read the workspace-specific session file to point Claude at the right `project_state.md`
