# Code Path Detection — Strategies

**Introduced:** ai-dev-assistant v3.11.0
**Consumers:** `/new` (project creation), `/set-code-path` (interactive detect+confirm), any feature that invokes the first-use flow on a project with unknown `codePath`.

Detection runs when a feature needs `codePath` but the project has none declared. Propose a candidate and let the user confirm. Never auto-accept.

## Strategies, in priority order

First match wins. If no strategy matches, fall back to a cold prompt (no pre-filled candidate).

### Strategy 1 — `$PWD` looks like code

If the current working directory contains any of the following markers, propose `$PWD`:

- `.git/` (any git repository)
- `composer.json` (PHP project)
- `package.json` (Node / JS project)
- `sites/default/` (docroot convention)
- `docroot/` (alternate docroot layout)
- `web/` + `composer.json` at sibling depth (dual web+composer layout)

Rationale: user invoked the command from where they intend the code to live. This is the common Pattern-2 case (framework-from-inside-code-base).

### Strategy 2 — Sibling of memory folder

If the active project's memory folder is `~/workspace/claude_memory/projects/<name>/`, check if `~/workspace/<name>/` exists and looks like code (same markers as Strategy 1 applied). Propose it if yes.

This is the common Pattern-1 case (claude_code_project + separate code repo): user has a memory project at one path and its code at a peer location.

### Strategy 3 — Memory folder's parent-of-parent + `/docroot/modules/custom/<project>`

Site-tree pattern where the memory folder sits under a site's tree. Less common; low priority. Evaluate after shipping v3.11.0 if real-world friction surfaces.

## What to show the user

```
Detected codePath candidate: /home/user/workspace/adc_theme
  (git repo at $PWD)

Current value: unknown

Confirm? Options:
  [Y] accept the detected candidate
  [n] cancel (no change)
  [o] enter a different path
  [d] mark this project docs-only
```

The "reason" parenthetical (`git repo at $PWD`) is required so the user knows WHY the framework proposed that path. Strategy names:

- Strategy 1: "git repo at $PWD" / "composer.json at $PWD" / "package.json at $PWD" / "docroot at $PWD"
- Strategy 2: "sibling of memory folder at ~/workspace/<name>/"

## Fallback — no detection

If no strategy matches, show the cold prompt:

```
Where does the code for this project live?
  [path] enter an absolute path
  [d] mark this project docs-only
  [s] skip for now — the first code-using feature will ask again
```

## Acceptance rules

- Detected candidate must be an absolute path after `realpath -m` normalization.
- Must still exist on disk at the moment of detection (if not, skip that strategy and try the next).
- User's explicit path override is accepted even if the path does not currently exist (with a warning — see `/set-code-path` for the "future-path" handling).

### Safety filter on detected + user-entered paths

Regardless of source (detection, explicit arg, or interactive prompt), the following paths are **hard-rejected** before accept:

- `/`, `/etc`, `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/boot`, `/sys`, `/proc`, `/dev`, `/var`, `/opt`, `/root`
- Any ancestor of `$HOME` (e.g., `/home`, `/Users`)

Paths outside `$HOME` but not in the hard-reject list (e.g., `/srv/myapp`, `/mnt/code`) are **warn-but-allow**: prompt for explicit confirmation (default no). See `/set-code-path` the "Acceptance / rejection rules" section for the canonical rule set — all consumers of this reference MUST apply the same filter.

## Ordering is intentional

`$PWD` > sibling. In doubt, prefer the cwd that the user explicitly launched Claude from. Keeps the detection predictable: "Claude suggests where I am, unless I'm clearly in a docs/knowledge location that has a sibling code repo."

## Three distinct null-like states

Consumers MUST distinguish these — they look similar at runtime but have different semantics:

| State | `codePath` (runtime) | `project_state.md` line | `active_projects.json` | Warnings | Meaning | Action |
|---|---|---|---|---|---|---|
| **unknown** | `null` | line absent OR value blank | `codePath: null` | `code_path_unknown` | Never set. First-use flow must detect+confirm. | Run detect+confirm |
| **docs-only** | `null` | `**Code path:** (docs-only)` | `codePath: null` | (none) | User intentionally declared no code. | Skip code-requiring features silently |
| **set** | `/abs/path` | `**Code path:** /abs/path` | `codePath: "/abs/path"` | `code_path_missing` iff dir absent at read time | Normal case. | Use the path |

Key distinction: both "unknown" and "docs-only" produce `codePath: null` at runtime, but **only "unknown" emits the `code_path_unknown` warning**. Consumers branch on the warning, not on the null value itself:

- `warnings[] contains "code_path_unknown"` → trigger detect+confirm flow
- `codePath: null` AND no `code_path_unknown` warning → docs-only; skip code read silently

The `project-state-reader` skill's contract guarantees this. Do not guess from `codePath` alone.

## Extension points

New strategies can be added in future versions by:
1. Adding a new numbered section to this file
2. Updating the detection implementation (command-body instructions in `/new` and `/set-code-path`)
3. Noting the addition in the release's CHANGELOG

Schema-level changes (e.g., multiple candidate paths, monorepo sub-path guidance) require a design discussion — not bundled into minor-version adds.
