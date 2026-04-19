---
name: checkpoint-gate
description: Enforce phase entry requirements by verifying prior-phase checkpoints are done or skipped before /design or /implement proceed. Called internally by those commands; blocks with guidance when checkpoints are incomplete.
user-invocable: false
version: 1.0.0
model: haiku
---

# Checkpoint Gate

Enforce that all required prior-phase checkpoints are complete before entering the next phase.

## When Called

Invoked by `/design` (target_phase=2) and `/implement` (target_phase=3) at the very start, before any other work.

Receives:
- `task_path` — absolute path to task folder
- `target_phase` — must be integer `2` or `3`

## Action

### Step 0 — Validate inputs

If `target_phase` is not `2` or `3` (including `1`, `4`, missing, string, null): return `error` with message `"checkpoint-gate: invalid target_phase {value}. Expected 2 or 3."` Exit non-zero.

If `$TASK_PATH/task.md` does not exist: return `error` with message `"checkpoint-gate: task.md not found at {task_path}"`. Exit non-zero.

### Step 1 — Read task.md frontmatter

Parse YAML frontmatter from `$TASK_PATH/task.md`. Use `yq` if available, otherwise Python:

```bash
yq -r '.checkpoints // "none"' "$TASK_PATH/task.md" 2>/dev/null \
  || python3 -c "import yaml,sys; d=yaml.safe_load(open('$TASK_PATH/task.md').read().split('---')[1]); print(d.get('checkpoints','none'))"
```

If parsing fails (malformed YAML): return `block` with message `"checkpoint-gate: cannot parse task.md frontmatter. Fix YAML syntax or remove the frontmatter block to use grandfather mode."` Exit non-zero.

If no frontmatter block exists OR `checkpoints` key is absent: go to **Step 2 (Grandfather mode)**.

Otherwise: go to **Step 3 (Checkpoint mode)**.

### Step 2 — Grandfather mode

Check the body of task.md in this order:

1. **`## Phase Status` checklist present:**
   - target_phase=2 → require `[x]` on the "Phase 1: Research" line
   - target_phase=3 → require `[x]` on both the Phase 1 and Phase 2 lines
2. **`## Phase Status` absent, but phase files present (last-resort heuristic):**
   - target_phase=2 → require `research.md` exists in the task folder
   - target_phase=3 → require `research.md` AND `architecture.md` exist
3. **Neither signal available:** return `block` with:
   ```
   checkpoint-gate: no phase tracking found in task.md.
   Add a `## Phase Status` checklist with:
     - [x] Phase 1: Research
     - [ ] Phase 2: Architecture
     - [ ] Phase 3: Implementation
   Or adopt the checkpoint frontmatter schema (see references/checkpoint-catalog.md).
   ```

Success in grandfather mode → return `proceed` with message: `"Checkpoint gate: grandfather mode — Phase {prior} verified via {Phase Status checklist|phase file existence}. Entering Phase {target}."`

### Step 3 — Checkpoint mode

Load `references/checkpoint-catalog.md` from the plugin root to resolve IDs to names. If the catalog is missing, continue with raw IDs in messages (do not block on catalog absence).

**Normalize:** lowercase every `status` value read from frontmatter before comparison (`Done` and `DONE` → `done`).

**Define "satisfying statuses":**
- `done` — always satisfies
- `skipped` — satisfies ONLY IF the entry also has a non-empty `justification` field; otherwise treat as `pending`

**Collect required phase arrays:**
- target_phase=2 → required = `phase_1` array
- target_phase=3 → required = `phase_1` array + `phase_2` array

**Check for empty arrays:** if any required phase array is empty or missing, return `block` with:
```
checkpoint-gate: Phase {N} has no checkpoints defined. A phase with no checkpoints cannot be considered complete. Add the canonical checkpoints from references/checkpoint-catalog.md (Phase {N} section) to task.md frontmatter.
```

**Check each required checkpoint:** collect any whose normalized status is not in the satisfying set. Also flag `skipped` entries with empty or missing `justification`.

If all required checkpoints satisfy: return `proceed` with:
```
Checkpoint gate: Phase {prior} complete ({done_count}/{total_count} done, {skipped_count} skipped with justification). Entering Phase {target}.
```

Otherwise: return `block` with:
```
Checkpoint gate: Cannot enter Phase {target}.

Incomplete checkpoints in Phase {prior}:
  - {id}: {name} ({current_status})
  - {id}: {name} ({current_status})
Skipped without justification (will not count):
  - {id}: {name}

Next action:
  1. Complete the pending checkpoints, or
  2. Skip them explicitly with: /drupal-dev-framework:step skip <id> <reason>
  3. Then re-run /{design|implement} {task_name}
```

Prefer the `PermissionDenied {retry: true}` return mechanism if the runtime supports it (makes Claude retry after correction). Otherwise exit non-zero with the message above.

## Do Not

- Do not write to task.md — this skill is read-only
- Do not invoke other skills — keep the gate tight and predictable
- Do not block on checkpoints beyond the required prior phases (target_phase=2 does not require Phase 2 or 3 checkpoints)
- Do not guess checkpoint IDs — resolve from the catalog or report raw IDs
- Do not treat `status: skipped` without a `justification` field as satisfying — this would let users bypass the gate silently

## Conflict resolution

If a task has BOTH `checkpoints` frontmatter AND a legacy `## Phase Status` checklist, **checkpoint frontmatter wins.** Only fall back to the checklist when the frontmatter is absent.

## Output Contract

- `proceed` — exit 0, short confirmation line (format above)
- `block` — exit non-zero with structured guidance; calling command halts
- `error` — exit non-zero with concise error; used for malformed input or missing files
