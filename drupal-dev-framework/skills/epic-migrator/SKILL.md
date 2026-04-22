---
name: epic-migrator
description: Use when converting a flat task into an epic folder with children. Runs the 8-step transactional migration — preflight, classify children, build in temp, validate, atomic swap, cleanup, session-context-hint, report. Delegates to scripts/migrate-to-epic.sh for the actual file surgery. Never leaves half-migrated state on disk.
version: 2.0.0
user-invocable: false
model: sonnet
allowed-tools: Bash, Skill
---

# Epic Migrator

Thin wrapper around the real script `${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh`. The script executes the 8-step transactional migration deterministically; this skill exists to give it a callable-via-Skill name and to document contract, invariants, and the session-context handoff.

## Contract

**Input (passed as CLI args to the script):**
- `<project_path>` — absolute path to the project root (`.../claude_memory/projects/<name>/`)
- `<task_name>` — the flat task folder to promote
- `[--dry-run]` — optional flag; prints the plan without making changes
- `[<child1> <child2> ...]` — zero or more child names (may be empty for epic shell)

**Output:**
- Stdout: step-by-step log (`[1/8] Preflight — OK`, etc.) ending with a structure summary
- Stderr (after live-run success): three `KEY=VALUE` lines — `SESSION_CONTEXT_CASE`, `EPIC_FOR_CTX`, `NEW_TASK_PATH`. Caller parses these to invoke `session-context-writer` correctly.

**Exit codes:**
- `0` — success (live run) or plan printed (dry-run)
- `1` — abort (preflight failed, validation failed, or mid-migration error; transactional guarantee means nothing was committed)
- `2` — usage error (missing required arguments)

## Invocation

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME" --dry-run child_a child_b
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME" child_a child_b
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME"   # epic shell (no children)
```

After a live run, **parse the stderr session-context hints** and invoke `session-context-writer` per the three cases:

- **Case A** (`SESSION_CONTEXT_CASE=A`): migrated task is NOT the active task. Pass the literal `{CURRENT_EPIC_OR_NULL}` to the writer — preserves existing `currentEpic`.
- **Case B** (`SESSION_CONTEXT_CASE=B`): the migrated task IS the active task. Pass `currentEpic=null` to the writer. Keep `taskPath` unchanged.
- **Case C** (`SESSION_CONTEXT_CASE=C`): a moved-existing child was the active task. Pass `currentEpic=$TASK_NAME` to the writer, AND update `taskPath` to `$NEW_TASK_PATH` (the new nested location).

## Invariants the script upholds

1. **Atomicity.** At any observable moment, the filesystem is either pre-migration or post-migration state; never partial. Abort before the atomic swap rolls back cleanly.
2. **24h rollback window.** The `.old-<task>/` directory persists at `$TEMP_ROOT/.old-<task>/` with a `.migration-completed-at` timestamp marker. Manual `rm -rf` to claim the space back.
3. **Read-before-write.** Step 4 validates every generated `task.md` via `fm_read` (sourced from `fm-helpers.sh`). Blocking warnings abort the migration before the atomic swap, leaving temp cleaned up.
4. **No silent overwrites.** Atomic `mkdir "$TEMP_ROOT/$TASK_NAME"` (without `-p`) fails fast if a concurrent migration is in flight. Protects against same-task races in the same project.
5. **Deterministic children classification.** `move_existing` iff folder exists at peer location; `create_stub` iff folder does not exist. No judgment calls.
6. **Status preservation.** Epic inherits the original task's `status`. `move_existing` children keep their own pre-migration status. `create_stub` children start at `draft`.
7. **Canonical frontmatter.** All frontmatter emitted via `yaml.safe_dump(..., sort_keys=False)` — byte-deterministic across invocations.

## Preflight rejections (script aborts with exit 1)

- Task folder not found
- `task.md` missing inside the folder
- Task already in `completed/`
- Task is already an epic or sub_epic
- Task is a subtask of another epic
- In-flight migration exists at `$TEMP_ROOT/<task>` or `.old-<task>`
- Any child name equals the task name
- Duplicate child names

## Why this is a script, not embedded instructions

Earlier drafts of this skill embedded the migration logic as bash pseudo-code with undefined helper-function references. A paper-test (2026-04-22) flagged BLOCKERS: `CHILDREN_CLASSIFIED` never assigned, four pseudo-functions without implementations, ambiguous delete targets, a zsh-specific colon-parsing bug. The script-based design closes all of these: the script is a single file that runs deterministically, tests cleanly, and cannot drift across invocations.

## See also

- `${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh` — the script this skill wraps
- `${CLAUDE_PLUGIN_ROOT}/scripts/fm-helpers.sh` — shared helpers (sourced by both scripts)
- `task-frontmatter-reader` skill — wraps the fm-read.sh entry point
- `/drupal-dev-framework:migrate-to-epic` command — user-facing orchestrator
- Architecture decision 3.1-D2 in `dev_framework_task_hierarchy_foundation/architecture.md`

## Do NOT

- Do not duplicate the migration logic in another skill. If a new flow needs migration behavior, call this skill (which calls the script).
- Do not modify the script's exit-code contract without updating this skill's consumers.
- Do not use `git mv` anywhere in this flow — task folders are NOT in git (framework memory).
