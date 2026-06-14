# /upgrade-project Walkthrough

> Companion to `commands/upgrade-project.md`. Loaded only on explicit user read (token-efficiency split per v4.0.2 pattern).

**Introduced:** ai-dev-assistant v4.1.0
**Driver:** Old projects (created before v3.15.0 playbook system / v4.1.0 review phase) silently inherit defaults from the plugin's `defaults.json`; without retrofit, framework upgrades produce a two-tier ecosystem.

## Overview

`/upgrade-project` is a **single command, two passes** that brings the active project up to current scaffolder parity:
1. **Project-state pass** — backfills missing fields onto `project_state.md` (Code Path, Playbook Sets, User Playbook + state, Worktree By Default, Review Required)
2. **Task-level pass** — iterates in-progress tasks under the project to retrofit task-level gaps (frontmatter, Phase 4 line, missing audit JSONs)

**Active-project-only.** Never iterates the registry (no bulk mode). Runs against the project resolved from session-context (or walk-up from `$PWD`).

**Wizard pattern** — delegates to existing `/set-code-path`, `/set-playbook-sets`, `/set-user-playbook` for actual writes. Field-validation lives in those commands; `/upgrade-project` orchestrates.

## Why this exists

Three sibling subtasks (`review_phase_command`, `adherence_gates`, `retrofit_tools`) shipped in v4.1.0 introduced new fields + new audit JSONs + new task-level conventions. Without retrofit, only newly-created tasks get the full benefit; old in-flight tasks remain grandfathered. `/upgrade-project` closes that gap on user demand.

Specifically:
- `**Review Required:**` field referenced by `/complete` Step 3 (PR #138) — without explicit setting, projects use legacy default
- Implicit-inheritance hint surfaced by `validate-playbook-adherence` (PR #139) — points users at this command
- Phase 4 line in task scaffolds (PR #138) — not retroactively applied to old task.md files
- v4.0.0 audit JSONs (`_pre-analysis.json`, etc.) — re-runnable for old tasks via deterministic loaders

## Per-step deep-dive

### Step 1 — Resolve active project + preflight

Charset-validates `<project-name>` (`^[a-z][a-z0-9_]*$`) — **path-traversal mitigation** (paper-test surfaced this as red-team A1; explicit Step 1 sub-step now). Resolves via session-context → walk up from `$PWD` to find `implementation_process/`, capped at `$HOME` or 5 levels (paper-test H7). Session-context vs walk-up consistency check (paper-test H10): if both resolve and disagree, user prompted to confirm.

Preflight verifies all required scripts exist + executable (paper-test H9): `project-state-read.sh`, `dev-guides-detect.sh`, `playbook-load-deterministic.sh`, `coverage-mapping-check.sh`, `gate-audit-write.sh`, `fm-helpers.sh`. Exit 2 on any failure.

### Step 2 — Project-state pass: gap detection

Runs `bash scripts/project-state-read.sh <project>`. For `**Review Required:**`, also direct-greps as fallback (older readers may not parse it; v4.1.0 reader extension added that — see `retrofit_tools` PR #140, fully fixed in plumbing_docs_tests via parse_bool refactor + char-class headers).

Builds `gaps[]` for fields a fresh project would have today:
- `**Code Path:**` (v3.11.0) — absent / `code_path_unknown`
- `**Playbook Sets:**` (v3.15.0) — `playbook_sets_source: "default"` (implicit inheritance)
- `**User Playbook:**` + `**User Playbook State:**` (v3.15.0) — state `unset`
- `**Worktree By Default:**` (v3.16.0) — absent (defaults `false`)
- `**Review Required:**` (v4.1.0) — absent (legacy default: `false` for projects with completed/ non-empty)

### Step 3 — Project-state pass: single batch prompt

Verbatim — no default; user MUST pick `[a]/[s]/[n]`. Mirrors dev-guides preflight UX (paper-test RQ1).

### Step 4 — Project-state pass: journal-backed atomic batch

Before any write, creates `<project>/.upgrade-project-journal.json` with planned operations + per-op `done: false`. **Critical fix from paper-test C3** — without journal, partial-state silent half-write breaks idempotency contract.

Per gap, dispatches to existing setter via `Skill` (delegation) OR direct `Edit` (for fields without setters):
- Code Path → `/set-code-path`
- Playbook Sets → `/set-playbook-sets`
- User Playbook → `/set-user-playbook`
- Worktree By Default → direct Edit
- Review Required → direct Edit

After each write, marks `done: true` in journal. On any failure: stops, leaves journal, surfaces "partial state — run with `--resume`". On full success: deletes journal.

`--resume` reads journal and skips `done: true` entries. Idempotent recovery.

### Step 5 — Task-level pass: discovery

`Glob <project>/implementation_process/in_progress/**/task.md`, then **filter** to exclude `*/.migration-tmp/*` AND `*/completed/*` (paper-test H1: glob over-match would catch already-completed subtasks inside epic folders).

Per task: parse frontmatter via `fm-helpers.sh`; refuse on YAML parse failure with diagnostic. Build per-task `gaps[]`:
- Missing v3.10.0 frontmatter keys (full set)
- Missing `## Phase Status` H2 OR Phase 4 line
- Missing audit JSONs for **completed phases only** (Phase 1 [x] expects `_dev-guides-load.json`, `_playbook-load.json`, `_coverage-mapping.json`)
- `_pre-analysis.json` absent + research.md present → mark `grandfathered`
- `alignment.md` absent → flag-only

**Symlink rejection** (paper-test C2): if any artifact in task folder is a symlink, skip task with warning. Defends against `research.md → /etc/hosts` getting copied into committed audits.

**Audit JSON validation** (paper-test H8): `jq empty <file>` before treating as present; corrupt → rewrite with `replaced_corrupt: true` flag.

### Step 6 — Task-level pass: single batch summary

Alphabetical task order (paper-test RQ6 — deterministic). User picks `[a]/[s]/[n]`. `--rerun-loaders` auto-selects `[a]`. Under `--dry-run`, prompt becomes "would-have-applied"; nothing written.

### Step 7 — Task-level pass: apply per gap-type

- **Frontmatter merge** via `fm-helpers.sh`: read existing YAML; for missing canonical keys, add v3.10.0 defaults; preserve user-written keys verbatim. On no-frontmatter task, prepend full frontmatter block. On YAML parse failure, refuse (reported in Step 5).
- **Phase Status repair**: if H2 absent, append complete 4-line block at end of `## Goal` section. If only Phase 4 line missing, idempotent insert before next `## ` boundary (or EOF).
- **Audit backfill**: invoke `dev-guides-detect.sh`, `playbook-load-deterministic.sh`, `coverage-mapping-check.sh`; wrap each output in standard envelope via jq with `gate_specific.retrofitted: true` flag (paper-test H7); write via `gate-audit-write.sh`.
- **`_pre-analysis.json` grandfather marker** (optional, user-confirmed in `[s]elect`): `gate_specific.grandfathered: true` + `bypass_reason: "grandfathered_retrofit"`.
- **`alignment.md`**: flagged only; user invokes `/scope` separately.

### Step 8 — `--dry-run` mode

Skips all writes (Step 4 + Step 7); prints full would-write summary. **Exit 0 always** (POSIX-compatible per paper-test H3 — `set -e` + `&&` chain compatibility). Stderr message if would-have-changes.

`--dry-run` dominates `--rerun-loaders` (paper-test H4): combination shows would-have-applied; nothing written.

### Step 9 — Final summary

Print: project-state fields written, tasks retrofitted (per-task gap closures), already-current count, manual-attention items.

## Examples

### Implicit-inheritance project (camoa_skills)

```
$ /ai-dev-assistant:upgrade-project
Resolving active project... camoa_skills
Project state pass — found 5 gaps:
  - Code Path: absent → /set-code-path will detect+confirm
  - Playbook Sets: inherits "<framework>/best-practices/<author>" from default
  - User Playbook: unset
  - Worktree By Default: absent (default false)
  - Review Required: absent (legacy default: false on projects with completed/ non-empty)

[a]pply all | [s]elect | [n]one : a

Writing journal... .upgrade-project-journal.json
[1/5] /set-code-path interactive...
[2/5] /set-playbook-sets <framework>/best-practices/<author>
[3/5] /set-user-playbook (3-state interactive)
[4/5] Direct Edit: **Worktree By Default:** false
[5/5] Direct Edit: **Review Required:** false (legacy)
Deleting journal — full success.

Task pass — found 4 in-progress tasks; 3 need retrofit:
  task-a: 3 gaps (frontmatter merge, Phase 4 line, _coverage-mapping.json missing)
  task-b: 1 gap (alignment.md flagged — manual)
  task-c: already current ✓
  task-d: 2 gaps (frontmatter merge, _playbook-load.json missing)

[a]pply all | [s]elect | [n]one : a

Applying...
  task-a: frontmatter merged (3 keys added); Phase 4 inserted; _coverage-mapping.json written (retrofitted: true)
  task-b: alignment.md flagged in summary; no auto-create
  task-d: frontmatter merged (5 keys added); _playbook-load.json written (retrofitted: true)

Final summary:
  Project state: 5 fields written (Code Path, Playbook Sets, User Playbook, Worktree By Default, Review Required)
  Tasks retrofitted: 2/4 (task-a, task-d)
  Tasks already current: 1 (task-c)
  Manual attention: 1 (task-b — alignment.md missing)
```

### `--dry-run` preview

```
$ /ai-dev-assistant:upgrade-project --dry-run
[Detect gaps as above]
[a]pply all | [s]elect | [n]one : a

DRY-RUN — no writes:
  Would invoke: /set-code-path
  Would invoke: /set-playbook-sets ...
  Would write: **Worktree By Default:** false to project_state.md
  Would write: **Review Required:** false to project_state.md
  Would merge frontmatter on: task-a, task-d
  Would insert Phase 4 line on: task-a
  Would write _coverage-mapping.json on: task-a (retrofitted: true)
  ...
Exit 0.
```

### `--resume` after interruption

```
$ /ai-dev-assistant:upgrade-project
[Step 4 fails on /set-user-playbook — user typo]
Partial state — run with --resume to continue.
Journal preserved at .upgrade-project-journal.json (2/5 ops done).

$ /ai-dev-assistant:upgrade-project --resume
Resuming from journal — skipping 2 done ops.
[3/5] /set-user-playbook (re-prompts)
...
Full success. Deleting journal.
```

## Edge cases

- **Project state fully explicit already** — surfaces "no change at project level"; continues to task pass
- **All tasks already current** — surfaces "N tasks already current; nothing to retrofit"
- **`/set-*` failure mid-batch** — journal preserves partial state for `--resume`
- **`project_state.md` corrupt** — exit 2 with diagnostic; no writes
- **Frontmatter checksum-mismatch** — refuses merge; surfaces conflict for manual resolution
- **Concurrent `/upgrade-project` invocations** — last-writer-wins on `project_state.md`; lock not implemented in v1 (v2 candidate)

## Version history

- **v4.1.0** — initial introduction. Single-command two-pass design (collapsed from earlier `/upgrade-project + /upgrade-task` proposal per 2026-04-26 user scope decision).

## Related

- `commands/upgrade-project.md` — runtime body (100/120 lines token-efficient)
- `commands/set-code-path.md` / `:set-playbook-sets` / `:set-user-playbook` — invoked by this wizard
- `commands/complete.md` — Step 3 honors `**Review Required:**` (set this via `/upgrade-project`)
- `commands/validate-playbook-adherence.md` — surfaces implicit-inheritance hint pointing at `/upgrade-project`
- `scripts/project-state-read.sh` — extended in v4.1.0 with `Review Required` parsing + parse_bool refactor + char-class headers (full case-sensitivity audit shipped in `plumbing_docs_tests`)
