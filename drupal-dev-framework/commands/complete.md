---
description: Mark a task as done and move to completed
allowed-tools: Read, Write, Bash(mv:*), Glob
argument-hint: <task-name>
---

# Complete

Mark a task as complete and move it to the completed folder.

## Usage

```
/drupal-dev-framework:complete <task-name>
```

## What This Does (v3.0.0)

1. Invokes `task-completer` skill
2. Loads task from `implementation_process/in_progress/{task_name}/`
3. Verifies acceptance criteria are met
4. Updates `task.md` with completion notes
5. Moves entire task directory to `implementation_process/completed/{task_name}/`
6. Updates `project_state.md`
7. Suggests next task (if any)

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
