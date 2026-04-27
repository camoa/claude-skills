---
description: "Retrofit the active project to current scaffolder parity. Trigger: 'upgrade project', 'retrofit', 'bring project up to date', 'modernize project state'. Backfills project_state.md fields (Code Path, Playbook Sets, User Playbook + state, Worktree By Default, Review Required) AND iterates in-progress tasks for task-level gaps (frontmatter, Phase 4 line, missing audit JSONs). Active-project-only, never bulk. Wizard pattern delegating to existing /set-* commands. Idempotent + journal-based atomic. Introduced v4.1.0."
allowed-tools: Read, Edit, Bash, Glob, Skill
argument-hint: [<project-name>]
---

# Upgrade Project

Bring the active project on par with what a fresh project would scaffold today. Two passes per invocation: project-state fields, then in-progress tasks. Active-project-only; never iterates the registry. Wizard pattern — delegates to existing `/set-*` commands so field-validation lives in one place.

## Usage

```
/drupal-dev-framework:upgrade-project              # active project (from session-context)
/drupal-dev-framework:upgrade-project <name>       # specific project
/drupal-dev-framework:upgrade-project <n> --dry-run         # preview without writing (exit 0 always)
/drupal-dev-framework:upgrade-project <n> --rerun-loaders   # auto-write missing audit JSONs
/drupal-dev-framework:upgrade-project <n> --skip-tasks      # project-state pass only
/drupal-dev-framework:upgrade-project <n> --resume          # continue interrupted upgrade from journal
```

`--dry-run` dominates `--rerun-loaders` (combination shows would-have-applied; nothing written).

## What this does

1. **Resolve active project + preflight.** Validate `<project-name>` matches `^[a-z][a-z0-9_]*$` (charset; exit 2 with usage on mismatch — path-traversal mitigation). Resolve via `session_context.json`; else walk up from `$PWD` to find `implementation_process/`, capped at `$HOME` or 5 levels (whichever first; exit 2 if exhausted). When BOTH resolve, compare; mismatch → prompt user to confirm before proceeding (defense vs spoofed session-context). Verify required scripts exist + executable: `project-state-read.sh`, `dev-guides-detect.sh`, `playbook-load-deterministic.sh`, `coverage-mapping-check.sh`, `gate-audit-write.sh`, `fm-helpers.sh`. Verify `/set-code-path`, `/set-playbook-sets`, `/set-user-playbook` command files present. Exit 2 on any preflight failure.

2. **Project-state pass — gap detection.** Run `bash scripts/project-state-read.sh <project>`. Inspect emitted JSON. For `**Review Required:**`, also direct-grep (`grep -i '^\*\*[Rr]eview [Rr]equired:\*\*'`) as fallback for older readers. Build `gaps[]` for: `**Code Path:**` (absent / `code_path_unknown`), `**Playbook Sets:**` (`playbook_sets_source: "default"` = implicit), `**User Playbook:**` + state (`unset`), `**Worktree By Default:**` (absent), `**Review Required:**` (absent).

3. **Project-state pass — single batch prompt** (verbatim):
   ```
   Found {N} project-state gaps in <project>:
     - Code Path:           absent → /set-code-path will detect+confirm
     - Playbook Sets:       inherits "drupal/best-practices/camoa" from default
     - User Playbook:       unset
     - Worktree By Default: absent (default false)
     - Review Required:     absent (legacy default: false on projects with completed/ non-empty)

   How to proceed?
   [a]pply all — confirm current resolved values as explicit (lossless)
   [s]elect    — interactive per-gap [c]onfirm | [e]dit | [s]kip
   [n]one      — skip project-state pass
   ```
   No default; user MUST pick. On non-`a/s/n` input, re-display verbatim (do not infer).

4. **Project-state pass — apply via journal-backed atomic batch.** Before any write, create `<project>/.upgrade-project-journal.json` with planned operations + per-op `done: false`. For each gap:
   - `**Code Path:**` → invoke `/drupal-dev-framework:set-code-path` via `Skill`
   - `**Playbook Sets:**` → invoke `/drupal-dev-framework:set-playbook-sets <currently-resolved>`
   - `**User Playbook:**` → invoke `/drupal-dev-framework:set-user-playbook`
   - `**Worktree By Default:**` → direct `Edit` insert `**Worktree By Default:** false` (no setter exists)
   - `**Review Required:**` → direct `Edit` insert with computed legacy default
   After each write, mark `done: true` in journal. On any failure: stop, leave journal, surface "partial state — run with `--resume` to continue from {next-undone-op}". On full success, delete journal. `--resume` reads journal and skips `done: true` entries.
   Under `--dry-run`: emit "would invoke /set-X with args ..." per gap; do NOT write journal or invoke setters.

5. **Task-level pass — discovery** (skip if `--skip-tasks` OR project-pass-aborted). `Glob <project>/implementation_process/in_progress/**/task.md`, then **filter** to exclude paths matching `*/.migration-tmp/*` or `*/completed/*` (anchored to /completed/, not the project's top-level completed/ which is already outside in_progress/**). Per task, `bash scripts/fm-helpers.sh` parses frontmatter; reject task on YAML parse failure with diagnostic. Build per-task `gaps[]`:
   - Missing v3.10.0 frontmatter keys (full set: `id`, `kind`, `parent`, `children`, `blocks`, `blocked_by`, `external_ids`, `status`)
   - Missing `## Phase Status` H2 OR missing `Phase 4: Review` line
   - Missing audit JSONs for **completed** phases only: Phase 1 [x] expects `_dev-guides-load.json`, `_playbook-load.json`, `_coverage-mapping.json`. Validate existing audits with `jq empty <file>`; treat parse-failed as absent (annotate `replaced_corrupt: true` on rewrite).
   - `_pre-analysis.json` absent + `research.md` present → mark `grandfathered`
   - `alignment.md` absent → flag-only
   - **Symlink rejection:** if any artifact in task folder is a symlink (`[ -L "<file>" ]`), skip task with warning "task contains symlinked artifacts; refusing to run loaders"

6. **Task-level pass — single batch summary** (alphabetical task order):
   ```
   Found {N} in-progress tasks under <project>; {M} need retrofit, {K} already current.

   <task-1>: 3 gaps (frontmatter merge, Phase 4 line, _coverage-mapping.json missing)
   <task-2>: 1 gap (alignment.md flagged — manual; not auto-fixable)

   [a]pply all — auto-fix safe gaps  |  [s]elect — per-task interactive  |  [n]one
   ```
   `--rerun-loaders` auto-selects `[a]pply all`. Under `--dry-run`, prompt becomes "would-have-applied"; nothing written.

7. **Task-level pass — apply per gap-type.**
   - **Frontmatter merge** via `bash scripts/fm-helpers.sh`: read existing YAML; for missing canonical keys, add v3.10.0 defaults (`children: null`, `blocks: []`, `blocked_by: []`, `external_ids: {}`, `status: draft`); preserve user-written keys verbatim. On no-frontmatter task.md, prepend full frontmatter block. On YAML parse failure, refuse (reported in Step 5 discovery).
   - **Phase Status repair**: if H2 absent, append complete 4-line block at end of `## Goal` section. If only Phase 4 line missing, idempotent insert before next `## ` boundary (or EOF).
   - **Audit backfill**: invoke `dev-guides-detect.sh`, `playbook-load-deterministic.sh`, `coverage-mapping-check.sh` per task; wrap each output in standard envelope via jq (`{schema_version: "1.0", gate_type: "<name>", fired_at: NOW, task_folder: <abs>, user_choice: "automatic", bypass_reason: null, gate_specific: <loader-output> + {retrofitted: true}}`); write via `gate-audit-write.sh`.
   - **`_pre-analysis.json` grandfather marker** (optional, user-confirmed in `[s]elect`): write marker audit with `gate_specific.grandfathered: true` and `bypass_reason: "grandfathered_retrofit"`.
   - **`alignment.md`**: flagged only; user invokes `/scope` separately.

8. **Final summary.** Print: project-state fields written + tasks retrofitted (per-task closures) + already-current count + manual-attention items (alignment.md missing, _pre-analysis.json grandfathered). Exit `0` always under `--dry-run`; exit `0` on success or no-op; exit `2` on resolution/preflight failure.

## Idempotency + safety

- **Journal-backed atomic** project-state batch (Step 4); `--resume` continues from interruption.
- **Symlink rejection** at task level (Step 5).
- **Audit JSON validation** before treating as present (Step 5; corrupt → rewrite with `replaced_corrupt: true`).
- **Bounded $PWD walk-up** (Step 1; capped at $HOME / 5 levels).
- **Charset enforced** on `<project-name>` (Step 1).
- **Glob filtered** to exclude `.migration-tmp/*` and nested `completed/*` (Step 5).
- **Already-explicit / already-current**: silent skip.
- **`/set-*` failure**: journal preserves partial state for resume.

## Pointers

- Wizard delegates to: `/set-code-path`, `/set-playbook-sets`, `/set-user-playbook`
- Reader: `scripts/project-state-read.sh` (extended in v4.1.0 to parse `**Review Required:**` with truthy variants)
- Audit writer: `scripts/gate-audit-write.sh` (accepts `gate_specific.retrofitted: true` + `replaced_corrupt: true` additive flags)
- Source-of-truth scaffolders: `commands/new.md` + `skills/project-initializer` (project-side); `references/research-walkthrough.md` Step 2 + `scripts/fm-helpers.sh write_stub_task_md` (task-side)

## Related

- `/drupal-dev-framework:set-code-path` / `:set-playbook-sets` / `:set-user-playbook` — invoked by this wizard
- `/drupal-dev-framework:complete` — Step 3 honors `**Review Required:**` (set this via `/upgrade-project`)
- `/drupal-dev-framework:validate-playbook-adherence` — surfaces implicit-inheritance hint when Playbook Sets defaults
