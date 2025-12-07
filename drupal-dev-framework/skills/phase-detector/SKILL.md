---
name: phase-detector
description: Use when determining task phase - analyzes task file to identify Phase 1, 2, or 3 for a specific task
version: 1.2.0
---

# Phase Detector

Analyze a task file to determine its current development phase.

## Key Concept

**Phases apply to TASKS, not projects.** A project has requirements (gathered once), then contains multiple tasks. Each task independently progresses through phases.

## Activation

Activate when:
- Invoked by `project-orchestrator` agent
- Checking status of a specific task
- "What phase is this task in?"
- Determining next action for a task

## Phase Definitions (Per Task)

| Phase | Focus | Code? |
|-------|-------|-------|
| 1 - Research | Understand requirements, research solutions | NO |
| 2 - Architecture | Design approach, patterns, decisions | NO |
| 3 - Implementation | Build with TDD, interactive coding | YES |

## Workflow

### 1. Identify Task

Get task name from:
- User request
- Current in_progress task
- project_state.md "Current Task" field

### 2. Locate Task File

Check for task file at:
```
{project_path}/implementation_process/in_progress/{task_name}.md
```

If not found, check:
```
{project_path}/implementation_process/completed/{task_name}.md
```

If neither exists, task hasn't started yet → Phase 0 (Not Started)

### 3. Analyze Task File Content

Use `Read` on task file and check for these sections:

**Phase 1 Complete Indicators:**
- [ ] `## Research` section exists with content
- [ ] `## Existing Solutions` or `## Patterns Found` section
- [ ] Research notes or findings documented

**Phase 2 Complete Indicators:**
- [ ] `## Architecture` or `## Design` section exists
- [ ] `## Components` or `## Structure` defined
- [ ] `## Dependencies` or `## Services` listed
- [ ] Pattern decisions documented

**Phase 3 Progress Indicators:**
- [ ] `## Implementation` section exists
- [ ] `## Tests` or TDD progress noted
- [ ] `## Progress` with checkboxes
- [ ] Code references or file paths mentioned

### 4. Determine Phase

```
Task file doesn't exist?
→ Phase 0: Not Started - "Create task and begin research"

Task file exists but no Research section?
→ Phase 1: Research - "Research this task"

Research complete but no Architecture section?
→ Phase 2: Architecture - "Design architecture for this task"

Architecture complete?
→ Phase 3: Implementation - "Implement this task"

All checkboxes complete?
→ Done - "Complete this task"
```

### 5. Return Result

Format output as:
```
## Task Phase: {task_name}

**Phase:** {0/1/2/3} - {Not Started/Research/Architecture/Implementation}
**Status:** {Not Started/In Progress/Complete}

### Evidence
| Section | Found | Content |
|---------|-------|---------|
| Research | Yes/No | {summary or "Empty"} |
| Architecture | Yes/No | {summary or "Empty"} |
| Implementation | Yes/No | {progress or "Empty"} |

### Next Action
{What to do next for this task}

### Command
{Suggested command to run}
```

## Project-Level Status

When checking overall project status, summarize all tasks:

```
## Project: {project_name}

### Requirements
{Complete / Not gathered}

### Task Summary
| Task | Phase | Status | Next Action |
|------|-------|--------|-------------|
| {task1} | 3 | In Progress | Continue implementation |
| {task2} | 1 | In Progress | Complete research |
| {task3} | 0 | Queued | Start research |

### Completed Tasks
- {task_a} ✓
- {task_b} ✓
```

## Edge Cases

| Situation | Handling |
|-----------|----------|
| No task specified | List all tasks with their phases |
| Task not found | Offer to create it |
| Task in completed/ | Report as done |
| Multiple tasks in progress | Show all, ask which to focus on |

## Stop Points

STOP if:
- No task specified and multiple tasks exist (ask which one)
- Task file has unexpected structure
- Phase is ambiguous (ask user to clarify)
