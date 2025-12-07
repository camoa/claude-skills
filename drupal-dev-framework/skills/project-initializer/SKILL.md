---
name: project-initializer
description: Use when starting a new development project - creates memory folder structure with project_state.md, architecture scaffolding, and registers project
version: 1.2.0
---

# Project Initializer

Create a new project with memory structure for the 3-phase workflow.

## Activation

Activate when you detect:
- "Start new project" or "Initialize project X"
- `/drupal-dev-framework:new` command
- Beginning development work that needs tracking

## Workflow

### 1. Get Project Name

Ask:
```
What should this project be called?
(lowercase, letters, numbers, underscores only)
```

Validate the name matches pattern `^[a-z][a-z0-9_]*$`. If invalid, ask again.

### 2. Get Storage Location

Ask:
```
Where should project files be stored?

Default: ../claude_projects/{project_name}/
(relative to current working directory)

Options:
1. Accept default
2. Enter custom path

Your choice:
```

Convert relative paths to absolute. Store the full path.

### 3. Check Path

Use `Bash` to check if folder exists:
```bash
ls -la {chosen_path}
```

If exists, ask: "Folder exists. Overwrite, use different name, or cancel?"

### 4. Create Structure

Use `Bash` to create folders:
```bash
mkdir -p {path}/{project_name}/architecture
mkdir -p {path}/{project_name}/implementation_process/in_progress
mkdir -p {path}/{project_name}/implementation_process/completed
```

### 5. Create project_state.md

Use `Write` tool to create `{path}/{project_name}/project_state.md`:

```markdown
# {Project Name}

**Created:** {YYYY-MM-DD}
**Phase:** 1 - Research
**Status:** Initializing
**Path:** {full_path_to_project_folder}

## Overview
{To be filled during requirements gathering}

## Scope
This project includes:
- {To be defined}

## Requirements
{Populated by requirements-gatherer}

## Key Decisions
{Empty initially}

## Current Focus
Initial setup - gathering requirements

## Next Steps
1. Complete requirements gathering
2. Research existing solutions
3. Begin architecture design
```

### 6. Create Empty architecture/main.md

Use `Write` tool:
```markdown
# {Project Name} Architecture

{To be designed in Phase 2}
```

### 7. Register Project

Add project to the registry at `~/.claude/drupal-dev-framework/active_projects.json`.

First, ensure the directory exists:
```bash
mkdir -p ~/.claude/drupal-dev-framework
```

Then read existing registry (or create new if doesn't exist) and add the project:

**Registry Schema:**
```json
{
  "version": "1.0",
  "projects": [
    {
      "name": "{project_name}",
      "path": "{full_path_to_project}",
      "created": "{YYYY-MM-DD}",
      "lastAccessed": "{YYYY-MM-DD}",
      "phase": 1,
      "status": "active"
    }
  ]
}
```

Use `Read` to load existing registry, then `Write` to save updated version with new project appended.

If registry doesn't exist, create it with just this project.

### 8. Invoke Requirements Gatherer

After structure is created, invoke `requirements-gatherer` skill to populate requirements.

### 9. Confirm

Show user:
```
Project initialized at: {full_path}

Created:
- project_state.md
- architecture/main.md
- implementation_process/in_progress/
- implementation_process/completed/

Next: Answer requirements questions to complete Phase 1 setup.
```

### 10. After Requirements Gathered

Once requirements-gatherer completes and user confirms, show:
```
Requirements gathering complete.

Run `/drupal-dev-framework:next` to get your next recommended action.
```

Do NOT manually list commands like `/research` or `/design`. Always direct to `/next` for intelligent routing.

## Stop Points

STOP and wait for user response:
- After asking for project name
- After asking for storage location
- Before creating folders if path exists
- After showing confirmation
