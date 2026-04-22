---
description: "Mark a task as done and move to completed. Trigger: 'finish task', 'mark done', 'task complete', 'close task'. Runs ALL 5 quality gates before allowing completion."
allowed-tools: Read, Write, Bash(mv:*), Glob
argument-hint: <task-name>
---

# Complete

Mark a task as complete and move it to the completed folder.

## Usage

```
/drupal-dev-framework:complete <task-name>
```

## What This Does (v3.0.0 + v3.10.0 epic awareness)

1. Invokes `task-completer` skill
2. Loads task from `implementation_process/in_progress/{task_name}/`
3. **Invoke `task-frontmatter-reader` (v1.0.0+) to learn the task's `kind` and parent.** Different completion rules apply per kind (see below).
4. Verifies acceptance criteria are met
5. Updates `task.md` with completion notes
6. Moves entire task directory to `implementation_process/completed/{task_name}/`
7. Updates `project_state.md`
8. **If the completed task is a subtask**, check its parent epic's `children[]`: if all siblings are now completed, print a "epic ready for completion" hint to the user (don't auto-complete the epic — the user owns that decision).
9. Suggests next task (if any)

## Hierarchy-aware completion rules (v3.10.0)

- **`kind: flat`** — unchanged v3.0.0 behavior.
- **`kind: subtask`** — standard completion, plus the step-8 sibling check. The task folder moves from `<epic>/<subtask>/` to `completed/<subtask>/` — **child leaves the epic folder on completion**. The epic's frontmatter `children[]` still references the subtask by id (resolves via id, not location), so the reference stays valid.
- **`kind: epic`** or **`kind: sub_epic`** — pre-completion gate enforces that ALL children are in `completed/`. If any child is still `in_progress`, abort with a message listing the outstanding children. When the gate passes, the epic folder itself moves to `completed/<epic>/` (with all still-nested children remaining inside — they're already completed, but physically still nested at their last pre-completion location).
- **Dog-food note for v3.10.0 release:** the first epic completed under these rules will be sub-task 3.1's dog-food test. Verify the flow end-to-end before declaring 3.1 shipped.

Do NOT touch dependency graphs (`blocks`/`blocked_by`) here — those are a 3.2 `/next` concern.
8. **Invokes `session-context-writer` skill with project and task set to `null` (task is now completed)**

## Pre-Completion Checks

Before marking complete, verifies:
- [ ] All acceptance criteria marked done in task file
- [ ] Tests pass (user confirmation required)
- [ ] No blocking issues noted
- [ ] Implementation section is complete

If checks fail:
- Lists remaining items
- Does NOT complete task
- Offers to continue working

## Example

```
/drupal-dev-framework:complete settings_form

Task: settings_form

Pre-completion check:
✓ Acceptance criteria: 5/5 complete
? Tests pass: [Awaiting your confirmation]
✓ No blocking issues

Please confirm tests pass to complete this task.
```

After user confirms (v3.0.0):

```
Task completed: settings_form

Updated files:
- Moved: implementation_process/in_progress/settings_form/ → completed/settings_form/
  - task.md
  - research.md
  - architecture.md
  - implementation.md
- Updated: project_state.md

Up Next:
- content_entity (in_progress, Phase 2)

Run: /drupal-dev-framework:design content_entity
```

## Task File Updates

Adds completion section to task file before moving:

```markdown
## Completion

**Completed:** {date}
**Status:** Complete

### Files Created/Modified
- `src/Form/SettingsForm.php` - Created
- `config/schema/mymodule.schema.yml` - Created
- `tests/src/Unit/SettingsFormTest.php` - Created

### Summary
{Brief summary of what was implemented}

### Notes
{Any implementation notes for future reference}
```

## project_state.md Updates

Updates the project state:

```markdown
## Current Implementation Task
Working on: {next_task or "None - all tasks complete"}
File: {path or "-"}

## Completed Implementation Tasks
- ✅ settings_form - {date}
- ✅ {previous_task} - {date}
```

## All Tasks Complete

When completing the last task:

```
All tasks complete!

Project: {project_name}
Completed tasks: {count}

Options:
1. Define new tasks
2. Mark project as done
3. Review completed work

What would you like to do?
```

## Related Commands

- `/drupal-dev-framework:implement <task>` - Continue implementing a task
- `/drupal-dev-framework:validate <task>` - Validate before completing
- `/drupal-dev-framework:next` - See what's next
- `/drupal-dev-framework:status` - See all task statuses
