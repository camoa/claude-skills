---
description: Start a new Drupal development project with memory structure
allowed-tools: Read, Write, Bash(mkdir:*), Glob
argument-hint: <project-name>
---

# New Project

Initialize a new Drupal development project.

## Usage

```
/drupal-dev-framework:new my_module_name
```

## What This Does

1. Creates project folder in `~/workspace/claude_memory/$1/`
2. Sets up directory structure:
   - `project_state.md`
   - `architecture/`
   - `implementation_process/in_progress/`
   - `implementation_process/completed/`
3. Invokes `project-initializer` skill
4. Invokes `requirements-gatherer` skill

## Project Name Requirements

- Lowercase letters and underscores only
- Must be valid Drupal module name format
- Cannot already exist in claude_memory/

## Example

```
/drupal-dev-framework:new content_workflow

Creating project: content_workflow
Location: ~/workspace/claude_memory/content_workflow/

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
2. Run `/drupal-dev-framework:research <topic>` for Phase 1
3. Run `/drupal-dev-framework:design` for Phase 2
