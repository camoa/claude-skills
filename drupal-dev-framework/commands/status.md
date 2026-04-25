---
description: "Show current project state and task progress. Trigger: 'show progress', 'where am I', 'project overview', 'task status'."
allowed-tools: Read, Write, Glob, Bash
context: fork
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
5. **For each task folder, invoke `task-frontmatter-reader` skill (v1.0.0+) to determine `kind`** — flat/epic/sub_epic/subtask — so the rendering below knows whether to show a flat line or a tree.
6. Presents comprehensive status with hierarchy-aware rendering

## Hierarchy-aware rendering (added v3.10.0)

For each top-level task folder in `implementation_process/in_progress/`:

- **`kind: flat`** (or no frontmatter) — one line: `<name> (Phase N: <phase-name>)`. Current behavior, unchanged.
- **`kind: epic`** or **`kind: sub_epic`** — tree:
  ```
  <epic-name> (Epic — N total, M in progress, K completed)
    ├─ <child-1> (Phase N: <phase-name>)    ← in-progress subtask
    ├─ <child-2> ✓                            ← completed subtask
    └─ ...
  ```
  Children listed in frontmatter order. One line per child, no recursion into sub-epic grandchildren (future enhancement).
- **Location rule for subtask children:** children live inside the epic folder, split by status:
  1. `<epic>/in_progress/<child>/` exists → render with phase indicator
  2. `<epic>/completed/<child>/` exists → render with `✓` marker (phase omitted)
  3. Neither exists → render `├─ <child> ⚠ folder missing` (dangling)
- Mixed output: flat tasks appear separately from trees for readability.

Do NOT walk dependency graphs here — that's `/next`'s (future) responsibility.
6. **Invokes `session-context-writer` skill with the resolved project (and task if one is active)**

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

## Unaudited gates section (v4.0.0+)

After listing tasks, scan each task folder for missing audit files (per `references/gate-audit-schema.md` v1.0). Tasks where the framework expected a hardened gate to fire but the audit file is absent are flagged.

Detection per task:

- `research.md` present but `_pre-analysis.json` absent → "pre-analysis bypassed (or grandfathered from pre-v4.0.0)"
- `research.md` present + has `## Coverage Mapping` section but `_coverage-mapping.json` absent → "coverage-mapping check did not record"
- `research.md` present + lacks `## Coverage Mapping` AND `_coverage-mapping.json` absent → "Phase 1 incomplete: missing coverage mapping (run /research)"
- Phase artifacts written (any of research.md, architecture.md, implementation.md) but `_phase-command-bypass.json` exists → "phase-command bypass recorded; consider re-running through /research / /design / /implement"

Format:

```
Unaudited gates:
  <task_name_1>:
    - pre-analysis: bypassed (no _pre-analysis.json; task pre-dates v4.0.0 → grandfathered)
    - coverage-mapping: missing audit + missing section
  <task_name_2>:
    - phase-command-bypass: recorded for architecture.md (use /audit-status <task> for details)
```

Empty section if no audit gaps. Mentions `/audit-status <task>` for per-task drill-down.

## Related Commands

- `/drupal-dev-framework:next` - Get recommended next action
- `/drupal-dev-framework:research <task>` - Start research for a task
- `/drupal-dev-framework:implement <task>` - Continue implementation
- `/drupal-dev-framework:audit-status [<task>]` - **(v4.0.0+)** Detailed audit-state view; surfaces unaudited gates and bypass reasons
