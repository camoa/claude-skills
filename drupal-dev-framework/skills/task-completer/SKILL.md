---
name: task-completer
description: Use when finishing a task - moves task to completed/, updates project_state.md, suggests next task
version: 1.1.0
---

# Task Completer

Finalize tasks and update project memory.

## Activation

Activate when you detect:
- `/drupal-dev-framework:complete` command
- "Done with X task" or "Task complete"
- "Finish this task"
- All acceptance criteria appear met

## Workflow

### 1. Verify Completion

Use `Read` on the task file: `{project_path}/implementation_process/in_progress/{task}.md`

Check each acceptance criterion. Ask user:
```
Completion checklist for {task_name}:

Acceptance Criteria:
- [ ] {criterion 1} - Is this done?
- [ ] {criterion 2} - Is this done?
- [ ] {criterion 3} - Is this done?

Additional checks:
- [ ] Tests pass? (you run: ddev phpunit {path})
- [ ] Code reviewed or ready for review?
- [ ] No TODO comments left?

Confirm all items are complete (yes/no):
```

If NO, identify what's remaining and continue working.

### 2. Run Code Pattern Check

Before completing, invoke `code-pattern-checker` skill on the files that were created/modified.

If issues found, ask: "Issues found. Fix before completing? (yes/continue anyway)"

### 3. Update Task File

Use `Edit` to add completion section to the task file:

```markdown
---

## Completion

**Completed:** {YYYY-MM-DD}
**Final Status:** Complete

### Summary
{Brief description of what was implemented}

### Files Changed
| File | Action |
|------|--------|
| src/... | Created |
| tests/... | Created |
| *.services.yml | Modified |

### Test Results
- Unit tests: {count} passing
- Kernel tests: {count} passing
- Total: All passing

### Notes
{Any implementation notes, deviations, or decisions made}
```

### 4. Move Task File

Use `Bash` to move the task:
```bash
mv "{project_path}/implementation_process/in_progress/{task}.md" "{project_path}/implementation_process/completed/{task}.md"
```

### 5. Update project_state.md

Use `Edit` to update:

```markdown
## Progress

### Completed Tasks
| Task | Completed | Notes |
|------|-----------|-------|
| {task_name} | {date} | {one-line summary} |

## Current Focus
{Update to next task or "Ready for next component"}
```

### 6. Suggest Next Task

Use `Glob` to find remaining tasks:
```
{project_path}/implementation_process/in_progress/*.md
```

Analyze dependencies and priorities. Present:
```
Task complete: {task_name}

Next task options:
1. {next_task} - {reason: dependency unblocked / priority}
2. {alternative} - {reason}
3. No more tasks - component complete

Which task next? (1/2/3 or other):
```

### 7. Invoke Verification

If this was the last task for a component, suggest:
```
Component {name} appears complete.

Run final validation?
- superpowers:verification-before-completion
- Full test suite
- Integration tests

Proceed? (yes/no)
```

## Stop Points

STOP and wait for user:
- After showing completion checklist (confirm all done)
- If code-pattern-checker finds issues
- After suggesting next task (let user choose)
- Before running verification
