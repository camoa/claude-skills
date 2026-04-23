---
description: "Start a new development project. Trigger: 'start project', 'new module', 'initialize project', 'begin development'. Creates project structure and gathers requirements BEFORE any coding."
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
2. Asks where to store project files (uses saved base path from registry, or asks on first run)
3. **Asks where the code lives** (v3.11.0+ — see "Code path capture" below). Captures the codePath for downstream framework features (analysis agent, visual check, etc.).
4. Creates project folder structure:
   - `project_state.md` (with `**Code path:**` line populated from step 3)
   - `architecture/main.md`
   - `implementation_process/in_progress/`
   - `implementation_process/completed/`
5. Registers project in `~/.claude/drupal-dev-framework/active_projects.json` (including the `codePath` field)
6. Invokes `project-initializer` skill (v1.4.0 accepts a `code_path` arg)
7. Invokes `requirements-gatherer` skill
8. **Invokes `session-context-writer` skill with the new project name and path**

## Code path capture (v3.11.0+)

Before creating the project structure, ask the user:

> Where does the code for this project live? This is the path the analysis agent and other code-aware features will use. Options:
>   [Y] accept detected candidate: `<detected_path>`    (only shown when detection found a candidate)
>   [path] enter an absolute path to the code
>   [d] mark this project docs-only (no code base)
>   [s] skip for now — set later with `/drupal-dev-framework:set-code-path`

Detection strategies (in order, first match wins):
1. `$PWD` — if it contains `.git/`, `composer.json`, `package.json`, or Drupal markers
2. Sibling-of-memory-folder — e.g., memory at `~/workspace/claude_memory/projects/foo/` → check `~/workspace/foo/`

If the user skips, the project starts with `codePath` absent — the first framework feature that needs code will trigger detect+confirm again.

Pass the captured value to `project-initializer` as the `code_path` argument.

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
Default: ~/my/projects/content_workflow/    (from saved base path)
Press Enter to accept or provide custom path:
> [Enter]

Creating project: content_workflow
Location: ~/my/projects/content_workflow/

Structure created, project registered, initializing...

Now gathering requirements...
```

## After Creation

The command automatically:
1. Gathers project requirements
2. You can then run `/drupal-dev-framework:next` to start your first task

## Related Commands

- `/drupal-dev-framework:next` - Continue working (auto-detects project)
- `/drupal-dev-framework:status` - View project status
