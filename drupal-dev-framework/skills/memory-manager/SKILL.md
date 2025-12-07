---
name: memory-manager
description: Use after completing any phase activity - updates project_state.md, project registry, ensures files are in correct locations, maintains lean memory
version: 1.2.0
---

# Memory Manager

Maintain clean and organized project memory.

## Activation

Activate when:
- After completing any phase activity (research, design, implementation)
- After task completion
- When project state seems inconsistent
- Periodic maintenance requested
- "Clean up project files" or "Update project state"

## Workflow

### 1. Load Current State

Use `Read` on `{project_path}/project_state.md`

Extract:
- Current phase
- Last updated date
- Current focus
- Progress summary

### 2. Scan Project Files

Use `Glob` to inventory files:
```
{project_path}/architecture/*.md
{project_path}/implementation_process/in_progress/*.md
{project_path}/implementation_process/completed/*.md
```

Count:
- Research files (research_*.md)
- Component architectures
- In-progress tasks
- Completed tasks

### 3. Detect Inconsistencies

Check for issues:

| Issue | Detection | Fix |
|-------|-----------|-----|
| Empty files | File size = 0 | Ask to delete or populate |
| Orphaned tasks | Task in wrong folder | Move to correct location |
| Stale state | project_state.md outdated | Update current focus |
| Missing files | Referenced but not found | Create or update reference |

### 4. Update project_state.md

Use `Edit` to update:

```markdown
# {Project Name}

**Updated:** {today's date}
**Phase:** {detected phase}
**Status:** {current status}
**Path:** {project_path}

## Overview
{Keep existing or update based on recent work}

## Progress
- Phase 1 (Research): {Complete/In Progress} - {count} research files
- Phase 2 (Architecture): {Complete/In Progress} - {count} component files
- Phase 3 (Implementation): {X}/{Y} tasks complete

## Current Focus
{What's actively being worked on}

## Key Decisions
| Date | Decision | Rationale |
|------|----------|-----------|
{add new decisions, keep old ones}

## Next Steps
1. {Immediate next action}
2. {Following action}
```

### 5. Organize Files

If files are misplaced, use `Bash` to move:

```bash
# Move completed task from in_progress
mv "{project_path}/implementation_process/in_progress/{file}" "{project_path}/implementation_process/completed/{file}"
```

### 6. Clean Up

Ask before deleting anything:
```
Found {count} empty/orphaned files:
- {file 1}
- {file 2}

Delete these? (yes/no/review each)
```

### 7. Update Project Registry

Update the registry at `~/.claude/drupal-dev-framework/active_projects.json`:

1. Read the registry file
2. Find this project by path
3. Update:
   - `lastAccessed`: today's date
   - `phase`: current detected phase
   - `status`: "active" or "archived" if all tasks complete
4. Write the updated registry

If project not in registry, offer to add it:
```
This project is not in the registry.
Add it for easier access next time? (yes/no)
```

### 8. Report

Show summary:
```
Memory cleanup complete:

Files scanned: {count}
Issues found: {count}
Issues fixed: {count}

Current state:
- Phase: {phase}
- Architecture files: {count}
- Tasks in progress: {count}
- Tasks completed: {count}

project_state.md updated.
Registry updated.
```

## Lean Memory Principles

Follow these rules:
- **One source of truth** - don't duplicate information
- **Summarize, don't copy** - reference external files
- **Archive, don't delete** - move to completed/, not trash
- **Update in place** - no versioned copies (main.md, not main_v2.md)

## Stop Points

STOP and wait for user:
- Before deleting any files
- Before major reorganization
- After presenting cleanup summary
