---
description: Show current project state and phase
allowed-tools: Read, Glob
argument-hint: [project-name]
---

# Status

Show current project status, phase, and progress.

## Usage

```
/drupal-dev-framework:status              # Current project
/drupal-dev-framework:status my_project   # Specific project
```

## What This Does

1. Invokes `project-orchestrator` agent
2. Reads project memory files
3. Invokes `phase-detector` skill
4. Presents comprehensive status

## Output Format

```markdown
## Project Status: {Project Name}

### Current Phase: {1/2/3} - {Research/Architecture/Implementation}

### Progress Summary
| Phase | Status | Details |
|-------|--------|---------|
| Research | Complete | 3 research files |
| Architecture | In Progress | 2/4 components designed |
| Implementation | Not Started | 0 tasks |

### Current Focus
{What's currently being worked on}

### Recent Activity
- {Date}: {Activity}
- {Date}: {Activity}

### Key Decisions
- {Decision 1}
- {Decision 2}

### Open Questions
- {Question needing resolution}

### Files
| Location | Count |
|----------|-------|
| architecture/ | 4 |
| in_progress/ | 1 |
| completed/ | 2 |
```

## Quick Status

For a quick summary without full details, the output starts with:

```
{Project}: Phase {N} - {status}
```

## Finding Projects

If no project specified and none detected:
- Asks user to provide project path
- Asks which one to check

## Related Commands

- `/drupal-dev-framework:next` - Suggest next action
