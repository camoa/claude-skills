---
name: epic-migrator
description: Use when converting a flat task into an epic folder with children, promoting a subtask to a sub_epic, or expanding an existing epic with more children. Runs the 8-step transactional migration via scripts/migrate-to-epic.sh. Supports --dry-run for preflight plan. Never leaves half-migrated state on disk.
version: 2.2.0
user-invocable: false
model: inherit
allowed-tools: Bash
---

# Epic Migrator

Thin wrapper around `${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh`. The script implements transactional migration; this skill exists to be callable-via-Skill and to spell out the invocation contract + session-context handoff.

## Contract

**Input (CLI args to the script):**
- `<project_path>` — absolute project path
- `<task_name>` — the task folder to operate on. The script picks the operation by where the name resolves and its current `kind`:
  - flat task at project level → **flat → epic** promotion
  - subtask nested inside an epic → **subtask → sub_epic** promotion
  - already an epic/sub_epic + child names passed → **epic expansion** (adds children to the existing epic, preserving existing children + artifacts)
  - already an epic/sub_epic + no child names → no-op (exit 1 with a "pass children to expand" hint)
- `[--dry-run]` — prints plan, changes nothing
- `[<child1> <child2> ...]` — zero or more child names

**Output:**
- Stdout: step-by-step log ending with a structure summary
- Stderr on live-run success: three `KEY=VALUE` lines — `SESSION_CONTEXT_CASE`, `EPIC_FOR_CTX`, `NEW_TASK_PATH`

**Exit codes:**
- `0` success (live or dry-run)
- `1` abort (preflight/validation/mid-migration error — nothing committed) OR no-op (epic with no children to add)
- `2` usage error (missing required arg)

## Invocation

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME" --dry-run child_a child_b
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME" child_a child_b
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME"
```

## Session-context dispatch (apply after live run)

Parse the stderr `KEY=VALUE` lines (`SESSION_CONTEXT_CASE`, `EPIC_FOR_CTX`, `NEW_TASK_PATH`), then write session context by running `scripts/session-context-write.sh` directly (Bash, zero model context — v4.16.0):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh" \
  "$PROJECT_NAME" "$PROJECT_PATH" "$TASK" "$TASK_PATH" "$EPIC_ARG"
```

Choose the `$EPIC_ARG` (5th positional) and `$TASK_PATH` by the case the script emitted:

| Case | When | `$EPIC_ARG` (5th arg) | `$TASK_PATH` (4th arg) |
|---|---|---|---|
| **A** | Migrated task != active task | literal `{CURRENT_EPIC_OR_NULL}` (preserve) | unchanged |
| **B** | Migrated task == active task | `null` (clear) | unchanged |
| **C** | A `move_existing` child == active task | `$EPIC_FOR_CTX` (= `$TASK_NAME`, set epic) | `$NEW_TASK_PATH` |

## See also

- `${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh` — the script (header comments document invariants, preflight rejections, and architectural rationale)
- `${CLAUDE_PLUGIN_ROOT}/scripts/fm-helpers.sh` — shared helpers
- `task-frontmatter-reader` skill — wraps fm-read.sh
- `/ai-dev-assistant:migrate-to-epic` command — user orchestrator

## Do NOT

- Do not duplicate the migration logic in another skill. Call this skill (which calls the script).
- Do not modify the script's exit-code contract without updating consumers.
- Do not use `git mv` — task folders are NOT in git (framework memory).
