---
description: "Set or clear the active playbook sets for the current project. Validates each set ID via dev-guides-navigator before writing. Accepts comma-separated list, literal `none` (explicit opt-out), or no arg (interactive). Introduced v3.15.0."
allowed-tools: Read, Write, Edit, Bash, Skill
argument-hint: [<set-id-1,set-id-2,...> | none]
---

# Set Playbook Sets

Set or update the project's `**Playbook Sets:**` field in `project_state.md`. The framework subscribes the project to the listed dev-guides categories, loading them at every phase entry alongside other dev-guides.

## Usage

```
/drupal-dev-framework:set-playbook-sets                                       # interactive
/drupal-dev-framework:set-playbook-sets drupal/best-practices/camoa           # single set
/drupal-dev-framework:set-playbook-sets drupal/best-practices/camoa,drupal/best-practices/lullabot  # multiple
/drupal-dev-framework:set-playbook-sets none                                  # explicit opt-out
```

## What this does

### Step 1 — Resolve project context

Invoke `project-state-reader` to get current `playbookSets[]`, `playbookSetsSource`, and `folder`. Refuse with helpful message if no project resolved.

### Step 2 — Parse arg

Three cases:

- **No arg** → interactive: print current state, ask user to enter new value (comma-separated, or `none`, or `default` to clear).
- **Arg `none`** → set to literal `none` (explicit opt-out).
- **Arg `default`** → remove the line from `project_state.md` (revert to plugin.json default).
- **Arg with comma-separated IDs** → split on commas, trim whitespace, validate each.

### Step 3 — Validate set IDs (if not `none`/`default`)

For each set ID, invoke `dev-guides-navigator` to confirm the set exists:

```bash
curl -s https://camoa.github.io/dev-guides/llms.txt | grep -F "/<set-id>/"
```

If a set ID doesn't resolve, refuse with a suggestion list (the closest matches by Levenshtein on `llms.txt` topic names) and exit without writing.

### Step 4 — Write to `project_state.md`

Use `Edit` to update the `**Playbook Sets:**` line. If the line doesn't exist, append it after the last metadata line (typically after `**Code path:**` or `**Code Path State:**`).

Format:
```markdown
**Playbook Sets:** drupal/best-practices/camoa, drupal/best-practices/lullabot
```

Or, for opt-out:
```markdown
**Playbook Sets:** none
```

For `default`, remove the line entirely.

### Step 5 — Confirm

Print:
```
✓ Playbook Sets updated for <project>:
  Active sets: <list>
  Source: <explicit|explicit-none|default>

Next phase command (research/design/implement/complete) will load these sets via dev-guides-navigator.
```

## Error cases

| Scenario | Behavior |
|---|---|
| No project context | Abort; exit 2; suggest `/next` to select a project |
| Invalid set ID (doesn't resolve via navigator) | Print suggestion list; refuse; exit 2; do NOT write |
| `project_state.md` missing | Abort; exit 2; suggest `/new` to initialize project |
| Write failure | Print error; exit 1 |

## Related

- `/drupal-dev-framework:set-user-playbook` — set the project-local playbook file
- `/drupal-dev-framework:playbook-active` — display current active sets + local playbook + last conflicts
- `references/playbook-schema.md` — local playbook structure (not relevant to sets)
- `dev-guides-navigator` — set ID resolution and loading
