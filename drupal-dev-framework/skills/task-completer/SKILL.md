---
name: task-completer
description: Use when finishing a task - moves task to completed/, updates project_state.md, suggests next task
version: 1.0.0
---

# Task Completer

Finalize completed tasks and update project memory.

## Triggers

- `/drupal-dev-framework:complete` command
- User says "Done with X task" or "Task complete"
- All acceptance criteria are met

## Process

1. **Verify completion** - Check acceptance criteria
2. **Update task file** - Mark as completed with notes
3. **Move to completed/** - Archive the task file
4. **Update project_state.md** - Record progress
5. **Suggest next task** - What should be done next?

## Pre-Completion Checklist

Before marking complete:
- [ ] All acceptance criteria met
- [ ] Tests pass (user confirms)
- [ ] Code reviewed (or ready for review)
- [ ] No TODO comments left in code
- [ ] Documentation updated if needed

If any item is not complete:
- Do not complete the task
- Identify what's remaining
- Continue working

## Task File Update

Add completion section to task file:

```markdown
## Completion

**Completed:** {date}
**Status:** Complete

### Summary
{Brief description of what was implemented}

### Files Changed
- `src/Service/MyService.php` - Created
- `my_module.services.yml` - Updated
- `tests/src/Unit/MyServiceTest.php` - Created

### Notes
{Any implementation notes or deviations from plan}

### Tests
- {count} unit tests
- {count} kernel tests
- All passing: Yes
```

## Move Task

```
From: implementation_process/in_progress/{task_name}.md
To:   implementation_process/completed/{task_name}.md
```

## Update project_state.md

```markdown
## Progress Log

### {date} - {task_name}
- Component: {component}
- Status: Completed
- Tests: {count} passing
- Next: {suggested next task}
```

## Suggest Next Task

Based on:
1. Task dependencies (what's unblocked now?)
2. Priority order in task names
3. Remaining in_progress/ files
4. Architecture completion status

Format:
```markdown
## Suggested Next Task

**Task:** {task_name}
**File:** implementation_process/in_progress/{task_name}.md
**Reason:** {why this should be next}

Alternative options:
- {other task 1}
- {other task 2}
```

## Integration

Before completing, consider invoking:
- `superpowers:verification-before-completion` - Final checks
- `code-pattern-checker` - Standards validation

## Human Control Points

- User confirms acceptance criteria are met
- User confirms tests pass
- User approves completion
- User chooses next task
