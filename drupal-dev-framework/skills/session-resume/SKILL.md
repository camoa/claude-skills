---
name: session-resume
description: Use when resuming work on existing project - reads project_state.md, summarizes current state, identifies where to continue
version: 1.1.0
---

# Session Resume

Restore context when starting a new session on an existing project.

## Activation

Activate when:
- Starting a new Claude session on existing project
- User says "Resume work on X" or "Continue X project"
- User provides project path for existing project
- "Where did we leave off?"

## Workflow

### 1. Locate Project

If project path provided, use it.

Otherwise, ask:
```
Which project do you want to resume?

Enter the project path or name:
```

### 2. Load Project State

Use `Read` on `{project_path}/project_state.md`

If file not found:
```
No project_state.md found at {path}.

Options:
1. Different path
2. Initialize new project here
3. Cancel

Your choice:
```

### 3. Detect Current Phase

Invoke `phase-detector` skill to determine phase.

### 4. Load Current Focus

From project_state.md, extract:
- Current phase
- Current focus
- Recent key decisions
- Next steps listed

### 5. Scan Active Work

Use `Glob` to find:
```
{project_path}/implementation_process/in_progress/*.md
```

If tasks in progress, use `Read` on each to get:
- Task name
- Status
- Last progress notes

### 6. Present Resume Summary

Format as:
```
## Resuming: {Project Name}

### Project Path
{full_path}

### Current Phase
Phase {N} - {Research/Architecture/Implementation}

### Last Session Summary
{From project_state.md Current Focus}

### Key Decisions Made
- {Decision 1}
- {Decision 2}

### Where We Left Off
{Description of last activity}

### Active Tasks
| Task | Status | Progress |
|------|--------|----------|
| {task 1} | In Progress | {last note} |

### Suggested Next Action
{Based on project state and phase}

---
Ready to continue? What would you like to work on?
```

### 7. Load Task Context (If In Implementation)

If Phase 3 and tasks in progress, ask:
```
Active task: {task_name}

Load full context for this task? (yes/different task/overview first)
```

If yes, invoke `task-context-loader` for that task.

### 8. Set Up Session

After user confirms direction:
- Load relevant architecture files
- Load relevant guides (if configured)
- Invoke appropriate skill for chosen activity

## Quick Resume

For rapid context restoration:
```
Quick resume: {project_name}
- Phase: {N}
- Focus: {current_focus}
- Active task: {task or "none"}
- Next: {suggested action}

Continue with {suggested action}? (yes/other)
```

## Stop Points

STOP and wait for user:
- After asking for project path (if not provided)
- After presenting resume summary
- After asking which task to continue
- Before loading full task context
