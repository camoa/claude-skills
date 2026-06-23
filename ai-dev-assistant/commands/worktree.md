---
description: "Create a git worktree for parallel task execution. Sets up `.worktrees/<task>/` on `feature/<task>` branch, runs auto-detect setup (composer install, npm install), pre-seeds session-context. Framework-aware. Opt-in `--ddev-up` brings up an isolated DDEV instance for the worktree and seeds its DB/files from the main checkout (the official DDEV git-worktree workflow) so an agent has a live env to build/verify against. Soft-nudge — never auto-creates without confirmation; never spins up DDEV implicitly. Introduced v3.16.0."
allowed-tools: Read, Write, Edit, Bash, Skill
argument-hint: <task-name> [--base <ref>] [--branch <name>] [--with-baseline] [--no-ddev-check] [--ddev-up] [--ddev-no-seed]
---

# Worktree

Create a git worktree at `.worktrees/<task_name>/` on branch `feature/<task_name>` so this task can run in parallel with another Claude session on the same project. Reuses the superpowers `using-git-worktrees` precedent + extends with framework/task-lifecycle awareness.

## Usage

```
/ai-dev-assistant:worktree <task-name>                              # default flow
/ai-dev-assistant:worktree <task-name> --base origin/main           # branch from a specific ref
/ai-dev-assistant:worktree <task-name> --branch task/<custom>       # custom branch name
/ai-dev-assistant:worktree <task-name> --with-baseline              # opt-in baseline tests
/ai-dev-assistant:worktree <task-name> --no-ddev-check              # skip dev-environment name-conflict check
/ai-dev-assistant:worktree <task-name> --ddev-up                    # bring up an isolated DDEV for the worktree + seed DB/files from main
/ai-dev-assistant:worktree <task-name> --ddev-up --ddev-no-seed     # bring up the isolated DDEV but DON'T copy the DB/files (empty env)
```

`--ddev-up` is opt-in (default OFF — DDEV spin-up is expensive). It gives the worktree its **own isolated DDEV project** so an agent has a live env to `composer`/`drush`/`npm`/verify against — the official DDEV git-worktree workflow (<https://ddev.com/blog/git-worktree-contributor-training/>). `--ddev-no-seed` brings the instance up empty (skips the DB/files copy). This is the **code-authoring** worktree path; **infra/state** work-orders that must mutate the canonical env build in-place instead (see `references/work-order-lifecycle.md`).

See `references/worktree-conventions.md` v1.2 for the full convention, including how this command relates to Claude Code's native `claude --worktree` flag, PR-based worktrees, `.worktreeinclude`, `worktree.baseRef`, and `worktree.bgIsolation`.

## What this does

### Step 1 — Resolve task + project context

Run `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parse its JSON for `folder` (project path), `codePath`, `worktreeByDefault`. Resolve task folder under `<project>/implementation_process/**/<task-name>/`. Refuse with helpful message if task folder doesn't exist.

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

### Step 5 — Dev-environment check

If `<codePath>/.ddev/config.yaml` exists AND has a `name:` key:

> Print warning: "`.ddev/config.yaml` has `name: <x>` set. Multiple worktrees with the same name will conflict at dev-environment startup. Recommended: remove the `name:` line and commit, OR use `--no-ddev-check` to proceed anyway."
>
> Ask: "[c]ontinue / [a]bort / [s]how-instructions"

On `[a]` → exit 0 cleanly.
On `[s]` → print: "Edit `.ddev/config.yaml` and remove the line starting with `name:`. Save, commit (`git add .ddev/config.yaml && git commit -m 'chore: remove name key for worktree compatibility'`), then re-run /worktree." Then exit 0.
On `[c]` → continue (user knows the risk).

If `--no-ddev-check` was passed **and `--ddev-up` was NOT**, skip this step entirely. **`--no-ddev-check` does NOT skip the step when `--ddev-up` is set** — the auto-naming hard-halt below is mandatory under `--ddev-up` (skipping it would build a worktree that only fails later at `ddev start`), so evaluate that halt first and ignore `--no-ddev-check` for it.

**Under `--ddev-up`, a pinned `name:` is a HARD blocker, not a warning.** Auto-naming (the worktree dir → the DDEV project name) is what keeps the worktree's instance distinct from the main project's; a pinned `name:` makes both projects share one name and `ddev start` refuses the second (`project root is already set … refusing to change it`). So with `--ddev-up` and a `name:` set: do NOT offer `[c]ontinue` — halt and instruct the user to **either** remove the `name:` line and commit (per-project, no global change), **OR** run `ddev config global --omit-project-name-by-default` once, then re-run. **Scope note (state it when recommending the flag):** `--omit-project-name-by-default` is a **machine-global** DDEV setting; per the DDEV docs it changes only the *default* for **newly-configured** projects (`ddev config` stops writing a `name:`) — it does **not** rename or alter existing projects. Prefer the per-project `name:` removal if the user would rather not touch global config. `--no-ddev-check` does not bypass this (you cannot bring up a correctly-named isolated instance with a pinned name).

### Step 6 — Create worktree

Determine BASE:
- `--base <ref>` flag → use it
- Default → `git rev-parse HEAD` (current commit)

The HEAD default matches the `worktree.baseRef: "head"` semantic — task work often sits on uncommitted local patches a `"fresh"` base would drop. This command does not read the `worktree.baseRef` setting (that setting governs Claude Code's native `--worktree`); pass `--base origin/main` for a clean base. See `references/worktree-conventions.md`.

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
| `composer.json` | `composer install` |
| `package.json` | `npm install` (or `pnpm install` / `yarn install` per lockfile) |

Setup runs sequentially. Failures print but don't auto-rollback (user can fix and re-run).

### Step 7b — DDEV bring-up + seed (opt-in, `--ddev-up`)

Runs **only** when `--ddev-up` was passed AND `<codePath>/.ddev/config.yaml` exists. Skip silently otherwise. This brings up the worktree's **own isolated DDEV project** (its own web + db containers) and copies the main site's state into it — the official DDEV git-worktree pattern. The DB is **copied, never shared**: each worktree gets its own DB (the supported, isolation-safe path; pointing a worktree at the main project's db container is explicitly NOT used — it resets on restart and risks concurrent-write corruption).

**Auto-naming** is already guaranteed by Step 5 (a pinned `name:` halted there under `--ddev-up`). The worktree at `.worktrees/<task>/` becomes `https://<task>.ddev.site` (non-alphanumerics in the dir name normalise to `-`). Recommend (don't auto-apply) the global default once so every future worktree auto-names: `ddev config global --omit-project-name-by-default` — noting it is **machine-global** and changes only the default for newly-configured projects (it does not touch existing ones; see the scope note in Step 5).

**Bring up the isolated instance** (cwd is the worktree from Step 7):

```bash
ddev start
```

If `ddev start` fails (commonly a stale same-name project still registered), surface the error verbatim; the fix is `ddev stop --unlist <name>` then re-run. Do NOT auto-`--unlist` — it mutates the user's DDEV project registry.

**Seed DB + files from the main checkout** (skip entirely when `--ddev-no-seed`). Warn first: a DB export/import can take **minutes** on a large site and the worktree keeps its own DB volume (disk cost).

```bash
TARBALLS="<codePath>/.worktrees/.tarballs"; mkdir -p "$TARBALLS"
rm -f "$TARBALLS/db.sql.gz" "$TARBALLS/files.tgz"   # never import a STALE tarball from a prior run
# DB — stack-agnostic + cross-project portable. The MAIN project's DDEV MUST be running (ddev export-db
# reads its db container; if it's stopped the export fails). `&&` so a failed export NEVER falls through
# to an import of a missing/old file:
( cd "<codePath>" && ddev export-db --file="$TARBALLS/db.sql.gz" ) \
  && ddev import-db --file="$TARBALLS/db.sql.gz"                     # into the worktree (cwd = the worktree)
# Files — best-effort; derive the docroot from .ddev/config.yaml (default empty = repo root):
DOCROOT=$(grep -E '^docroot:' "<codePath>/.ddev/config.yaml" | head -1 | sed -E 's/^docroot:[[:space:]]*//; s/["'"'"']//g')
FILES="<codePath>/${DOCROOT:+$DOCROOT/}sites/default/files"
if [ -d "$FILES" ]; then
  ( cd "<codePath>" && tar -C "$FILES" -czf "$TARBALLS/files.tgz" . ) && ddev import-files --source="$TARBALLS/files.tgz"
fi
```

The two `ddev export-db` / `tar` reads run in a `( cd … )` subshell against the **main** checkout (a subshell `cd` does not change the command's working directory); the `import-*` run in the worktree. The tarballs are cleared first (no stale-data seed) and export-`&&`-import is chained so a failed export can't seed an old DB. **Precondition: the main project's DDEV must be running** (`ddev export-db` reads its db container) — if `ddev export-db` fails, surface it and leave the worktree's DDEV up empty (the user starts main's DDEV and re-seeds, or builds against an empty DB). Never abort the whole worktree over a seed hiccup.

### Step 8 — Optional baseline

If `--with-baseline` was passed:

| Available | Run |
|---|---|
| `vendor/bin/phpunit` | `vendor/bin/phpunit` |
| `npm test` script in package.json | `npm test` |

Print pass/fail summary. If failures and `--ignore-baseline` not passed → refuse to declare worktree ready.

Default: skip baseline (opt-in only).

### Step 9 — Pre-seed session-context

Run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh` **from inside the worktree** (`$PWD` is now the worktree path — the script keys the session file by `md5($PWD)`):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh" \
  "<project_name>" "<abs project memory folder>" null null
```

- `$1` `<project_name>` (from `project-state-read.sh`)
- `$2` `<abs project memory folder>`
- `$3` `null` (task)
- `$4` `null` (taskPath)

This ensures the worktree's session-context file exists; the user's first `/research` or `/implement` populates the task field.

### Step 10 — Print summary

```
✓ Worktree created at .worktrees/<task-name>
  Branch:  feature/<task-name> from <BASE-ref>
  Setup:   composer install ✓ | npm install ✓
  DDEV:    https://<task-name>.ddev.site  (seeded: db ✓ | files ✓)   # only when --ddev-up
  Session: pre-seeded for project <name>

Next:
  cd .worktrees/<task-name>
  /ai-dev-assistant:implement <task-name>

Or run /worktree-prune later to clean up when done (it tears the worktree's DDEV down first).
```

Print the `DDEV:` line only when `--ddev-up` brought an instance up; show `seeded: skipped` under `--ddev-no-seed`.

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
| `--ddev-up` AND `.ddev/config.yaml` has `name:` set | **Hard halt** (Step 5) — no `[c]ontinue`; instruct remove `name:` + commit OR `ddev config global --omit-project-name-by-default`, then re-run |
| `--ddev-up` and `ddev start` fails (stale same-name project) | Surface git/ddev error verbatim; suggest `ddev stop --unlist <name>`; leave the worktree created; do NOT auto-`--unlist` |
| `--ddev-up` seed (export/import) fails | Leave the worktree + its DDEV instance up (empty/partial); surface the error; user re-seeds or builds against an empty DB |

## Soft-nudge posture

- Never creates without explicit confirmation when there's a dev-environment name-conflict warning
- Never auto-edits `.ddev/config.yaml`
- Never `--force` removes anything
- `--ddev-up` is opt-in (default OFF) — DDEV is never spun up implicitly; never auto-`--unlist`s a registered project
- User can decline at every interactive step

## Related

- `/ai-dev-assistant:worktree-prune` — cleanup
- `/ai-dev-assistant:implement` — invokes worktree recommendation pre-step
- `/ai-dev-assistant:complete` — invokes worktree merge prompt at task end
- `references/worktree-conventions.md` — full conventions, including coverage of Claude Code's native worktree support
- `superpowers:using-git-worktrees` — generic creation pattern (ai-dev-assistant adds task-aware lifecycle)
- Claude Code's native worktree support — `https://code.claude.com/docs/en/worktrees` (the `claude --worktree` / `-w` CLI flag, PR-based worktrees, `.worktreeinclude`). The framework's `/worktree` and the native flag are complementary entry points — see `references/worktree-conventions.md`.
