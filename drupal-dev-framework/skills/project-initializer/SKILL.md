---
name: project-initializer
description: Use when starting a new Drupal development project - creates memory folder structure with project_state.md and architecture scaffolding in ~/workspace/claude_memory/
version: 1.0.0
---

# Project Initializer

Initialize a new Drupal development project with proper memory structure for the 3-phase workflow.

## Triggers

- User says "Start new project" or "Initialize project X"
- `/drupal-dev-framework:new` command is used
- Beginning a new Drupal module or feature development

## Process

1. **Get project name** - Ask for project identifier (lowercase, underscores)
2. **Create folder structure** - Set up memory directories
3. **Create project_state.md** - Initialize with basic info
4. **Invoke requirements-gatherer** - Ask structured questions
5. **Confirm setup** - Show created structure

## Folder Structure Created

```
~/workspace/claude_memory/{project_name}/
├── project_state.md              # Project status and decisions
├── architecture/
│   └── main.md                   # Architecture document (empty initially)
└── implementation_process/
    ├── in_progress/              # Current task files
    └── completed/                # Finished task files
```

## project_state.md Template

```markdown
# {Project Name}

**Created:** {date}
**Phase:** 1 - Research
**Status:** Initializing

## Overview
{Brief description from requirements}

## Requirements
{Populated by requirements-gatherer}

## Key Decisions
{Empty initially, populated during development}

## Current Focus
Initial setup - gathering requirements

## Next Steps
1. Complete requirements gathering
2. Research existing solutions
3. Begin architecture design
```

## Validation

Before creating:
- Check project name is valid (lowercase, underscores only)
- Check folder doesn't already exist
- Confirm with user before creating

## After Initialization

Automatically invoke `requirements-gatherer` skill to populate initial requirements in project_state.md.

## Human Control Points

- User provides project name
- User confirms folder creation
- User answers requirements questions
