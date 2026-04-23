---
description: "Use when the user wants to convert a flat task into an epic folder with child sub-tasks — manual, one-task-at-a-time, transactional. Runs the 8-step migration via the epic-migrator skill. Flat tasks remain a valid permanent choice; this command is opt-in."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: <task-name> [--children "name1,name2,..."] [--dry-run]
---

# Migrate To Epic

Convert a single flat task into an epic folder containing child sub-tasks. Manual and explicit — this command is the atomic primitive for the hierarchy feature. For automated epic detection across many tasks, see `/propose-epics` (v3.11.0+), which calls this command under the hood when the user accepts a proposal.

## Usage

```
/drupal-dev-framework:migrate-to-epic <task-name>
/drupal-dev-framework:migrate-to-epic <task-name> --children "child_a,child_b,child_c"
/drupal-dev-framework:migrate-to-epic <task-name> --dry-run
/drupal-dev-framework:migrate-to-epic <task-name> --children "a,b" --dry-run
```

- `<task-name>` — the folder name of an existing flat task in `implementation_process/in_progress/`. Required.
- `--children "<list>"` — comma-separated child sub-task names. Optional; if omitted, the command prompts interactively. May be empty (creates an "epic shell" with no children yet).
- `--dry-run` — print the migration plan without executing. Safe to combine with `--children`.

## What this does

1. **Preflight** — validate the task exists, is not completed, is not already an epic, and no in-flight migration blocks the attempt.
2. **Resolve children** — use `--children` if provided; otherwise prompt the user interactively. Classify each child as `move_existing` (there's a peer folder with that name) or `create_stub` (a new subtask folder will be scaffolded).
3. **Build in temp** — construct the new epic structure under `.migration-tmp/<task>/`. Never touches the live folder.
4. **Validate** — run `task-frontmatter-reader` on every generated `task.md` in temp. Abort if any blocking warning surfaces.
5. **Atomic swap** — two-step rename (original → `.old-<task>`, then temp → live). Failure-recovers original on error.
6. **Cleanup scheduling** — `.old-<task>/` persists for 24 hours for manual rollback.
7. **Session context refresh** — update `session_context.json` to reflect the new epic via `session-context-writer` (sets `currentEpic` when appropriate).
8. **Report** — print the new structure + rollback instructions + suggested next command.

## Behavior

This command is a **thin orchestrator**. All file surgery lives in a real bash script (`${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh`) invoked via the `epic-migrator` skill. This command is responsible only for:

- Argument parsing and validation
- User interaction (interactive prompt when `--children` absent)
- Invoking the script (through the skill) with correctly-classified inputs
- Surfacing the script's output to the user
- Invoking `session-context-writer` with the case-analysis result the script emits on stderr

## Invocation steps

Follow these exactly:

1. **Parse arguments**:
   - First positional argument = `<task-name>`. If missing, ask the user.
   - `--children "<csv>"` — split on comma, trim whitespace per element, reject empty names and duplicates.
   - `--dry-run` — pass through to the skill.

2. **If `--children` not provided**, prompt interactively:
   > Promoting `<task-name>` to an epic.
   >
   > Enter child sub-task names (comma-separated). Existing peer folders with matching names will be MOVED into the new epic; unknown names will become empty subtask stubs.
   >
   > Leave blank to create an epic shell with no children yet.

3. **Invoke `epic-migrator` skill** (which calls `${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh`). The script takes positional arguments:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME" [--dry-run] [<child1> <child2> ...]
   ```

   Resolve `$PROJECT_PATH` from session context (`session_context.json` `projectPath`) or from `pwd` if no project is active. The script handles all file surgery; this command does not touch disk directly.

4. **If dry-run**, print the skill's plan output verbatim and stop.

5. **If live run**:
   - Relay the skill's step-by-step progress to the user
   - On success, print the summary the skill emits
   - On failure, print the skill's abort message and stop — the skill has already cleaned up any temp state

6. **Post-success**, parse the three `KEY=VALUE` lines the script emits on stderr:
   ```
   SESSION_CONTEXT_CASE=<A|B|C>
   EPIC_FOR_CTX=<value>           # literal string "{CURRENT_EPIC_OR_NULL}" for Case A; "null" for Case B; task_name for Case C
   NEW_TASK_PATH=<path or empty>  # non-empty only for Case C
   ```
   Invoke `session-context-writer` accordingly:
   - **Case A**: pass `{CURRENT_EPIC_OR_NULL}` literal → preserves existing `currentEpic`
   - **Case B**: pass `currentEpic=null`; keep `taskPath` unchanged
   - **Case C**: pass `currentEpic=<task_name>`; also update `taskPath` to `NEW_TASK_PATH`

7. **Suggest the next command**:
   - If the migrated epic has children: `/drupal-dev-framework:next` to continue with a child
   - If the migrated epic has no children (shell): `/drupal-dev-framework:migrate-to-epic <task> --children "..."` to add children, OR proceed with the epic's own phases

## Examples

### Interactive promotion with children

```
User: /drupal-dev-framework:migrate-to-epic my_big_task

Claude: Promoting `my_big_task` to an epic.

Enter child sub-task names (comma-separated):
> research_piece, implementation_piece, validation_piece

Invoking epic-migrator...
  [1/8] Preflight: OK
  [2/8] Children resolved: research_piece (create_stub), implementation_piece (create_stub), validation_piece (create_stub)
  [3/8] Built temp structure
  [4/8] Validation: all frontmatter parses cleanly
  [5/8] Atomic swap: OK
  [6/8] Rollback scheduled (.old-my_big_task/ for 24h)
  [7/8] Session context refreshed
  [8/8] Done.

my_big_task/
  task.md                  (kind: epic, children: 3)
  shared/
  research.md              (preserved)
  architecture.md          (preserved)
  research_piece/task.md   (kind: subtask, stub)
  implementation_piece/task.md
  validation_piece/task.md

Rollback available 24h at .migration-tmp/.old-my_big_task/
Next: /drupal-dev-framework:next
```

### Dry-run with an existing peer

```
User: /drupal-dev-framework:migrate-to-epic my_big_task --children "existing_peer,new_stub" --dry-run

Claude: PLAN (dry-run): /migrate-to-epic my_big_task
  Preflight: OK (flat, in_progress, no temp state)
  Children:
    existing_peer  → MOVE from peer location into the epic
    new_stub       → CREATE stub
  Would create epic folder with kind=epic, children=[local:existing_peer, local:new_stub]
  Would create shared/
  Would preserve phase artifacts: research.md (present), architecture.md (present), implementation.md (absent)
  Would move original aside to .migration-tmp/.old-my_big_task for 24h rollback
  Would update session context currentEpic if active task matches

No changes made. Re-run without --dry-run to execute.
```

### Promote to epic shell (no children yet)

```
User: /drupal-dev-framework:migrate-to-epic my_big_task --children ""

Claude: Invoking epic-migrator...
  [1/8] Preflight: OK
  [2/8] No children specified — creating epic shell
  [3-8] ...

my_big_task/
  task.md          (kind: epic, children: [])
  shared/
  research.md      (preserved)

Add children later with:
  /drupal-dev-framework:migrate-to-epic my_big_task --children "a,b,c"
  (will expand this epic with the new children)

Next: work on the epic's own phases, or add children when ready.
```

## What this command does NOT do

- **Does not propose which tasks should be epics.** That's `/drupal-dev-framework:propose-epics` (v3.11.0+).
- **Does not migrate multiple tasks at once.** One invocation = one task. Bulk review is a `/propose-epics` concern.
- **Does not migrate completed tasks.** Preflight refuses.
- **Does not promote a subtask to a sub_epic.** That's a different flow (candidate for a later command). Today, sub-epics are created by running this command on a task whose parent is already an epic — which the preflight currently refuses. If you need nested decomposition, contact the framework maintainers (mechanism pending).
- **Does not cross project boundaries.** A task in project A cannot have children in project B.

## Errors and how to resolve

| Error | Resolution |
|---|---|
| `task folder not found` | Check the spelling of `<task-name>`; it must match an in-progress folder name exactly. |
| `task already in completed/` | Cannot migrate completed tasks. Move the folder back to `in_progress/` manually if you really need to. |
| `task is already an epic (kind=epic)` | The task is already an epic. Add children via re-running this command (expansion flow — see examples above). |
| `task is a subtask of another epic` | Cannot promote subtasks directly. Detach the task from its parent first (manual: edit the parent's `task.md` frontmatter `children[]` to remove this task, then re-run). |
| `a prior migration's rollback directory exists` | A previous migration left `.migration-tmp/.old-<task>/`. Either the rollback window is still open (use it, or delete it manually), or a previous migration crashed mid-run. Resolve the temp state before retrying. |
| `generated task.md has blocking warnings` | Schema-level problem with how the migration was assembled. Check the warning detail; usually indicates a malformed child name. |

## Related commands

- `/drupal-dev-framework:status` — shows the new tree view after migration
- `/drupal-dev-framework:next` — honors the new parent/child relationship when suggesting next action
- `/drupal-dev-framework:complete` — epic completion awareness
- `/drupal-dev-framework:propose-epics` (v3.11.0+) — calls this command under the hood when the user accepts an agent's proposal
