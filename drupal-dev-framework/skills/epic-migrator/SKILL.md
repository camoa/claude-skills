---
name: epic-migrator
description: Use when converting a flat task into an epic folder with children. Runs the 8-step transactional migration — preflight, gather children, build in temp, validate, atomic swap, cleanup, register, report. Isolates file surgery so the /migrate-to-epic command body stays thin. Never leaves half-migrated state on disk.
version: 1.0.0
user-invocable: false
model: sonnet
allowed-tools: Read, Write, Edit, Bash, Glob
---

# Epic Migrator

Transform a flat task into an epic folder structure, or expand an epic to include new children. Operate transactionally: either the migration fully succeeds or the disk is left exactly as it was found.

## When Called

The `/drupal-dev-framework:migrate-to-epic` command invokes you with:
- `task_name` — the flat task folder to promote (or the existing epic to expand)
- `children` — comma-separated list of child sub-task names (or empty for epic shell)
- `dry_run` — if `true`, print the plan without executing
- `project_path` — absolute path to the project root (`.../claude_memory/projects/<name>/`)

## The 8 Steps (execute in order; abort on any failure)

### 1. Preflight

Verify all invariants. If any fail, abort with a clear message — do not touch disk.

```bash
TASK_DIR="$PROJECT_PATH/implementation_process/in_progress/$TASK_NAME"
TASK_MD="$TASK_DIR/task.md"
COMPLETED_DIR="$PROJECT_PATH/implementation_process/completed/$TASK_NAME"
TEMP_ROOT="$PROJECT_PATH/implementation_process/in_progress/.migration-tmp"

# Must exist
[ -d "$TASK_DIR" ] || abort "task folder not found: $TASK_DIR"
[ -f "$TASK_MD" ] || abort "task.md not found in folder"

# Must not be completed
[ ! -d "$COMPLETED_DIR" ] || abort "task already in completed/; cannot migrate"

# Must not already be an epic (read via task-frontmatter-reader)
READER_OUTPUT=$(invoke_task_frontmatter_reader "$TASK_DIR")
CURRENT_KIND=$(jq -r '.kind' <<<"$READER_OUTPUT")
case "$CURRENT_KIND" in
  flat) : ;;
  epic|sub_epic) abort "task is already an epic (kind=$CURRENT_KIND); use a different flow to add children" ;;
  subtask) abort "task is a subtask of another epic; cannot promote" ;;
  *) abort "task has unknown kind: $CURRENT_KIND" ;;
esac

# Must have no in-flight migration for this task
[ ! -d "$TEMP_ROOT/$TASK_NAME" ] || abort "a prior migration for this task is in temp; resolve manually"
[ ! -d "$TEMP_ROOT/.old-$TASK_NAME" ] || abort "a prior migration's rollback directory exists; resolve manually"
```

### 2. Gather children

If the caller passed `children`, use that list. Otherwise, prompt the user interactively:

```
Enter child sub-task names (comma-separated, or blank for empty epic):
```

Parse, validate each name:
- Must be a valid folder name (kebab_case recommended; alphanumeric + underscore + hyphen)
- No duplicates
- A child name may match an existing in-progress peer folder (in which case it will be MOVED into the epic) OR be a new name (in which case a stub folder is created)

Classify each child as `move_existing` or `create_stub`:

```bash
for child in "${CHILDREN[@]}"; do
  if [ -d "$PROJECT_PATH/implementation_process/in_progress/$child" ]; then
    echo "$child:move_existing"
  else
    echo "$child:create_stub"
  fi
done
```

### 3. Build in temp

Create everything under `$TEMP_ROOT/$TASK_NAME/`. Nothing is moved into the final location yet.

```bash
mkdir -p "$TEMP_ROOT/$TASK_NAME"
mkdir -p "$TEMP_ROOT/$TASK_NAME/shared"

# Copy (not move) the original task.md to temp; we'll edit it there
cp "$TASK_MD" "$TEMP_ROOT/$TASK_NAME/task.md"

# Prepend / overwrite frontmatter block to make it kind: epic
update_frontmatter_to_epic "$TEMP_ROOT/$TASK_NAME/task.md" "$TASK_NAME" "${CHILDREN[@]}"

# Copy phase artifacts if they exist
for artifact in research.md architecture.md implementation.md; do
  if [ -f "$TASK_DIR/$artifact" ]; then
    cp "$TASK_DIR/$artifact" "$TEMP_ROOT/$TASK_NAME/$artifact"
  fi
done

# Create child folders in temp
for child_spec in "${CHILDREN_CLASSIFIED[@]}"; do
  child="${child_spec%:*}"
  kind="${child_spec#*:}"
  case "$kind" in
    move_existing)
      cp -r "$PROJECT_PATH/implementation_process/in_progress/$child" "$TEMP_ROOT/$TASK_NAME/$child"
      # Upgrade the child's task.md to add parent frontmatter (or rewrite if it already had frontmatter)
      update_frontmatter_to_subtask "$TEMP_ROOT/$TASK_NAME/$child/task.md" "$child" "$TASK_NAME"
      ;;
    create_stub)
      mkdir -p "$TEMP_ROOT/$TASK_NAME/$child"
      write_stub_task_md "$TEMP_ROOT/$TASK_NAME/$child/task.md" "$child" "$TASK_NAME"
      ;;
  esac
done
```

**Frontmatter writers** (helper functions — implement inline via `awk`/`sed` or a small Python helper):

- `update_frontmatter_to_epic(file, task_name, children)` — insert or replace the `---` block at line 1 with `id: local:<task>`, `kind: epic`, `parent: null`, `children: [local:<c1>, ...]`, `blocks: []`, `blocked_by: []`, `external_ids: {}`, `status: in_progress`.
- `update_frontmatter_to_subtask(file, child_name, parent_name)` — same shape but `kind: subtask`, `parent: local:<parent>`, `children: null`. Preserves any existing body after the frontmatter block.
- `write_stub_task_md(file, child_name, parent_name)` — create a minimal `task.md` using the framework's new-task template + subtask frontmatter. Body includes `## Goal`, `## Phase Status` (all `[ ]`), placeholder.

### 4. Validate temp

Run `task-frontmatter-reader` on every generated `task.md` in temp. All must parse without `warnings[]` entries of severity higher than informational (`unknown_fields` is acceptable; `malformed_yaml`, `wrong_type`, `orphaned_subtask` are aborting).

```bash
for generated in "$TEMP_ROOT/$TASK_NAME/task.md" "$TEMP_ROOT/$TASK_NAME"/*/task.md; do
  OUTPUT=$(invoke_task_frontmatter_reader "$(dirname "$generated")")
  BLOCKING_WARNINGS=$(jq '[.warnings[] | select(.code == "malformed_yaml" or .code == "wrong_type" or .code == "orphaned_subtask")] | length' <<<"$OUTPUT")
  if [ "$BLOCKING_WARNINGS" -gt 0 ]; then
    abort "generated task.md has blocking warnings: $(jq '.warnings' <<<"$OUTPUT") — migration unsafe, aborting before swap"
  fi
done
```

If any file fails validation, delete `$TEMP_ROOT/$TASK_NAME/` and abort. Original untouched.

### 5. Atomic swap

Two renames. The original is moved to a backup location FIRST so if the second rename fails, we can restore.

```bash
# Move original aside
mv "$TASK_DIR" "$TEMP_ROOT/.old-$TASK_NAME" \
  || abort "failed to move original aside — nothing changed"

# Move new into place
mv "$TEMP_ROOT/$TASK_NAME" "$TASK_DIR" || {
  # Restore original; delete temp
  mv "$TEMP_ROOT/.old-$TASK_NAME" "$TASK_DIR"
  abort "failed to move new structure into place; restored original"
}

# For every child that was move_existing, remove the original peer folder now that it's inside the epic
for child_spec in "${CHILDREN_CLASSIFIED[@]}"; do
  child="${child_spec%:*}"
  kind="${child_spec#*:}"
  if [ "$kind" = "move_existing" ]; then
    rm -rf "$PROJECT_PATH/implementation_process/in_progress/$child"
  fi
done
```

### 6. Cleanup

Schedule the rollback directory for deletion after 24 hours. Simplest: leave `.old-$TASK_NAME` on disk with a marker file; a separate cleanup invocation (or the next `/migrate-to-epic` call for a DIFFERENT task) can garbage-collect. For now, just record a timestamp and move on.

```bash
date -Iseconds > "$TEMP_ROOT/.old-$TASK_NAME/.migration-completed-at"
```

Document in the user-facing output that `.old-$TASK_NAME` exists for 24h rollback and can be deleted manually with `rm -rf "$TEMP_ROOT/.old-$TASK_NAME"`.

### 7. Register

Update session context to reflect the new epic containment (if the migrated task is the active task, set `currentEpic` accordingly). Invoke `session-context-writer` with the appropriate `{CURRENT_EPIC_OR_NULL}` value.

### 8. Report

Emit a summary to the user:

```
Migrated <task_name> to epic with N children.

<task_name>/
  task.md          (kind: epic, children: [...])
  shared/          (empty — add cross-cutting docs here)
  research.md      (preserved)
  architecture.md  (preserved)
  implementation.md (preserved)
  <child1>/task.md (kind: subtask, moved from peer)
  <child2>/task.md (kind: subtask, stub created)
  ...

Rollback available for 24h at:
  <project>/implementation_process/in_progress/.migration-tmp/.old-<task_name>/

Delete rollback early with: rm -rf <that path>

Next: /drupal-dev-framework:next — continue with a child.
```

## Dry-run mode

If `dry_run=true`, execute Step 1 (preflight) and Step 2 (gather children), then print the PLAN without executing Steps 3–8. Plan output:

```
PLAN (dry-run): /migrate-to-epic <task_name>
  Preflight: OK (task is kind=flat, not completed, no temp state)
  Would create epic folder: <task_name>/ with frontmatter kind=epic
  Would create shared/: <task_name>/shared/
  Would preserve phase artifacts: research.md, architecture.md (present), implementation.md (not present)
  Would move existing peer folders as subtask children: foo, bar
  Would create stub subtask folders: baz, qux
  Would move original to .old-<task_name> for 24h rollback
  Would update session context currentEpic: <task_name> (if active task matches)

No changes made. Re-run without --dry-run to execute.
```

## Invariants this skill upholds

1. **Atomicity.** At any observable moment between step boundaries, the file system is either "pre-migration state" or "post-migration state." Never "partial."
2. **Rollback window.** The `.old-<task>/` directory persists at least 24 hours for manual restoration.
3. **Read-before-write.** Every write-decision is gated on a read via `task-frontmatter-reader`. We do not write frontmatter without validating it parses correctly.
4. **No silent overwrites.** If the target exists (e.g., `.old-<task>/` from a failed previous run), abort — never overwrite user state.
5. **Children classification is deterministic.** `move_existing` ⇔ folder exists at peer location; `create_stub` ⇔ folder does not exist. No judgment calls.

## Do NOT

- Do not use `git mv`. These task folders are NOT in git (framework memory). Plain `mv` is the correct primitive.
- Do not delete `$TASK_DIR` until the new structure is successfully in place.
- Do not write partial frontmatter (e.g., `kind:` without `id:`). All required fields go in one atomic file write.
- Do not call this skill recursively. A sub_epic migration is a separate invocation after the epic is in place.
- Do not proceed past Step 4 if validation has any blocking warnings.

## See also

- `task-frontmatter-reader` (v1.0.0+) — contract for reading the schema this skill writes
- `/drupal-dev-framework:migrate-to-epic` command — the thin user-facing orchestrator that invokes this skill
- Architecture decision 3.1-D2 in `dev_framework_task_hierarchy_foundation/architecture.md` — the source of this 8-step contract
