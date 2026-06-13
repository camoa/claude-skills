---
description: "Set, update, or clear the project-local user playbook file path. Three modes: explicit path, --docs-only sentinel, or interactive detect-and-confirm. Mirrors /set-code-path precedent. Introduced v3.15.0."
allowed-tools: Read, Write, Edit, Bash, Skill, Glob
argument-hint: "[<path> | --docs-only]"
---

# Set User Playbook

Set or update the project's `**User Playbook:**` and `**User Playbook State:**` fields in `project_state.md`. Declares the project-local playbook file the framework loads alongside subscribed playbook sets.

## Usage

```
/ai-dev-assistant:set-user-playbook /abs/path/to/playbook.md   # explicit
/ai-dev-assistant:set-user-playbook --docs-only                # explicit opt-out
/ai-dev-assistant:set-user-playbook                             # interactive detect-and-confirm
```

## What this does

### Step 1 — Resolve project context

Run `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parse its JSON. Refuse with helpful message if no project resolved.

### Step 2 — Mode dispatch

#### Explicit path

Validate the path:
- Absolute path required
- File must exist (not a directory)
- File must be readable
- Path-safety filter (reject system roots `/`, `/etc`, `/usr`, etc., per `references/code-path-detection.md` precedent)

If validation passes, write:
```markdown
**User Playbook:** <abs path>
**User Playbook State:** set
```

#### `--docs-only` sentinel

Write:
```markdown
**User Playbook State:** docs-only-no-playbook
```

(no `**User Playbook:**` value line)

Confirms the project explicitly has no local playbook. Framework skips loading; never re-prompts.

#### Interactive (no arg)

Run detect-and-confirm scan:

1. Look in known locations (in order):
   - `<codePath>/docs/technical/guides/development-patterns.md`
   - `<codePath>/docs/conventions.md`
   - `<codePath>/docs/playbook.md`
   - `<codePath>/CONTRIBUTING.md`
   - `<codePath>/.claude/rules/playbook.md`
2. Glob: `<codePath>/docs/**/*playbook*.md`, `<codePath>/docs/**/*conventions*.md`, `<codePath>/docs/**/*patterns*.md`

For each found path, ask:
> Found `<path>`. Use as User Playbook? [y]es / [n]o / [s]how me what's in it / [next]

If user accepts → write `set` state with that path.
If no candidates found → ask:
> No playbook detected. Options:
> - Provide an absolute path
> - Run with `--docs-only` to declare none
> - Skip for now (state stays `unset`; framework asks again on next relevant command)

### Step 3 — Smoke-test load

After writing, run:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/playbook-read.sh" "<new path>"
```

Print play count + warning count. If parser warns, surface (informational).

### Step 4 — Confirm

Print:
```
✓ User Playbook configured:
  Path: <path or none>
  State: <set | docs-only-no-playbook>
  Plays detected: <N>
  Warnings: <N>
```

## Error cases

| Scenario | Behavior |
|---|---|
| No project context | Abort; exit 2 |
| Path doesn't exist | Refuse; exit 2; do NOT write |
| Path-safety violation (system root) | Refuse; exit 2; do NOT write |
| Path is a directory | Refuse; exit 2 |
| Write failure | Print error; exit 1 |

## Related

- `/ai-dev-assistant:set-playbook-sets` — set subscribed playbook sets
- `/ai-dev-assistant:playbook-active` — display current state
- `/ai-dev-assistant:playbook-capture` — append new entries to the file
- `/ai-dev-assistant:playbook-review` — walk existing entries for keep/update/remove
- `references/playbook-schema.md` — recommended file structure
