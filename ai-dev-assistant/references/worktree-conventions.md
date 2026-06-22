# Worktree Conventions v1.3

**Introduced:** ai-dev-assistant v3.16.0
**Owner:** `commands/worktree.md`, `commands/worktree-prune.md`, `commands/implement.md` (recommendation), `commands/complete.md` (lifecycle)
**Consumers:** the framework's worktree commands + the helper scripts (`worktree-detect.sh`, `worktree-signals.sh`)

This reference documents the framework's git-worktree conventions for parallel task execution within a single ai-dev-assistant project. It establishes directory layout, branch naming, detection signals, lifecycle paths, and framework-specific concerns. Reuses the superpowers `using-git-worktrees` skill's core patterns; extends with task-aware lifecycle and framework awareness.

## 1. Why worktrees

Two Claude Code sessions on the same workspace collide on:

- `~/.claude/ai-dev-assistant/sessions/<md5($PWD)>.json` — same `$PWD` = same hash = last writer wins
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
| `multi_session` | MEDIUM-HIGH | 2+ session-context files in `~/.claude/ai-dev-assistant/sessions/` reference the same project (signal that the user has been working on this project from multiple workspaces) |
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

## 8. DDEV-aware worktrees (`--ddev-up`)

For Drupal projects with a `.ddev/config.yaml` in `codePath`, `/worktree --ddev-up` gives the worktree its **own isolated DDEV project** (own web + db containers) and seeds it from the main site — the official DDEV git-worktree workflow (<https://ddev.com/blog/git-worktree-contributor-training/>). This is what makes the worktree+PR agent loop viable for **code-authoring** Drupal WOs that need a live env to verify against. (DDEV is optional Drupal-flavored wiring; the engine stays stack-agnostic — a non-`.ddev` project simply skips this.)

### 8.1 Auto-naming (the name-conflict guard)

A DDEV project name **must be unique**; two projects sharing a `name:` collide — `ddev start` on the second refuses with `project root is already set … refusing to change it`. The fix is **auto-naming**: with no pinned `name:`, each worktree's directory becomes its project name (`.worktrees/feature-foo/` → `https://feature-foo.ddev.site`).

- **Recommended global default:** `ddev config global --omit-project-name-by-default` (once) — every future worktree auto-names with no per-project edit.
- **Or** remove the `name:` line from `.ddev/config.yaml` and commit.
- `/worktree` detects a pinned `name:` and warns; **under `--ddev-up` a pinned `name:` is a hard halt** (no `[c]ontinue`, and `--no-ddev-check` does not bypass it) — you cannot bring up a correctly-named isolated instance with a pinned name. Never auto-edits the config.

### 8.2 Seeding (copy, never share)

Each worktree gets its **own** DB — the state is **copied** from the main project, never shared. (Pointing a worktree at the main project's db container is explicitly NOT used: DDEV resets the DB host on restart, and two web containers writing one DB risks cache/schema/lock corruption — see the DDEV research in `aida-gaps.md`.) `/worktree --ddev-up` (without `--ddev-no-seed`):

1. `ddev start` in the worktree (its own containers).
2. From the **main** checkout: `ddev export-db --file=<shared>/db.sql.gz` (+ `tar` the files dir, docroot derived from `.ddev/config.yaml`).
3. In the worktree: `ddev import-db` (+ `ddev import-files`).

`--ddev-no-seed` brings the instance up empty. A DB export/import is minutes on a large site and each worktree holds its own DB volume (disk) — hence `--ddev-up` is opt-in (default OFF), never implicit.

### 8.3 Teardown ordering (mandatory)

`/worktree-prune` **must `ddev delete --omit-snapshot --yes` the worktree's DDEV project BEFORE `git worktree remove`.** Removing the dir first leaves an **orphaned DDEV registry entry** (DDEV still has the project root registered → the next same-name worktree fails `ddev start`). The DB is a throwaway copy, so `--omit-snapshot` skips the slow auto-snapshot.

### 8.4 Infra/state WOs build in-place, NOT in a worktree

The ephemeral worktree above is for **code-authoring** WOs (durable output = files, PR-able). An **infra/state** WO (composer require + drush en + config import + theme build) produces env state — DB schema, enabled modules, built theme — that must land on the **canonical** integration env. A per-worktree isolated DDEV builds it where nothing downstream sees it. Those WOs use **build-in-place** mode instead (see `references/work-order-lifecycle.md`): build on the main checkout's DDEV, operator-gated. The taxonomy: **code-authoring WO → ephemeral-worktree (`--ddev-up`) + PR; infra/state WO → build-in-place.**

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

The `session-context-writer` skill (v1.5.0+) writes the session-context file through the shared `scripts/session-paths.sh` helper (`ddf_session_file`). The path is keyed by `md5($PWD)` and — when `CLAUDE_CODE_SESSION_ID` is set — additionally by the session ID. A worktree gets a distinct `$PWD` (`.worktrees/<task>/`), so its session-context file is already distinct from the main tree's; the session-ID salt (added v4.9.0) additionally separates two sessions that share the **same** `$PWD` — two terminals in the main checkout, or a resumed session. Every session hook resolves the same path through the helper; the project-copied `save-session.sh` inlines an equivalent formula. When `CLAUDE_CODE_SESSION_ID` is absent the key is `md5($PWD)` exactly as before v4.9.0.

`/worktree` pre-seeds the new session-context file with `task: null, taskPath: null, project: <name>, projectPath: <abs>` so the file exists for hooks; the user's first `/research` or `/implement` populates the task field.

## 11. Claude Code's native worktree support

Claude Code ships its own git-worktree features, separate from this framework's
`/worktree` command. The two coexist; this section maps the relationship so a
user running framework work inside native worktrees is not surprised.

### 11.1 Two entry points

| Entry point | Creates | Branch | Owned by |
|---|---|---|---|
| `/ai-dev-assistant:worktree <task>` | `.worktrees/<task>/` | `feature/<task>` | this framework |
| `claude --worktree <name>` (or `-w`) | `.claude/worktrees/<name>/` | `worktree-<name>` | Claude Code |

The framework's `/worktree` is task-scoped: it resolves the task folder, runs
framework-aware setup, and pre-seeds session-context. The native
`--worktree` flag is session-scoped — it starts a whole Claude Code session in a
fresh worktree. Mid-session, asking Claude to "work in a worktree" triggers the
`EnterWorktree` tool, which creates one the same way. Native `--worktree`
requires the workspace-trust dialog to have been accepted (run `claude` once in
the directory first).

### 11.2 Reviewing a PR in a worktree

`claude --worktree "#1234"` (or a full GitHub pull-request URL) fetches
`pull/1234/head` and creates a worktree at `.claude/worktrees/pr-1234`. This
pairs naturally with Phase 4 `/review`: open the PR in its own checkout, run
`/review` there, and the main working tree stays untouched. The framework does
not wrap this — it is a native CLI entry point, used directly.

### 11.3 Copying gitignored files — `.worktreeinclude`

A native worktree is a fresh checkout, so gitignored files (`.env`,
`settings.local.php`) are absent. A `.worktreeinclude` file
at the project root — `.gitignore` syntax — lists gitignored files to copy into
each new native worktree. Only files that both match a pattern AND are
gitignored are copied, so tracked files are never duplicated. Example entries:

```text
.env
.secrets
```

`.worktreeinclude` applies to `--worktree`, `EnterWorktree`, and subagent
worktrees. It is NOT processed when a `WorktreeCreate` hook is configured
(see the WorktreeCreate section below). The framework's own `/worktree` runs explicit setup (`commands/worktree.md`
Step 7) rather than relying on `.worktreeinclude`.

### 11.4 Base ref — `worktree.baseRef` vs the framework's HEAD default

The `worktree.baseRef` setting governs which ref *native* worktrees branch from:

- `"fresh"` (default) — branches from `origin/<default-branch>`, a clean tree
  matching the remote.
- `"head"` — branches from local `HEAD`, carrying unpushed commits and
  feature-branch state.

It applies to `--worktree`, the `EnterWorktree` tool, and subagent isolation.

The framework's `/worktree` command does **not** read `worktree.baseRef`. It has
its own `--base <ref>` flag and defaults `BASE` to `git rev-parse HEAD` — i.e.
the `"head"` semantic. This is deliberate: task work frequently sits on
uncommitted local patches and feature-branch state that a `"fresh"` base would
drop. Users who want a clean base pass `--base origin/main` explicitly.

### 11.5 Background-session isolation — `worktree.bgIsolation`

`worktree.bgIsolation` (v2.1.143+) controls how *background* sessions
(`claude --bg`, `/background`, Agent View) isolate their edits:

- `"worktree"` (default) — `Edit`/`Write` in the main checkout are blocked until
  the background session calls `EnterWorktree`, so background work lands in a
  `.claude/worktrees/` worktree.
- `"none"` — background jobs edit the working copy directly.

This is a background-session mechanism, finer-grained than and independent of
the framework's `/worktree`. A user who runs framework work in background
sessions will accumulate native worktrees under `.claude/worktrees/` — see the cleanup section below.

### 11.6 Non-git VCS — `WorktreeCreate` / `WorktreeRemove`

`WorktreeCreate` / `WorktreeRemove` hooks let non-git VCSs (SVN, Perforce,
Mercurial) supply custom worktree creation and cleanup. The framework neither
ships nor needs these hooks for standard git projects — noted only so the
relationship is complete.

### 11.7 Cleanup boundaries

`/worktree-prune` scans only `.worktrees/` and `worktrees/` — the framework's own
layout. It does **not** see `.claude/worktrees/` (native `--worktree` sessions,
PR worktrees, background isolation). Native worktrees are managed by:

- Agent View (`Ctrl+X` to delete a background-session worktree),
- `git worktree remove` / `git worktree prune`, and
- the `cleanupPeriodDays` auto-sweep, which removes *orphaned subagent*
  worktrees older than the cutoff that have no uncommitted changes, untracked
  files, or unpushed commits. Worktrees created with `--worktree` are never
  swept.

The `cleanupPeriodDays` auto-sweep complements `/worktree-prune`; it does not
replace it — the framework's prune is task-aware (checks branch-merged and
task-completed), the native sweep is not.

## 12. Versioning policy

- **Major bumps** (`2.0`) are breaking: changes to directory priority semantics, branch-naming default, signal-strength thresholds, lifecycle path order.
- **Minor bumps** (`1.1`) are additive: new optional signal types, new lifecycle paths, additional refusal cases, new flags, new documentation sections.
- v1.0 committed for v3.16.0; v1.1 (additive, native worktree support) for v4.7.0; v1.2 (session-ID-salted session files) for v4.9.0; v1.3 (additive, DDEV-aware worktrees `--ddev-up` + teardown ordering + infra/state build-in-place taxonomy) for v5.16.0.

## 13. Non-goals (deferred to v2)

- Configurable detection-window beyond 2 hours
- Detection signals on `/research` and `/design`
- `/migrate-to-worktree` for in-flight tasks
- Multi-task worktree reuse (single worktree, multiple tasks)
- Auto-edit `.ddev/config.yaml` (with backup + commit)
- Test-baseline runs default-on for all projects
- Configurable worktree directory beyond `.worktrees/` / `worktrees/`
- Distributed / cross-machine worktree-equivalent
