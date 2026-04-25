---
description: "Clean up abandoned worktrees in the current project. Lists each worktree with state (branch merged? task completed?). Per-worktree confirm; never bulk-removes silently. Honors git's refusal on uncommitted changes. Introduced v3.16.0."
allowed-tools: Read, Bash, Skill
---

# Worktree Prune

List and selectively remove worktrees in the current project. Each worktree gets a per-item confirm prompt; never bulk-removes silently.

## Usage

```
/drupal-dev-framework:worktree-prune
```

## What this does

### Step 1 — Resolve project context

Invoke `project-state-reader`. Refuse if no project resolved.

### Step 2 — Refuse if in a worktree

Invoke `scripts/worktree-detect.sh "$PWD"`. If `in_worktree: true`:

> Refuse: "You are currently in a worktree. Run /worktree-prune from the main tree."

### Step 3 — Enumerate worktrees

```bash
git worktree list --porcelain
```

For each entry, parse:
- `worktree <path>` — absolute path
- `HEAD <sha>` — current HEAD
- `branch <ref>` — current branch (or "(detached)")

Skip the main worktree (the entry where `worktree == git rev-parse --show-toplevel` of main).

### Step 4 — Annotate each worktree

For each worktree:
- Derive task name from path basename (e.g., `.worktrees/feature-foo` → `feature-foo`)
- Look up task state: check if folder exists in `<project>/implementation_process/in_progress/**/<task>` vs `completed/**/<task>` vs neither
- Check if branch is merged into `main`: `git branch --merged main | grep -F "<branch>"` → boolean
- Mark candidates for cleanup: (task in `completed/`) OR (branch merged into main) → "candidate"
- Mark NOT candidates: (task in `in_progress/`) AND (branch not merged) → "active"

### Step 5 — Print + per-worktree prompt

Order: candidates first, then active. For each:

```
[i]/[N] Worktree: <path>
  Branch: <branch>  (merged into main: yes/no)
  Task:   <name>  (state: completed | in_progress | unknown)
  Last commit: <YYYY-MM-DD HH:MM>

Remove? [y]es / [n]o / [q]uit
```

- `[y]` → run `git worktree remove "<path>"`. If git refuses (uncommitted changes, locked):
  - Print git's error verbatim
  - Offer `[f]orce / [n]o`
  - On `[f]` → run `git worktree remove --force "<path>"` (ONLY on explicit user confirmation)
  - On `[n]` → skip; continue
  Otherwise: also offer `Delete branch <branch> too? [y/n]` (only when branch is merged); on `[y]` → `git branch -d "<branch>"`.
- `[n]` → skip; continue.
- `[q]` → break loop; print summary; exit.

### Step 6 — Final summary

```
Pruned <K> worktrees.
  Removed: <list>
  Kept:    <N> (skipped or active)

Run `git worktree list` to verify.
```

## Error cases

| Scenario | Behavior |
|---|---|
| No project context | Abort; exit 2 |
| In a worktree | Refuse; exit 0 |
| `git worktree list` fails (not in a git repo) | Refuse; exit 2 |
| Single worktree (only main) | Print "No worktrees to prune"; exit 0 |
| `git worktree remove` fails on uncommitted changes | Honor refusal; offer `[f]orce`; require explicit user confirm |
| Branch deletion fails (unmerged) | Honor git's refusal; print message; continue with worktree-only removal |

## Soft-nudge posture

- Per-worktree confirm — never bulk-removes
- Force-remove requires explicit user `[f]` confirmation per worktree
- Branch deletion is opt-in per worktree (and only offered when merged)
- `[q]uit` exits cleanly; partial cleanup preserved

## Related

- `/drupal-dev-framework:worktree` — create worktrees
- `references/worktree-conventions.md` — full conventions
