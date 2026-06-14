---
name: project-initializer
description: Use when starting a new development project — creates memory folder structure with project_state.md (including codePath), architecture scaffolding, and registers project. Accepts optional code_path argument.
version: 1.5.0
model: inherit
user-invocable: false
allowed-tools: Bash, Read, Write
---

# Project Initializer

Create a new project with memory structure for the 3-phase workflow.

## Activation

Activate when you detect:
- "Start new project" or "Initialize project X"
- `/ai-dev-assistant:new` command
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

Read the registry at `~/.claude/ai-dev-assistant/active_projects.json`. Check if `projectsBase` is set.

**If `projectsBase` exists** — use it as default:
```
Where should project files be stored?

Default: {projectsBase}/{project_name}/

Options:
1. Accept default
2. Enter custom path

Your choice:
```

**If `projectsBase` is NOT set** (first-time setup) — ask:
```
Where do you keep your project memory files?
This folder will store architecture docs, task files, and project state.

Enter the base path (all projects will be created as subfolders here):
```

Save the chosen base path as `projectsBase` in the registry (see Step 7).

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
**Status:** Initializing
**Path:** {full_path_to_project_folder}
**Code path:** {absolute_code_path OR (docs-only) OR omit-entirely-if-caller-did-not-provide}
**Frameworks:** {when code path is known: run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-frameworks.sh" "<code_path>"` and write the `jq -r 'join(", ")'` result (e.g. `drupal, nextjs`); omit this line entirely when code path is unknown or the returned array is empty}

## Overview
{To be filled during requirements gathering}

## Scope
This project includes:
- {To be defined}

## Requirements
{Populated by requirements-gatherer}

## Current Implementation Task
Working on: None - define tasks after requirements are gathered
File: -

## Up Next
Queued: {Tasks to work on after current task}

## Completed Implementation Tasks
{Empty initially}

## Key Decisions
{Empty initially}

## Current Focus
Initial setup - gathering requirements
```

**Notes:**
- Never write an empty or placeholder `**Frameworks:**` line. The reader treats absence as `[]`. Only write the line when `detect-frameworks.sh` returns a non-empty array.
- The project does NOT have a phase. Each TASK has its own phase (Research → Architecture → Implementation)
- Multiple tasks can be in `implementation_process/in_progress/` simultaneously
- Task files in `in_progress/` contain the task's current phase and progress
- Move completed task files to `implementation_process/completed/`

### 6. Create Empty architecture/main.md

Use `Write` tool:
```markdown
# {Project Name} Architecture

{To be designed in Phase 2}
```

### 7. Register Project

Add project to the registry at `~/.claude/ai-dev-assistant/active_projects.json`.

First, ensure the directory exists:
```bash
mkdir -p ~/.claude/ai-dev-assistant
```

Then read existing registry (or create new if doesn't exist) and add the project:

**Registry Schema:**
```json
{
  "version": "1.1",
  "projectsBase": "{user's chosen base path for all projects}",
  "projects": [
    {
      "name": "{project_name}",
      "path": "{full_path_to_project}",
      "codePath": "{absolute path to code OR null}",
      "created": "{YYYY-MM-DD}",
      "lastAccessed": "{YYYY-MM-DD}",
      "status": "active"
    }
  ]
}
```

- `projectsBase` — set once on first project creation, reused as default for all future projects
- `path` — always the full absolute path to the specific project folder (memory folder)
- `codePath` — **(added v3.11.0)** absolute path to the code being worked on. `null` for docs-only projects. Optional; pre-v3.11.0 entries without it treated as "unknown" and trigger the first-use detect+confirm flow when a feature needs code. Source of truth is `project_state.md`; this is the cache.
- No `phase` field — phase is tracked per-task in task files, not per-project

Use `Read` to load existing registry, then `Write` to save updated version with new project appended.

If registry doesn't exist, create it with `projectsBase` and this project.

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

Once requirements-gatherer completes and user confirms, show — in order:

**(a) Playbook-config nudge (v4.2.2+ — single source of truth).** Print one line before the `/next` hint:

```
💡 Optional next step: configure your playbook before the first task.
   /ai-dev-assistant:set-playbook-sets — choose opinion-set(s) (default: drupal/best-practices/camoa)
   /ai-dev-assistant:set-user-playbook — point at a project-local playbook.md
   Playbook loads at every phase entry; configuring now means your first task gets the active opinion-set
   from the start. Skip if you want plain dev-guides only — /next will re-surface this nudge.
```

This nudge is the canonical surface for new-project playbook discoverability — `/new` and `/next` (inline-create path) both invoke this skill, so the nudge fires for every caller. Do NOT duplicate this text in caller commands.

**(b) Final handoff:**

```
Requirements gathering complete.

Run `/ai-dev-assistant:next` to get your next recommended action.
```

Do NOT manually list commands like `/research` or `/design`. Always direct to `/next` for intelligent routing.

## Stop Points

STOP and wait for user response:
- After asking for project name
- After asking for storage location
- Before creating folders if path exists
- After showing confirmation
