---
name: epic-migrator
description: Use when converting a flat task into an epic folder with children. Runs the 8-step transactional migration via scripts/migrate-to-epic.sh. Supports --dry-run for preflight plan. Never leaves half-migrated state on disk.
version: 2.0.1
user-invocable: false
model: sonnet
allowed-tools: Bash, Skill
---

# Epic Migrator

Thin wrapper around `${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh`. The script implements transactional migration; this skill exists to be callable-via-Skill and to spell out the invocation contract + session-context handoff.

## Contract

**Input (CLI args to the script):**
- `<project_path>` — absolute project path
- `<task_name>` — flat task folder to promote
- `[--dry-run]` — prints plan, changes nothing
- `[<child1> <child2> ...]` — zero or more child names

**Output:**
- Stdout: step-by-step log ending with a structure summary
- Stderr on live-run success: three `KEY=VALUE` lines — `SESSION_CONTEXT_CASE`, `EPIC_FOR_CTX`, `NEW_TASK_PATH`

**Exit codes:**
- `0` success (live or dry-run)
- `1` abort (preflight/validation/mid-migration error — nothing committed)
- `2` usage error (missing required arg)

## Invocation

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME" --dry-run child_a child_b
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME" child_a child_b
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME"
```

## Session-context dispatch (apply after live run)

Parse the stderr `KEY=VALUE` lines, then invoke `session-context-writer`:

| Case | When | `currentEpic` arg | `taskPath` arg |
|---|---|---|---|
| **A** | Migrated task != active task | literal `{CURRENT_EPIC_OR_NULL}` (preserve) | unchanged |
| **B** | Migrated task == active task | `"null"` (clear) | unchanged |
| **C** | A `move_existing` child == active task | `$TASK_NAME` (set epic) | `$NEW_TASK_PATH` |

## See also

- `${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh` — the script (header comments document invariants, preflight rejections, and architectural rationale)
- `${CLAUDE_PLUGIN_ROOT}/scripts/fm-helpers.sh` — shared helpers
- `task-frontmatter-reader` skill — wraps fm-read.sh
- `/drupal-dev-framework:migrate-to-epic` command — user orchestrator

## Do NOT

- Do not duplicate the migration logic in another skill. Call this skill (which calls the script).
- Do not modify the script's exit-code contract without updating consumers.
- Do not use `git mv` — task folders are NOT in git (framework memory).
