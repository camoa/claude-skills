---
name: project-orchestrator
description: Use when checking project status or deciding next steps - reads memory files, manages tasks, suggests actions, routes to appropriate agents/skills
capabilities: ["project-status", "task-management", "workflow-routing", "next-action-suggestion"]
version: 1.2.0
---

# Project Orchestrator

Central coordinator agent for managing project state and task workflow progression.

## Purpose

Coordinate the development workflow by:
- Reading project memory files
- Managing tasks (each task has its own 3-phase cycle)
- Suggesting appropriate next actions
- Routing to correct agents/skills

## Key Concept: Task-Based Phases

**Projects contain tasks. Each TASK goes through 3 phases, not the project itself.**

```
Project
├── Requirements (project-level, gathered once)
└── Tasks (each has its own phases)
    ├── Task 1: Phase 1 → Phase 2 → Phase 3 → Complete
    ├── Task 2: Phase 1 → Phase 2 → Phase 3 → Complete
    └── Task 3: Phase 1 → Phase 2 → Phase 3 → Complete
```

## When to Invoke

- Starting a new Claude session on existing project
- When `/drupal-dev-framework:status` command is used
- When `/drupal-dev-framework:next` command is used
- When uncertain about project state or next steps

## Process

1. **Locate project** - Check registry at `~/.claude/drupal-dev-framework/active_projects.json`
2. **Read state** - Load project_state.md from the project's `path`
3. **Check requirements** - Are project requirements gathered?
4. **Check tasks** - Are there defined tasks? What's their status?
5. **Suggest actions** - Based on project and task state
6. **Update registry** - Update `lastAccessed` in registry
7. **Route** - Point to appropriate agent or skill

## Project Registry

The registry at `~/.claude/drupal-dev-framework/active_projects.json` tracks all projects:

```json
{
  "version": "1.0",
  "projects": [
    {
      "name": "project_name",
      "path": "/full/path/to/project/folder",
      "created": "YYYY-MM-DD",
      "lastAccessed": "YYYY-MM-DD",
      "status": "active"
    }
  ]
}
```

## Decision Logic

### Step 0: Project Selection (if no project specified)

When invoked without a specific project:

```
Read registry: ~/.claude/drupal-dev-framework/active_projects.json

Projects found?
├── YES → List projects (sorted by lastAccessed)
│         ┌─────────────────────────────────────────────┐
│         │ ## Available Projects                       │
│         │                                             │
│         │ Found {N} project(s):                       │
│         │                                             │
│         │ 1. my_module (2025-12-06)                   │
│         │    Path: /home/user/workspace/my_module     │
│         │                                             │
│         │ 2. another_project (2025-12-05)             │
│         │    Path: /home/user/workspace/another       │
│         │                                             │
│         │ Which project? (enter number or "new")      │
│         └─────────────────────────────────────────────┘
│
└── NO → "No projects found. Run /new <project-name>"
```

### Step 1: Check Project Requirements (after project selected)
```
Requirements gathered?
├── NO → "Gather requirements first" → requirements-gatherer
└── YES → Go to Step 2 (Task Selection)
```

### Step 2: Task Selection (follows /start pattern)

**Always scan `implementation_process/in_progress/` and present options:**

```
Use Glob to find: {project_path}/implementation_process/in_progress/*.md

If tasks found:
┌─────────────────────────────────────────────┐
│ ## Tasks in Progress                        │
│                                             │
│ Found {N} task(s):                          │
│                                             │
│ 1. settings_form (Phase 2 - Architecture)   │
│ 2. content_entity (Phase 1 - Research)      │
│ 3. field_formatter (Phase 3 - Implementation)│
│                                             │
│ Which task do you want to work on?          │
│ - Enter a number (1-3) to continue existing │
│ - Enter a new task name to start new        │
└─────────────────────────────────────────────┘

If no tasks found:
┌─────────────────────────────────────────────┐
│ ## No Tasks Yet                             │
│                                             │
│ No tasks in implementation_process/in_progress/│
│                                             │
│ What task do you want to work on?           │
│ Enter a task name (e.g., "settings_form")   │
└─────────────────────────────────────────────┘
```

### Step 3: After User Selects Task

```
User selected existing task?
├── YES → Load task file, detect phase, suggest command
└── NO (new task name) →
    Suggest: /drupal-dev-framework:research {task_name}
    This creates task file and starts Phase 1
```

### Step 4: Task Phase Detection
For the selected task, check `implementation_process/in_progress/{task_name}.md`:

| Task File Contains | Phase | Next Action |
|-------------------|-------|-------------|
| Only task description | Phase 1 - Research | `/research {task}` |
| Research section complete | Phase 2 - Architecture | `/design {task}` |
| Architecture section complete | Phase 3 - Implementation | `/implement {task}` |
| Implementation complete | Done | `/complete {task}` |

## Output Format

```markdown
## Project Status: {Project Name}

### Requirements
{Complete / Not gathered}

### Tasks
| Task | Phase | Status |
|------|-------|--------|
| {task_name} | {1/2/3} | {in_progress/queued/complete} |

### Current Focus
Task: {task_name}
Phase: {1-Research / 2-Architecture / 3-Implementation}

### Recommended Next Action
**Action:** {What to do}
**Command:** {Command to run}
**Reason:** {Why this is the priority}

### Alternative Actions
1. {Alternative 1}
2. {Alternative 2}
```

## Output: Task Selection

### When Tasks Exist
```markdown
## Project: {Project Name}

Requirements: Complete ✓

## Tasks in Progress

Found 3 task(s) in implementation_process/in_progress/:

1. settings_form (Phase 3 - Implementation, 3/5 done)
2. content_entity (Phase 1 - Research)
3. field_formatter (Phase 2 - Architecture)

## Completed Tasks
- ✅ user_service
- ✅ config_schema

Which task do you want to work on?
- Enter a number (1-3) to continue an existing task
- Enter a new task name to start something new
```

### When No Tasks Exist
```markdown
## Project: {Project Name}

Requirements: Complete ✓

## No Tasks Yet

No tasks found in implementation_process/in_progress/

What task do you want to work on?
Enter a task name (e.g., "settings_form", "user_entity", "admin_dashboard")
```

## Routing Table

| Situation | Route To |
|-----------|----------|
| No requirements | `requirements-gatherer` skill |
| No tasks defined | Ask user for task |
| Task needs research | `contrib-researcher` agent |
| Task needs architecture | `architecture-drafter` agent |
| Task needs implementation | `task-context-loader` skill |
| Task complete | `task-completer` skill |
| Need pattern guidance | `pattern-recommender` agent |

## Human Control Points

- Developer defines what tasks to work on
- Developer chooses which task to start next
- Developer decides when a task phase is complete
- Developer can skip phases if appropriate
