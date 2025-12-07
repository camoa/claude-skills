---
description: Research a task topic and store findings in task file
allowed-tools: Read, Write, WebSearch, WebFetch, Grep, Glob, Task
argument-hint: <task-name>
---

# Research

Research existing solutions for a specific task (Phase 1 of a task).

## Usage

```
/drupal-dev-framework:research <task-name>
```

## What This Does

1. Creates/updates task file in `implementation_process/in_progress/{task_name}.md`
2. Invokes `contrib-researcher` agent for drupal.org/contrib search
3. Invokes `core-pattern-finder` skill for core examples
4. Stores findings in the task file's Research section
5. Updates `project_state.md` with current task

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

## Output

Creates/updates `implementation_process/in_progress/{task_name}.md`:

```markdown
# Task: {task_name}

**Created:** {date}
**Phase:** 1 - Research
**Status:** In Progress

## Description
{What this task accomplishes}

## Research

### Problem Statement
What we're trying to solve.

### Existing Solutions
| Solution | Type | Fit | Notes |
|----------|------|-----|-------|
| {module/pattern} | Contrib/Core | Good/Partial/Poor | {notes} |

### Core Patterns Found
| Pattern | Location | Applicability |
|---------|----------|---------------|
| {pattern} | {path} | {notes} |

### Recommendation
Use / Extend / Build from scratch

### Key Patterns to Apply
- Pattern 1: {description}
- Pattern 2: {description}

## Architecture
{To be completed in Phase 2}

## Implementation
{To be completed in Phase 3}
```

## Next Steps

After research is complete for this task:
1. Review findings
2. Move to Phase 2: `/drupal-dev-framework:design {task_name}`

## Related Commands

- `/drupal-dev-framework:design <task>` - Design architecture (Phase 2)
- `/drupal-dev-framework:next` - See recommended next action
