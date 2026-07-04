---
description: "Use when the user wants to convert a flat task into an epic folder with child sub-tasks — manual, one-task-at-a-time, transactional. Runs the 8-step migration via scripts/migrate-to-epic.sh. Flat tasks remain a valid permanent choice; this command is opt-in."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: <task-name> [--children "name1,name2,..."] [--dry-run]
---

# Migrate To Epic

Convert a single flat task into an epic folder containing child sub-tasks. Manual and explicit — this command is the atomic primitive for the hierarchy feature. For automated epic detection across many tasks, see `/propose-epics` (v3.11.0+), which calls this command under the hood when the user accepts a proposal.

## Usage

```
/ai-dev-assistant:migrate-to-epic <task-name>
/ai-dev-assistant:migrate-to-epic <task-name> --children "child_a,child_b,child_c"
/ai-dev-assistant:migrate-to-epic <task-name> --dry-run
/ai-dev-assistant:migrate-to-epic <task-name> --children "a,b" --dry-run
```

- `<task-name>` — the folder name of an existing flat task in `implementation_process/in_progress/`. Required.
- `--children "<list>"` — comma-separated child sub-task names. Optional; if omitted, the command prompts interactively. May be empty (creates an "epic shell" with no children yet).
- `--dry-run` — print the migration plan without executing. Safe to combine with `--children`.

## What this does

1. **Preflight** — validate the task exists, is not completed, and no in-flight migration blocks the attempt. If the task is **already** an epic/sub_epic: with `--children` it enters **expansion mode** (the new children are added to the existing epic; existing children and artifacts are preserved); with no children it is a no-op that prints how to expand.
2. **Resolve children** — use `--children` if provided; otherwise prompt the user interactively. Classify each child as `move_existing` (there's a peer folder with that name), `already_completed` (a peer folder in `completed/`), or `create_stub` (a new subtask folder will be scaffolded). In expansion mode, every new child name must be genuinely new — collisions with the epic's existing `children[]` or its `in_progress/` / `completed/` folders are rejected at preflight.
3. **Build in temp** — construct the new epic structure under `.migration-tmp/<task>/`. Never touches the live folder.
4. **Validate** — the script validates every generated `task.md` in temp via `fm_read` (from `fm-helpers.sh`). Abort if any blocking warning surfaces.
5. **Atomic swap** — two-step rename (original → `.old-<task>`, then temp → live). Failure-recovers original on error.
6. **Cleanup scheduling** — `.old-<task>/` persists for 24 hours for manual rollback.
7. **Session context refresh** — update `session_context.json` to reflect the new epic via `scripts/session-context-write.sh` (sets `currentEpic` when appropriate).
8. **Report** — print the new structure + rollback instructions + suggested next command.

## Behavior

This command is a **thin orchestrator**. All file surgery lives in a real bash script (`${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh`), invoked directly via Bash (v4.16.0 — was previously routed through the `epic-migrator` skill; a Bash call carries no model context, so it can't overflow a large session). This command is responsible only for:

- Argument parsing and validation
- User interaction (interactive prompt when `--children` absent)
- Invoking the script (Bash, directly) with correctly-classified inputs
- Surfacing the script's output to the user
- Running `scripts/session-context-write.sh` with the case-analysis result the script emits on stderr

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

3. **Run `${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh` directly** (Bash). The script takes positional arguments:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-to-epic.sh" "$PROJECT_PATH" "$TASK_NAME" [--dry-run] [<child1> <child2> ...]
   ```

   Resolve `$PROJECT_PATH` by running `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-read.sh` (Bash) and parsing its JSON `.projectPath`, or from `pwd` if no project is active. The script handles all file surgery; this command does not touch disk directly.

4. **If dry-run**, print the script's plan output verbatim and stop.

5. **If live run**:
   - Relay the script's step-by-step progress to the user
   - On success, print the summary the script emits
   - On failure, print the script's abort message and stop — the script has already cleaned up any temp state

6. **Post-success**, parse the three `KEY=VALUE` lines the script emits on stderr:
   ```
   SESSION_CONTEXT_CASE=<A|B|C>
   EPIC_FOR_CTX=<value>           # literal string "{CURRENT_EPIC_OR_NULL}" for Case A; "null" for Case B; task_name for Case C
   NEW_TASK_PATH=<path or empty>  # non-empty only for Case C
   ```
   Run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task>" "<task_path>" "<epic_arg>"` (Bash) accordingly — the 5th positional `<epic_arg>` and the 4th `<task_path>` vary by case:
   - **Case A**: omit the 5th arg (or pass the literal `{CURRENT_EPIC_OR_NULL}`) → preserves existing `currentEpic`; `<task_path>` unchanged
   - **Case B**: pass `null` as the 5th arg → clears `currentEpic`; `<task_path>` unchanged
   - **Case C**: pass `$EPIC_FOR_CTX` (= `<task_name>`) as the 5th arg → sets `currentEpic`; set `<task_path>` to `$NEW_TASK_PATH`

7. **Suggest the next command**:
   - If the migrated epic has children: `/ai-dev-assistant:next` to continue with a child
   - If the migrated epic has no children (shell): `/ai-dev-assistant:migrate-to-epic <task> --children "..."` to add children, OR proceed with the epic's own phases

## Examples

### Interactive promotion with children

```
User: /ai-dev-assistant:migrate-to-epic my_big_task

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
Next: /ai-dev-assistant:next
```

### Dry-run with an existing peer

```
User: /ai-dev-assistant:migrate-to-epic my_big_task --children "existing_peer,new_stub" --dry-run

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

### Promote a subtask to a sub_epic (v4.4.0+)

```
User: /ai-dev-assistant:migrate-to-epic auth_subtask --children "token_logic,session_storage"

Claude: Promoting `auth_subtask` to a sub_epic.

Preflight detected nested location:
  parent epic: user_management_epic
  subtask:     auth_subtask

Invoking epic-migrator...
  [1/8] Preflight: OK — kind=subtask parent kind=epic
  [2/8] Children resolved (looking under parent epic):
        token_logic     → MOVE from parent's in_progress/
        session_storage → CREATE stub
  [3/8] Built temp structure (sub_epic frontmatter: kind=sub_epic, parent=local:user_management_epic)
  [4/8] Validation: all frontmatter parses cleanly
  [5/8] Atomic swap: OK
  [6/8] Rollback scheduled (.migration-tmp/.old-auth_subtask/ for 24h)
  [7/8] Session context refreshed
  [8/8] Done.

user_management_epic/
  task.md                                (unchanged — still lists auth_subtask in children[])
  in_progress/
    auth_subtask/                        (kind: sub_epic — was: subtask)
      task.md
      in_progress/
        token_logic/task.md              (kind: subtask, parent: local:auth_subtask)
        session_storage/task.md          (stub)

Note: max nesting depth is 2. Cannot promote `token_logic` or `session_storage` further —
preflight will refuse with "parent is already a sub_epic".

Rollback available 24h at .migration-tmp/.old-auth_subtask/
Next: /ai-dev-assistant:next
```

### Promote to epic shell (no children yet)

```
User: /ai-dev-assistant:migrate-to-epic my_big_task --children ""

Claude: Invoking epic-migrator...
  [1/8] Preflight: OK
  [2/8] No children specified — creating epic shell
  [3-8] ...

my_big_task/
  task.md          (kind: epic, children: [])
  shared/
  research.md      (preserved)

Add children later with:
  /ai-dev-assistant:migrate-to-epic my_big_task --children "a,b,c"
  (will expand this epic with the new children)

Next: work on the epic's own phases, or add children when ready.
```

### Expand an existing epic (v4.10.0+)

```
User: /ai-dev-assistant:migrate-to-epic my_big_task --children "a_sixth_child"

Claude: `my_big_task` is already an epic — entering expansion mode.

Invoking epic-migrator...
  [1/8] Preflight: OK — kind=epic status=in_progress children=1 (expansion — adding to existing epic)
  [2/8] Classify children: a_sixth_child (create_stub)
  [3/8] Built temp structure (whole epic copied; merged children[] = existing + new)
  [4/8] Validation: all frontmatter parses cleanly
  [5/8] Atomic swap: OK
  [6/8] Rollback scheduled (.migration-tmp/.old-my_big_task/ for 24h)
  [7/8] Session context refreshed
  [8/8] Done.

Expanded epic my_big_task with 1 new child(ren); 5 existing child(ren) preserved.

Rollback available 24h at .migration-tmp/.old-my_big_task/
Next: /ai-dev-assistant:next
```

Running with no children on an epic is a no-op:

```
User: /ai-dev-assistant:migrate-to-epic my_big_task

Claude: Nothing to do: `my_big_task` is already an epic (kind=epic).
Pass child names (--children "<name> …") to expand it.
```

## What this command does NOT do

- **Does not propose which tasks should be epics.** That's `/ai-dev-assistant:propose-epics` (v3.11.0+).
- **Does not migrate multiple tasks at once.** One invocation = one task. Bulk review is a `/propose-epics` concern.
- **Does not migrate completed tasks.** Preflight refuses.
- **Does promote a subtask to a sub_epic** (v4.4.0+). Running this command on a subtask inside an epic creates the second and final nesting level: the subtask becomes `kind: sub_epic` with its own `in_progress/` and `completed/` subfolders for grandchildren. The parent epic's frontmatter is unchanged (it still lists the promoted task in its `children[]`; only the kind shifts). Refused when the parent is already a `sub_epic` — max nesting depth is 2. The classifier looks for peer subtasks under the parent epic's `in_progress/` and `completed/` (not project-level) when resolving `move_existing` / `already_completed` children.
- **Does not cross project boundaries.** A task in project A cannot have children in project B.

## Errors and how to resolve

| Error | Resolution |
|---|---|
| `task folder not found` | Check the spelling of `<task-name>`; it must match an in-progress folder name exactly. |
| `task already in completed/` | Cannot migrate completed tasks. Move the folder back to `in_progress/` manually if you really need to. |
| `Nothing to do: '<task>' is already an epic` | The task is already an epic/sub_epic and you passed no children. Re-run with `--children "..."` to expand it. |
| `child '<name>' is already in epic '<task>' children[]` | Expansion mode rejects re-adding an existing child. Pick names not already in the epic. |
| `child '<name>' already exists as a folder inside epic '<task>'` | A folder of that name already lives in the epic's `in_progress/` or `completed/`. Pick a new name. |
| `parent '<name>' is already a sub_epic — sub-sub-epics are not allowed (max nesting depth = 2)` | The subtask you're trying to promote lives inside a sub_epic; the framework allows only one level of nesting. Re-decompose at the top of the tree (split work into a peer epic instead). |
| `ambiguous task name '<name>'` | The subtask name exists under multiple parent epics. Run from inside the parent epic's folder, or rename one of the subtasks so the name is unique under `in_progress/`. |
| `task at top-level has kind=subtask — frontmatter inconsistent with location` | The task lives at project-level but its frontmatter says `kind: subtask`. Edit the frontmatter to `kind: flat` (or move the folder under its parent epic) and retry. |
| `task at nested path has kind=flat — frontmatter inconsistent with location` | The task lives inside an epic but its frontmatter says `kind: flat`. Edit the frontmatter to `kind: subtask` (or move the folder to project-level) and retry. |
| `a prior migration's rollback directory exists` | A previous migration left `.migration-tmp/.old-<task>/`. Either the rollback window is still open (use it, or delete it manually), or a previous migration crashed mid-run. Resolve the temp state before retrying. |
| `generated task.md has blocking warnings` | Schema-level problem with how the migration was assembled. Check the warning detail; usually indicates a malformed child name. |

## Related commands

- `/ai-dev-assistant:status` — shows the new tree view after migration
- `/ai-dev-assistant:next` — honors the new parent/child relationship when suggesting next action
- `/ai-dev-assistant:complete` — epic completion awareness
- `/ai-dev-assistant:propose-epics` (v3.11.0+) — calls this command under the hood when the user accepts an agent's proposal
