---
description: "Research a task topic and store findings in task file. Trigger: 'investigate', 'find patterns', 'research task', 'Phase 1', 'look into'. MUST be done before /design. Never skip research."
allowed-tools: Read, Write, WebSearch, WebFetch, Grep, Glob, Task
argument-hint: <task-name>
---

# Research

Research existing solutions for a specific task (Phase 1 of a task).

## Usage

```
/drupal-dev-framework:research <task-name>
```

## What This Does (v3.0.0)

1. Creates task directory: `implementation_process/in_progress/{task_name}/`
2. Creates `task.md` (tracker with links and acceptance criteria)
3. **Loads dev-guides** for the task's Drupal domain via `guide-integrator` (unless already loaded this session)
4. Invokes `contrib-researcher` agent for drupal.org/contrib search
5. Invokes `core-pattern-finder` skill for core examples
6. Stores findings in `research.md` file
7. Updates `task.md` to mark Phase 1 as in progress
8. Updates `project_state.md` with current task

## Task-Based Workflow

**This command operates on a TASK, not the project.**

Each task goes through:
1. **Research** (this command) → Find patterns, existing solutions
2. **Architecture** (`/design`) → Design the approach
3. **Implementation** (`/implement`) → Build with TDD

## Examples

```
/drupal-dev-framework:research settings_form
/drupal-dev-framework:research content_entity
/drupal-dev-framework:research field_formatter
```

## Output (v3.0.0)

Creates folder structure:
```
implementation_process/in_progress/{task_name}/
├── task.md         # Tracker
└── research.md     # Phase 1 findings
```

**task.md** (tracker):
```markdown
# Task: {task_name}

**Created:** {date}
**Current Phase:** Phase 1 - Research

## Goal
{What this task accomplishes}

## Phase Status
- [🔄] Phase 1: Research → See [research.md](research.md)
- [ ] Phase 2: Architecture → See [architecture.md](architecture.md)
- [ ] Phase 3: Implementation → See [implementation.md](implementation.md)

## Acceptance Criteria
- [ ] {criterion 1}
- [ ] {criterion 2}

## Related Tasks
None

## Notes
{Any additional notes}
```

**research.md** (Phase 1 findings):
```markdown
# Research: {task_name}

## Problem Statement
What we're trying to solve.

## Existing Solutions
| Solution | Type | Fit | Notes |
|----------|------|-----|-------|
| {module/pattern} | Contrib/Core | Good/Partial/Poor | {notes} |

## Core Patterns Found
| Pattern | Location | Applicability |
|---------|----------|---------------|
| {pattern} | {path} | {notes} |

## Recommendation
Use / Extend / Build from scratch

## Key Patterns to Apply
- Pattern 1: {description}
- Pattern 2: {description}

## Decision Log
{Research decisions made}
```

## Next Steps

After research is complete for this task:
1. Review findings
2. Move to Phase 2: `/drupal-dev-framework:design {task_name}`

## Related Commands

- `/drupal-dev-framework:design <task>` - Design architecture (Phase 2)
- `/drupal-dev-framework:next` - See recommended next action
