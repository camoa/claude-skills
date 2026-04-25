# Worktree Conventions v1.0

**Introduced:** drupal-dev-framework v3.16.0
**Owner:** `commands/worktree.md`, `commands/worktree-prune.md`, `commands/implement.md` (recommendation), `commands/complete.md` (lifecycle)
**Consumers:** the framework's worktree commands + the helper scripts (`worktree-detect.sh`, `worktree-signals.sh`)

This reference documents the framework's git-worktree conventions for parallel task execution within a single drupal-dev-framework project. It establishes directory layout, branch naming, detection signals, lifecycle paths, and DDEV/Drupal-specific concerns. Reuses the superpowers `using-git-worktrees` skill's core patterns; extends with task-aware lifecycle and Drupal awareness.

## 1. Why worktrees

Two Claude Code sessions on the same workspace collide on:

- `~/.claude/drupal-dev-framework/sessions/<md5($PWD)>.json` — same `$PWD` = same hash = last writer wins
- The git working tree itself (concurrent edits, dirty branches, conflicting commits)

A worktree at `.worktrees/<task_name>/` solves both: distinct `$PWD` → distinct hash → independent session-context file. The framework treats this as the standard mechanism for parallel work, not an exotic feature.

## 2. Directory priority

When the framework needs to choose where to create a worktree:

1. `.worktrees/` (preferred — hidden, project-local) — use if exists
2. `worktrees/` (alternative) — use if exists and `.worktrees/` doesn't
3. `CLAUDE.md` `worktree-directory:` preference line — use if specified
4. Ask user: "1. `.worktrees/` (recommended) | 2. `worktrees/`" — pick one

Both directories are project-local; never `~/.config/...` or other global locations. Each project owns its own worktree set.

## 3. Branch naming

`feature/<task_name>` — matches the camoa-skills marketplace's existing PR-branch convention.

Override: `--branch <custom>` flag on `/worktree`. Honored when passed; default convention applies otherwise.

## 4. Gitignore requirement

The chosen worktree directory MUST be gitignored before creation. Verification:

```bash
git check-ignore -q <directory>
```

If the directory is NOT ignored:
1. Append the directory name to `.gitignore` (one line, e.g. `/.worktrees/`)
2. `git add .gitignore && git commit -m "chore: ignore worktree directory"`
3. Proceed with worktree creation

This prevents the catastrophic "worktree contents committed to repo" failure mode.

## 5. Detection signals (for `/implement` recommendation)

The framework recommends a worktree on `/implement <task>` when at least one HIGH-strength signal fires AND the user is not already in a worktree.

| Signal | Strength | Evidence |
|---|---|---|
| `another_task_active` | HIGH | A different task folder has `implementation.md` AND `git log --since="2 hours" --name-only` shows commits to its tracked files |
| `dirty_tree` | HIGH | `git status --porcelain` shows modified files matching another task's `implementation.md` Files Created/Modified list |
| `multi_session` | MEDIUM-HIGH | 2+ session-context files in `~/.claude/drupal-dev-framework/sessions/` reference the same project (signal that the user has been working on this project from multiple workspaces) |
| `--worktree` user flag | EXPLICIT | User explicitly requested |
| `Worktree By Default: true` in `project_state.md` | EXPLICIT | Project opts into worktree-always |

**Recommendation threshold:** at least one HIGH or EXPLICIT signal. MEDIUM-HIGH signals alone are informational, not blocking.

**Suppression:** if the user is already in a worktree (per `worktree-detect.sh`), detection is skipped entirely.

## 6. Lifecycle paths at `/complete`

When the current task is on a worktree, `/complete` offers three paths. Default = 3 (least destructive).

### Path 1 — Merge back to main + remove worktree

```bash
cd <main_path>
git checkout main
git merge --no-ff feature/<task>
# on conflict: abort merge; print conflict files; user resolves manually
# on success: git worktree remove .worktrees/<task>
```

User runs `git push` afterward themselves. Framework never auto-pushes.

### Path 2 — Push branch + open PR (worktree stays)

```bash
cd <worktree_path>
git push -u origin feature/<task>
# if `gh` CLI available: prompt "Open PR via gh pr create? [y/n]"
```

Worktree remains; user finishes PR + merge + cleanup externally.

### Path 3 — Skip (default)

No-op. User handles everything.

## 7. Cleanup — `/worktree-prune`

Lists existing worktrees with their state:

- Branch merged into `main`?
- Task in `completed/`?
- Last commit timestamp

Per worktree: `[y]es remove / [n]o keep / [q]uit`. Never bulk-removes silently. Refuses to remove worktrees with uncommitted changes (honors git's refusal); user resolves manually.

## 8. DDEV compatibility

For Drupal projects with DDEV:

- DDEV explicitly supports worktrees ([DDEV Contributor Training, March 2026](https://ddev.com/blog/git-worktree-contributor-training/))
- **Requires the `name:` key removed from `.ddev/config.yaml`** — DDEV will then derive the project name from each worktree's directory automatically (`.worktrees/feature-foo/` → `https://feature-foo.ddev.site`)
- Framework detects `.ddev/config.yaml` presence + parses for `name:` key + warns user before creation if set; never auto-edits the config

If `name:` is set, `/worktree` warns:

> DDEV is configured with `name: <x>` in `.ddev/config.yaml`. Multiple worktrees with the same DDEV name will conflict. Recommended: remove the `name:` line and commit, OR use `/worktree --no-ddev-check` to proceed anyway.

User chooses [c]ontinue / [a]bort / [s]how-instructions.

## 9. Refusal cases

The `/worktree` creation command refuses on:

| Scenario | Behavior |
|---|---|
| Already inside a worktree | Refuse with: "Run from main tree to create a sibling worktree" |
| Task folder doesn't exist | Refuse; suggest `/research <task>` first |
| `.ddev/config.yaml` has `name:` set AND user didn't pass `--no-ddev-check` | Show warning; let user pick continue/abort |
| Branch `feature/<task>` already exists AND points to a different commit | Refuse with diagnostic; user can `--branch <custom>` or delete the branch |
| Working tree dirty (uncommitted changes) | git worktree add refuses; surface the error; user commits or stashes first |

## 10. Session-context interaction

The existing `session-context-writer` skill (v1.4.0) writes to `~/.claude/drupal-dev-framework/sessions/<md5($PWD)>.json`. **No changes needed** — the worktree's distinct `$PWD` produces a distinct hash, which produces a distinct session-context file automatically.

`/worktree` pre-seeds the new session-context file with `task: null, taskPath: null, project: <name>, projectPath: <abs>` so the file exists for hooks; the user's first `/research` or `/implement` populates the task field.

## 11. Versioning policy

- **Major bumps** (`2.0`) are breaking: changes to directory priority semantics, branch-naming default, signal-strength thresholds, lifecycle path order.
- **Minor bumps** (`1.1`) are additive: new optional signal types, new lifecycle paths, additional refusal cases, new flags.
- v1.0 is committed for v3.16.0.

## 12. Non-goals (deferred to v2)

- Configurable detection-window beyond 2 hours
- Detection signals on `/research` and `/design`
- `/migrate-to-worktree` for in-flight tasks
- Multi-task worktree reuse (single worktree, multiple tasks)
- Auto-edit `.ddev/config.yaml` (with backup + commit)
- Test-baseline runs default-on for Drupal projects
- Configurable worktree directory beyond `.worktrees/` / `worktrees/`
- Distributed / cross-machine worktree-equivalent
