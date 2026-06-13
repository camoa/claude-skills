---
description: "Start a new development project. Trigger: 'start project', 'new module', 'initialize project', 'begin development'. Creates project structure and gathers requirements BEFORE any coding."
allowed-tools: Read, Write, Bash(mkdir:*), Glob, Task
argument-hint: "[project-name]"
---

# New Project

Initialize a new development project with complete memory structure.

## Usage

```
/ai-dev-assistant:new                  # Interactive - asks for name
/ai-dev-assistant:new my_project       # Direct - with name
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
5. Registers project in `~/.claude/ai-dev-assistant/active_projects.json` (including the `codePath` field)
6. Invokes `project-initializer` skill (v1.4.0 accepts a `code_path` arg)
7. Invokes `requirements-gatherer` skill
8. **Runs `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" null null`** (Bash) with the new project name and path (no task yet)

## Code path capture (v3.11.0+)

Before creating the project structure, ask the user:

> Where does the code for this project live? This is the path the analysis agent and other code-aware features will use. Options:
>   [Y] accept detected candidate: `<detected_path>`    (only shown when detection found a candidate)
>   [path] enter an absolute path to the code
>   [d] mark this project docs-only (no code base)
>   [s] skip for now — set later with `/ai-dev-assistant:set-code-path`

Detection strategies, priority order, markers, and acceptance/safety rules are defined in `references/code-path-detection.md` — **that is the single source of truth**. Do not re-implement or re-enumerate strategies here; consult the reference.

If the user skips, the project starts with `codePath` absent — the first framework feature that needs code will trigger detect+confirm again.

Pass the captured value to `project-initializer` as the `code_path` argument (absolute path, or the literal string `(docs-only)` for docs-only, or omit for skip).

## Project Name Requirements

- Lowercase letters, numbers, and underscores only
- Must be a valid directory name
- Cannot already exist at chosen path

## Example Flow

```
/ai-dev-assistant:new

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
2. **Surfaces a playbook-config nudge.** Owned by `project-initializer` skill Step 10(a) (v4.2.2+; single source of truth). The skill prints the nudge before the final `/next` hint, suggesting `/set-playbook-sets` and `/set-user-playbook` before the first task. `/next` re-surfaces the nudge if the user skips it.
3. You can then run `/ai-dev-assistant:next` to start your first task.

## Related Commands

- `/ai-dev-assistant:next` - Continue working (auto-detects project)
- `/ai-dev-assistant:status` - View project status
