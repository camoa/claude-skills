---
description: "Show current checkpoint state for the active task and recommend next action. Also mark-done, skip, or reset individual checkpoints. Trigger: 'where am I', 'what's next checkpoint', 'step', 'mark checkpoint done', 'skip checkpoint'."
allowed-tools: Read, Edit
argument-hint: "[show|mark-done <id>|skip <id> <reason>|reset <id>]"
---

# Step

Navigate and update checkpoint state for the active task. Reads `references/checkpoint-catalog.md` for canonical checkpoint names and entry conditions.

## Usage

```
/drupal-dev-framework:step                                        # Show current state
/drupal-dev-framework:step mark-done 2.4                          # Mark a checkpoint done
/drupal-dev-framework:step skip 1.5 meta-task, no Drupal core     # Skip with justification (multi-word ok)
/drupal-dev-framework:step reset 2.3                              # Revert to pending
```

## Instructions

### Step 1 — Resolve active task

Read the per-workspace session file:

```bash
WORKSPACE_HASH=$(echo -n "$PWD" | md5sum | cut -d' ' -f1)
SESSION_FILE="$HOME/.claude/drupal-dev-framework/sessions/${WORKSPACE_HASH}.json"
```

If the session file does not exist: tell the user `"No active task for this workspace. Run /drupal-dev-framework:next to select one."` Stop.

If the session file exists but `taskPath` is null or does not point to an existing folder: tell the user `"Session points to a task that no longer exists. Run /drupal-dev-framework:next to re-select."` Stop.

### Step 2 — Parse arguments

Parse `$ARGUMENTS`:

- No argument or first token is `show` → go to **Show state**
- First token is `mark-done` → second token is `<id>`; go to **Mark done**
- First token is `skip` → second token is `<id>`; rest-of-line is `<reason>`; go to **Skip**
- First token is `reset` → second token is `<id>`; go to **Reset**
- Anything else → print usage block (see Usage above) and stop

**ID validation (applies to all mutating sub-commands):** the `<id>` token must match `^\d+\.\d+$` (e.g., `1.1`, `2.4`, `3.7`). Normalize by stripping surrounding whitespace. Reject anything else with `"Invalid checkpoint ID '{id}'. Expected format: <phase>.<step>, e.g., 1.3"`. This prevents path-like or malformed IDs from reaching file operations.

## Show state (default)

1. Read task.md. If no YAML frontmatter exists OR frontmatter lacks a `checkpoints` key → **grandfather-mode output:**
   ```
   Task: {task_name}
   Phase: {from body Phase Status checklist, or "unknown"} — grandfather mode (no checkpoint schema)

   Legacy Phase Status:
     Phase 1: {x or blank}
     Phase 2: {x or blank}
     Phase 3: {x or blank}

   Checkpoint schema not in use for this task. Add a `checkpoints:` key to the frontmatter
   following references/checkpoint-catalog.md to enable per-checkpoint tracking.
   ```

2. Otherwise, build the report from frontmatter + `references/checkpoint-catalog.md`:
   - Normalize all `status` values to lowercase for display and counting
   - Treat `skipped` entries without a non-empty `justification` as effectively `pending` (show with a `[?]` marker)

   ```
   Task: {task_name}
   Phase: {phase} ({done_count}/{total_count} checkpoints done)

   Current: {first in_progress, else first pending} — {name}
   Next:    {next pending after current} — {name}

   Recent (last 3):
     [done] {id}  {name}  ({evidence or "—"})
     [skip] {id}  {name}  ({justification})
     [done] {id}  {name}

   Upcoming in this phase (next 3):
     [....] {id}  {name}
     [....] {id}  {name}

   To advance:
     Complete {current id} by {human-readable hint from catalog entry condition}, then:
     /drupal-dev-framework:step mark-done {current id}
   ```

Output is **human-first** — readable prose + boxed structure. Include the suggested next command literally so the user can copy-paste. Cap `Recent` and `Upcoming` at 3 entries each.

## Mark done

1. Validate `<id>` matches `^\d+\.\d+$` (Step 2 already did this if reached here).
2. Validate `<id>` exists for the task's current phase in `references/checkpoint-catalog.md`. If not: print valid IDs for the current phase and stop.
3. Read task.md. If no `checkpoints` frontmatter: refuse with `"Task is in grandfather mode. Add a checkpoints: frontmatter block first (see references/checkpoint-catalog.md for schema)."`
4. Verify prior checkpoints in the same phase have normalized status `done` OR (`skipped` with non-empty `justification`). If any earlier ID is still pending or `skipped` without justification: list them and stop. Do not mark out of order.
5. If the target ID is already `done`: print `"{id} is already marked done — no change."` Do NOT touch the existing `evidence` field. Stop.
6. **Use `Edit` (not `Write`)** to change the single checkpoint entry's `status` to `done`. This preserves the surrounding frontmatter and avoids clobbering other concurrent edits. Do NOT add an `evidence` field automatically — evidence is added manually by the user or authoring agent when it's meaningful.
7. Print one-line confirmation + next recommended checkpoint.

## Skip

1. Validate `<id>` (same as mark-done step 1-2).
2. `<reason>` must be non-empty, trimmed of leading/trailing whitespace, contain at least one non-whitespace character, and be ≤ 500 characters. Reject:
   - empty / whitespace-only → `"Skip requires a written justification: /drupal-dev-framework:step skip <id> <reason>"`
   - > 500 chars → `"Skip reason too long (max 500 chars). Trim and retry."`
3. **YAML-safe the reason before writing:**
   - Reject if the reason contains raw newlines or control characters (ASCII < 0x20 except tab). Single-line only.
   - Reject if the reason contains a literal `"---"` sequence (could split the frontmatter block).
   - Escape all `"` as `\"` and all backslashes as `\\`.
   - Always write the justification inside double quotes: `justification: "…"`.
4. **Use `Edit`** to update the checkpoint entry: `status: skipped, justification: "{escaped_reason}"`. Preserve other fields.
5. Print one-line confirmation + next recommended checkpoint.

## Reset

1. Validate `<id>`.
2. **Use `Edit`** to set the entry to `status: pending` and remove any `evidence` and `justification` fields from that single entry. Do not touch other entries.
3. Print one-line confirmation.

## Output Style

- **Show state output is human-first** — prose, boxes, copy-pasteable commands
- **Mark-done / skip / reset confirmations are short** — one line of confirmation + one line of next action

## Do Not

- Do not invent checkpoint IDs. If user passes an ID not in the catalog for the current phase, print valid IDs and stop.
- Do not use `Write` on task.md — always `Edit`, to reduce clobber risk on concurrent operations.
- Do not mark completion without verifying prior-checkpoint dependencies.
- Do not accept skip reasons with newlines, control chars, or `"---"` sequences.
- Do not auto-fill `evidence` — let humans or authoring agents write meaningful evidence.

## Related Commands

- `/drupal-dev-framework:status` — full task overview (all phases)
- `/drupal-dev-framework:next` — recommend next command (macro-level)
- `/drupal-dev-framework:design <task>` — enter Phase 2 (invokes checkpoint-gate)
- `/drupal-dev-framework:implement <task>` — enter Phase 3 (invokes checkpoint-gate)
