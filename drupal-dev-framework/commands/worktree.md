---
description: "Create a git worktree for parallel task execution. Sets up `.worktrees/<task>/` on `feature/<task>` branch, runs auto-detect setup (composer install, npm install), pre-seeds session-context. Drupal/DDEV-aware. Soft-nudge — never auto-creates without confirmation. Introduced v3.16.0."
allowed-tools: Read, Write, Edit, Bash, Skill
argument-hint: <task-name> [--base <ref>] [--branch <name>] [--with-baseline] [--no-ddev-check]
---

# Worktree

Create a git worktree at `.worktrees/<task_name>/` on branch `feature/<task_name>` so this task can run in parallel with another Claude session on the same project. Reuses the superpowers `using-git-worktrees` precedent + extends with Drupal/DDEV/task-lifecycle awareness.

## Usage

```
/drupal-dev-framework:worktree <task-name>                              # default flow
/drupal-dev-framework:worktree <task-name> --base origin/main           # branch from a specific ref
/drupal-dev-framework:worktree <task-name> --branch task/<custom>       # custom branch name
/drupal-dev-framework:worktree <task-name> --with-baseline              # opt-in baseline tests
/drupal-dev-framework:worktree <task-name> --no-ddev-check              # skip DDEV name: warning
```

See `references/worktree-conventions.md` v1.1 for the full convention — including §11, how this command relates to Claude Code's native `claude --worktree` flag, PR-based worktrees, `.worktreeinclude`, `worktree.baseRef`, and `worktree.bgIsolation`.

## What this does

### Step 1 — Resolve task + project context

Invoke `project-state-reader` to get `folder` (project path), `codePath`, `worktreeByDefault`. Resolve task folder under `<project>/implementation_process/**/<task-name>/`. Refuse with helpful message if task folder doesn't exist.

### Step 2 — Refuse if already in a worktree

Invoke `scripts/worktree-detect.sh "$PWD"`. If `in_worktree: true`:

> Refuse with: "You are already in a worktree at `<path>` (branch `<branch>`). Run from the main tree to create a sibling worktree, or `cd` to the main tree first."

Exit 0.

### Step 3 — Resolve worktree directory

Per superpowers priority:

1. `.worktrees/` exists → use it
2. `worktrees/` exists → use it (if `.worktrees/` doesn't exist)
3. `CLAUDE.md` line `worktree-directory: <path>` → use that
4. Ask user: "Where should I create worktrees? [1] `.worktrees/` (recommended) [2] `worktrees/`"

### Step 4 — Verify gitignored

```bash
git check-ignore -q "<chosen-dir>"
```

If NOT ignored:
- Append `<chosen-dir>` to `.gitignore`
- `git add .gitignore && git commit -m "chore: ignore worktree directory"`
- Proceed

### Step 5 — DDEV check (Drupal-specific)

If `<codePath>/.ddev/config.yaml` exists AND has a `name:` key:

> Print warning: "DDEV is configured with `name: <x>` in `.ddev/config.yaml`. Multiple worktrees with the same DDEV name will conflict at `ddev start`. Recommended: remove the `name:` line and commit, OR use `--no-ddev-check` to proceed anyway."
>
> Ask: "[c]ontinue / [a]bort / [s]how-instructions"

On `[a]` → exit 0 cleanly.
On `[s]` → print: "Edit `.ddev/config.yaml` and remove the line starting with `name:`. Save, commit (`git add .ddev/config.yaml && git commit -m 'chore: remove DDEV name for worktree compatibility'`), then re-run /worktree." Then exit 0.
On `[c]` → continue (user knows the risk).

If `--no-ddev-check` was passed, skip this step entirely.

### Step 6 — Create worktree

Determine BASE:
- `--base <ref>` flag → use it
- Default → `git rev-parse HEAD` (current commit)

The HEAD default matches the `worktree.baseRef: "head"` semantic — Drupal task work often sits on uncommitted local patches a `"fresh"` base would drop. This command does not read the `worktree.baseRef` setting (that setting governs Claude Code's native `--worktree`); pass `--base origin/main` for a clean base. See `references/worktree-conventions.md` §11.4.

Determine BRANCH:
- `--branch <name>` flag → use it
- Default → `feature/<task-name>`

Run:
```bash
git worktree add ".worktrees/<task-name>" -b "$BRANCH" "$BASE"
```

If creation fails (existing branch with different HEAD, dirty tree blocking, etc.) → surface the error verbatim and refuse.

### Step 7 — Auto-detect setup

`cd` into the new worktree. Detect and run:

| File present | Setup command |
|---|---|
| `composer.json` (Drupal/PHP) | `composer install` |
| `package.json` (Node) | `npm install` (or `pnpm install` / `yarn install` per lockfile) |

Setup runs sequentially. Failures print but don't auto-rollback (user can fix and re-run).

### Step 8 — Optional baseline

If `--with-baseline` was passed:

| Available | Run |
|---|---|
| `vendor/bin/phpunit` | `vendor/bin/phpunit` |
| `npm test` script in package.json | `npm test` |

Print pass/fail summary. If failures and `--ignore-baseline` not passed → refuse to declare worktree ready.

Default: skip baseline (Drupal/DDEV setups make this heavy).

### Step 9 — Pre-seed session-context

Invoke `session-context-writer` skill from inside the worktree (`$PWD` is now the worktree path) with:

- `project: <project_name>` (from project-state-reader)
- `projectPath: <abs project memory folder>`
- `task: null`
- `taskPath: null`

This ensures the worktree's session-context file exists; the user's first `/research` or `/implement` populates the task field.

### Step 10 — Print summary

```
✓ Worktree created at .worktrees/<task-name>
  Branch:  feature/<task-name> from <BASE-ref>
  Setup:   composer install ✓ | npm install ✓
  Session: pre-seeded for project <name>

Next:
  cd .worktrees/<task-name>
  /drupal-dev-framework:implement <task-name>

Or run /worktree-prune later to clean up when done.
```

## Error cases

| Scenario | Behavior |
|---|---|
| No project context | Abort; exit 2 |
| Task folder doesn't exist | Refuse; suggest `/research <task>` first; exit 2 |
| Already in a worktree | Refuse with helpful message; exit 0 |
| `.ddev/config.yaml` has `name:` set AND no `--no-ddev-check` | Show warning; user picks continue/abort |
| Dirty tree blocks `git worktree add` | Surface git's error verbatim; suggest commit/stash; exit 1 |
| Branch already exists pointing at a different ref | Surface error; suggest `--branch` or branch deletion; exit 1 |
| Setup fails (composer install error, npm install error) | Print error; leave worktree created; exit 0 (user resumes manually) |
| Baseline fails AND no `--ignore-baseline` | Refuse to declare ready; exit 1; user can `--ignore-baseline` |

## Soft-nudge posture

- Never creates without explicit confirmation when there's a DDEV `name:` warning
- Never auto-edits `.ddev/config.yaml`
- Never `--force` removes anything
- User can decline at every interactive step

## Related

- `/drupal-dev-framework:worktree-prune` — cleanup
- `/drupal-dev-framework:implement` — invokes worktree recommendation pre-step
- `/drupal-dev-framework:complete` — invokes worktree merge prompt at task end
- `references/worktree-conventions.md` — full conventions; §11 covers Claude Code's native worktree support
- `superpowers:using-git-worktrees` — generic creation pattern (drupal-dev-framework adds task-aware lifecycle)
- Claude Code's native worktree support — `https://code.claude.com/docs/en/worktrees` (the `claude --worktree` / `-w` CLI flag, PR-based worktrees, `.worktreeinclude`). The framework's `/worktree` and the native flag are complementary entry points — see `references/worktree-conventions.md` §11.
