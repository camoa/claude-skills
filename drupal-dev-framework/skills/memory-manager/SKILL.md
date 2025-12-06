---
name: memory-manager
description: Use after completing any phase activity - updates project_state.md, ensures files are in correct locations, maintains lean memory
version: 1.0.0
---

# Memory Manager

Maintain clean and organized project memory state.

## Triggers

- After completing any phase activity
- After task completion
- When project state seems inconsistent
- Periodic maintenance

## Responsibilities

1. **Update project_state.md** - Keep current status accurate
2. **Organize files** - Ensure correct locations
3. **Clean up** - Remove temporary/obsolete files
4. **No versioning** - Update in place, don't create copies

## project_state.md Maintenance

Keep updated:

```markdown
# {Project Name}

**Updated:** {current date}
**Phase:** {1/2/3} - {Research/Architecture/Implementation}
**Status:** {current status}

## Overview
{Keep this current}

## Requirements
{From requirements-gatherer, update if changed}

## Key Decisions
| Date | Decision | Rationale |
|------|----------|-----------|
| {date} | {decision} | {why} |

## Current Focus
{What's being worked on now}

## Progress
- Phase 1: {Complete/In Progress}
- Phase 2: {Complete/In Progress}
- Phase 3: {X/Y tasks complete}

## Next Steps
1. {Immediate next action}
2. {Following action}
```

## File Organization

### Expected Structure
```
~/workspace/claude_memory/{project}/
├── project_state.md           # Always exists
├── architecture/
│   ├── main.md               # Main architecture
│   ├── research_*.md         # Research findings
│   └── {component}.md        # Component designs
└── implementation_process/
    ├── in_progress/          # Active tasks
    └── completed/            # Finished tasks
```

### Cleanup Rules

**Move to completed/:**
- Task files marked as complete
- Files in wrong location

**Remove:**
- Empty files
- Duplicate files
- Temporary notes (after incorporated)

**Never remove:**
- project_state.md
- architecture/main.md
- Completed task files

## Update Patterns

### After Research
- Update project_state.md with findings summary
- Ensure research files are in architecture/

### After Architecture
- Update project_state.md phase to 2
- Verify all components documented

### After Task Completion
- Move task to completed/
- Update project_state.md progress
- Update next steps

## Lean Memory Principle

Keep memory minimal:
- Summarize, don't duplicate
- Reference external files, don't copy
- Archive completed work, don't delete
- One source of truth per concept

## Human Control Points

- User can override file organization
- User confirms state updates
- User decides what to archive vs delete
