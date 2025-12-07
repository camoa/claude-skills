---
description: Show current project state and task progress
allowed-tools: Read, Glob
argument-hint: [project-name]
---

# Status

Show current project status and task progress.

## Usage

```
/drupal-dev-framework:status              # Current project
/drupal-dev-framework:status my_project   # Specific project
```

## What This Does

1. Checks project registry at `~/.claude/drupal-dev-framework/active_projects.json`
2. Loads `project_state.md` from project path
3. Scans `implementation_process/` for task files
4. Invokes `phase-detector` for each task
5. Presents comprehensive status

## Output Format

```markdown
## Project Status: {Project Name}

### Requirements
{Complete / Not gathered}

### Tasks Summary
| Task | Phase | Status | Next Action |
|------|-------|--------|-------------|
| settings_form | 3 - Implementation | In Progress | Continue implementation |
| content_entity | 2 - Architecture | In Progress | Complete design |
| field_formatter | 0 - Not Started | Queued | Start research |

### Current Focus
Task: {current_task_name}
Phase: {1-Research / 2-Architecture / 3-Implementation}
File: `implementation_process/in_progress/{task}.md`

### Completed Tasks
- ✅ {task_name} - {completion date}
- ✅ {task_name} - {completion date}

### Key Decisions
- {Decision 1}
- {Decision 2}

### Open Questions
- {Question needing resolution}

### Files
| Location | Count |
|----------|-------|
| architecture/ | {N} |
| in_progress/ | {N} |
| completed/ | {N} |
```

## Quick Status

For projects with active tasks, starts with:

```
{Project}: {N} tasks in progress, {M} completed
Current: {task_name} (Phase {N})
```

## No Tasks State

When requirements are complete but no tasks defined:

```markdown
## Project Status: {Project Name}

### Requirements
Complete ✓

### Tasks
No tasks defined yet.

### Next Action
Define your first task. What feature or component do you want to work on?
```

## Finding Projects

If no project specified:
1. Checks registry for active projects
2. If multiple, lists them for selection
3. If none, asks for project path

## Related Commands

- `/drupal-dev-framework:next` - Get recommended next action
- `/drupal-dev-framework:research <task>` - Start research for a task
- `/drupal-dev-framework:implement <task>` - Continue implementation
