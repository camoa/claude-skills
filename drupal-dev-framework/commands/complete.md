---
description: Mark current task as done and update memory
allowed-tools: Read, Write, Bash(mv:*), Glob
argument-hint: [task-name]
---

# Complete

Mark a task as complete and update project memory.

## Usage

```
/drupal-dev-framework:complete                    # Complete current task
/drupal-dev-framework:complete settings_form      # Complete specific task
```

## What This Does

1. Invokes `task-completer` skill
2. Verifies acceptance criteria met
3. Updates task file with completion notes
4. Moves task to `completed/`
5. Updates `project_state.md`
6. Suggests next task

## Pre-Completion Checks

Before marking complete, verifies:
- [ ] All acceptance criteria marked done
- [ ] Tests pass (user confirmation)
- [ ] Code reviewed or ready for review
- [ ] No blocking issues

If checks fail:
- Lists remaining items
- Does not complete task
- Offers to continue working

## Completion Process

```markdown
Task: settings_form

Pre-completion check:
✓ Acceptance criteria: 5/5 complete
? Tests pass: [Awaiting confirmation]
✓ No blocking issues

Please confirm tests pass to complete this task.
```

After confirmation:

```markdown
Task completed: settings_form

Updated files:
- Moved to: implementation_process/completed/02_form_settings.md
- Updated: project_state.md

Suggested next task:
- entity_definition (implementation_process/in_progress/03_entity.md)

Run: /drupal-dev-framework:implement entity_definition
```

## Task File Updates

Adds to task file:

```markdown
## Completion

**Completed:** {date}
**Status:** Complete

### Files Changed
- src/Form/SettingsForm.php - Created
- tests/src/Unit/SettingsFormTest.php - Created

### Notes
{Any implementation notes}
```

## Related Commands

- `/drupal-dev-framework:implement <task>` - Start next task
- `/drupal-dev-framework:validate` - Validate before completing
- `/drupal-dev-framework:next` - See what's next
