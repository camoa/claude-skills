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

When a command resolves which project and/or task the user is working on, **run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task|null>" "<task_path|null>" ["<currentEpic>"]`** (Bash) so compaction hooks can guide Claude to restore context from live project state files. (v4.16.0: a Bash call carries no model context, so the write never overflows a large session — the former `session-context-writer` skill remains as the documented contract.)

- Run after the user selects/confirms a project and task (not before)
- Pass `null` for task/taskPath if only the project is known
- On `/complete`, run with task set to `null` since the task moved to completed
- Omit the 5th arg (epic) to preserve the existing `currentEpic` (preserve-sentinel)
- Session context is per-workspace (keyed by `$PWD` hash) — multiple Claude windows don't conflict
- The pre/post-compact hooks read the workspace-specific session file to point Claude at the right `project_state.md`
