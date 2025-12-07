---
description: Start a new development project with memory structure
allowed-tools: Read, Write, Bash(mkdir:*), Glob
argument-hint: <project-name>
---

# New Project

Initialize a new development project.

## Usage

```
/drupal-dev-framework:new my_project_name
```

## What This Does

1. Asks where to store project files (default: `../claude_projects/$1/`)
2. Creates project folder at chosen location
3. Sets up directory structure:
   - `project_state.md`
   - `architecture/`
   - `implementation_process/in_progress/`
   - `implementation_process/completed/`
3. Invokes `project-initializer` skill
4. Invokes `requirements-gatherer` skill

## Project Name Requirements

- Lowercase letters and underscores only
- Cannot already exist at chosen path

## Example

```
/drupal-dev-framework:new content_workflow

Where should project files be stored?
Default: ../claude_projects/content_workflow/
> [Enter to accept]

Creating project: content_workflow
Location: ../claude_projects/content_workflow/

Structure created:
├── project_state.md
├── architecture/
│   └── main.md
└── implementation_process/
    ├── in_progress/
    └── completed/

Now gathering requirements...
```

## Next Steps After Creation

1. Answer requirements questions
2. Run `/drupal-dev-framework:next` to get intelligent next action recommendation
