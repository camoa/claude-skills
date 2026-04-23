---
description: "Use when a user wants to set, update, or clear a drupal-dev-framework project's codePath — the absolute path to the code the project is editing (distinct from the memory folder). Prompts detect+confirm if no argument given; accepts explicit path or (docs-only) sentinel. Updates project_state.md (source of truth) and syncs registry cache. Introduced v3.11.0."
allowed-tools: Read, Write, Edit, Bash, Skill
argument-hint: [<path> | --docs-only]
---

# Set Code Path

Set or update the `codePath` metadata for the active drupal-dev-framework project. `codePath` tells future framework features (analysis agent, visual check, live-e2e, etc.) where the project's code actually lives — which may be different from the memory folder in claude_code_project workflows.

## Usage

```
/drupal-dev-framework:set-code-path /absolute/path/to/code
/drupal-dev-framework:set-code-path --docs-only
/drupal-dev-framework:set-code-path                       # interactive: detect + confirm
```

## What this does

1. Resolves the active project from `session_context.json` (`projectPath`). If no project active, prompts the user to pick one via `/drupal-dev-framework:next` first.
2. **Reads current value** via `project-state-reader` skill (so the confirm prompt can show what's changing).
3. **Resolves new value:**
   - With `<path>` arg: `realpath -m` normalize; validate exists (unless `--docs-only` or the path resolves to an acceptable path that may not yet exist; in that case, warn and continue).
   - With `--docs-only`: set to `(docs-only)` sentinel (null at runtime).
   - With no arg: run the detect+confirm flow (see below).
4. **Writes to `project_state.md`** — the `**Code path:**` line (replace if exists, insert in the top metadata block if absent).
5. **Syncs registry cache** — updates `~/.claude/drupal-dev-framework/active_projects.json`'s matching entry `codePath` field.
6. **Reports** what changed.

## Detect + confirm flow (no arg provided)

When called without arguments, propose a candidate via the strategies and priority order defined in `references/code-path-detection.md`. **That reference is the single source of truth** — do not re-enumerate strategies here; consult it for markers, ordering, and acceptance rules.

Summary: first match wins across the reference's strategy list; if no strategy matches, fall back to the reference's cold-prompt form. If any candidate found, present the confirm prompt:

```
Detected codePath candidate: /absolute/path
Current value: (docs-only | /other/path | unknown)

Confirm? Options:
  [Y] accept the detected candidate
  [n] cancel (no change)
  [o] enter a different path
  [d] mark this project docs-only
```

If no candidate detected, fall back to cold prompt with the same options.

## What it writes

### project_state.md

In the top metadata block, within the first 10 lines (just after the H1 and `**Created:**`):

```markdown
# <Project Name>

**Created:** YYYY-MM-DD
**Code path:** /absolute/path/to/code
...
```

If the `**Code path:**` line exists, replace its value. Otherwise insert it after `**Created:**` (or at end of metadata block if `**Created:**` absent).

### active_projects.json

Read, modify, write. For the matching project entry, set `codePath` to the resolved value (absolute path or `null`).

## Acceptance / rejection rules

- **Path accepted:** must be absolute after `realpath -m`. If the path does not currently exist, warn but allow — user may be declaring a future-work path. Warning: `"Note: /path does not currently exist. Saved anyway; /drupal-dev-framework:set-code-path again when it exists to clear the warning."`
- **Path rejected (hard):** any of the following aborts with an error:
  - Contains newlines or null bytes
  - Cannot be normalized by `realpath -m`
  - **Is a dangerous system root:** `/`, `/etc`, `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/boot`, `/sys`, `/proc`, `/dev`, `/var`, `/opt`, `/root`, or any ancestor of `$HOME` (e.g., `/home`). These are never valid code paths and always indicate user error or malicious input.
- **Path warn-but-allow:** resolves outside `$HOME` but not in the hard-reject list (e.g., `/srv/myapp`, `/mnt/code`). Show: `"Warning: <path> is outside your home directory. Proceed? [y/N]"`. Default no. User must type `y` to accept.
- **`--docs-only`:** always accepted.
- **Cancel (user chooses [n]):** no change; exit 0 with "No change."

## Examples

```
/drupal-dev-framework:set-code-path /home/user/workspace/my-module

→ Reading project at /home/user/.../projects/my_project
  Current codePath: unknown
  Setting codePath to: /home/user/workspace/my-module
  ✓ Updated project_state.md
  ✓ Synced active_projects.json
```

```
/drupal-dev-framework:set-code-path --docs-only

→ Setting codePath to: (docs-only)
  ✓ Updated project_state.md
  ✓ Synced active_projects.json
```

```
/drupal-dev-framework:set-code-path

→ No argument provided. Running detect+confirm...
  Detected candidate: /home/user/workspace/adc_theme (git repo at $PWD)
  Current value: unknown

  Confirm? (Y/n/o/d): Y

  ✓ Updated project_state.md
  ✓ Synced active_projects.json
```

## Errors

| Error | Resolution |
|---|---|
| `No active project. Run /drupal-dev-framework:next first.` | Select a project via /next, then retry. |
| `Path '<p>' is not absolute after normalization.` | Provide a valid absolute path. |
| `Path '<p>' contains invalid characters.` | No newlines or null bytes; re-enter. |
| `project_state.md not found at <p>` | Ensure the project is properly initialized (should not happen for /new-created projects). |

## Related commands

- `/drupal-dev-framework:new` — also captures codePath during project creation (no need to run set-code-path afterward)
- `/drupal-dev-framework:propose-epics` — consumes codePath (triggers first-use detect+confirm if unknown)
- `/drupal-dev-framework:status` — shows codePath in project overview

## Discoverability

- README Commands table
- Command frontmatter `description` (this file)
- Plugin CLAUDE.md Project Metadata section (v3.11.0+)
- marketplace.json description (v3.11.0)
- `/drupal-dev-framework:next` references when codePath is unknown and a feature needs code
