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

## Checkpoint Frontmatter (v3.9.0+)

New tasks use a `checkpoints` key in task.md frontmatter to track phase progress. Canonical IDs and entry conditions live in `references/checkpoint-catalog.md`.

```yaml
---
task: <task_name>
phase: 1
checkpoints:
  phase_1:
    - {id: "1.1", status: done, evidence: "research.md#constraints"}
    - {id: "1.2", status: in_progress}
    - {id: "1.5", status: skipped, justification: "meta-task, no Drupal core applies"}
  phase_2: []
  phase_3: []
---
```

- Status values: `pending`, `in_progress`, `done`, `skipped` (skipped requires `justification`)
- `/design` and `/implement` invoke the `checkpoint-gate` skill at start to enforce phase entry
- `/step` command reads this schema to show current state and next action
- Tasks without `checkpoints` key fall through to legacy Phase Status checklist (backward compatible)
