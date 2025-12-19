---
description: Start a new development project
allowed-tools: Read, Write, Bash(mkdir:*), Glob, Task
argument-hint: [project-name]
---

# New Project

Initialize a new development project with complete memory structure.

## Usage

```
/drupal-dev-framework:new                  # Interactive - asks for name
/drupal-dev-framework:new my_project       # Direct - with name
```

## What This Does

1. Asks for project name (if not provided)
2. Asks where to store project files (default: `~/workspace/claude_projects/{name}/`)
3. Creates project folder structure:
   - `project_state.md`
   - `architecture/main.md`
   - `implementation_process/in_progress/`
   - `implementation_process/completed/`
4. Registers project in `~/.claude/drupal-dev-framework/active_projects.json`
5. Invokes `project-initializer` skill
6. Invokes `requirements-gatherer` skill

## Project Name Requirements

- Lowercase letters, numbers, and underscores only
- Must be a valid directory name
- Cannot already exist at chosen path

## Example Flow

```
/drupal-dev-framework:new

Enter project name (lowercase, underscores only):
> content_workflow

Where should project files be stored?
Default: ~/workspace/claude_projects/content_workflow/
Press Enter to accept or provide custom path:
> [Enter]

Creating project: content_workflow
Location: ~/workspace/claude_projects/content_workflow/

✓ Directory structure created
✓ Project registered
✓ Initializing project...

Now gathering requirements...
```

## After Creation

The command automatically:
1. Gathers project requirements
2. You can then run `/drupal-dev-framework:next` to start your first task

## Related Commands

- `/drupal-dev-framework:next` - Continue working (auto-detects project)
- `/drupal-dev-framework:status` - View project status
