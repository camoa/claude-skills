---
description: "Retrofit the active project to current scaffolder parity. Trigger: 'upgrade project', 'retrofit', 'bring project up to date', 'modernize project state'. Backfills project_state.md fields (Code Path, Playbook Sets, User Playbook + state, Worktree By Default, Review Required) AND iterates in-progress tasks for task-level gaps (frontmatter, Phase 4 line, missing audit JSONs). Once frameworks are known, runs a recipe-adoption sweep that records process-recipe sources for all applicable lifecycle phases and reports a coverage map (recording + visibility only — execution stays lazy). Active-project-only, never bulk. Wizard pattern delegating to existing /set-* commands. Idempotent + journal-based atomic. Introduced v4.1.0."
allowed-tools: Read, Edit, Bash, Glob, Skill
argument-hint: "[<project-name>]"
---

# Upgrade Project

Bring the active project on par with what a fresh project would scaffold today. Two passes per invocation: project-state fields, then in-progress tasks — plus a recipe-adoption sweep that runs between them once `**Frameworks:**` is known. Active-project-only; never iterates the registry. Wizard pattern — delegates to existing `/set-*` commands so field-validation lives in one place.

## Usage

```
/ai-dev-assistant:upgrade-project              # active project (from session-context)
/ai-dev-assistant:upgrade-project <name>       # specific project
/ai-dev-assistant:upgrade-project <n> --dry-run         # preview without writing (exit 0 always)
/ai-dev-assistant:upgrade-project <n> --rerun-loaders   # auto-write missing audit JSONs
/ai-dev-assistant:upgrade-project <n> --skip-tasks      # project-state pass only
/ai-dev-assistant:upgrade-project <n> --resume          # continue interrupted upgrade from journal
```

**Flag precedence (M7):** `--dry-run` > `--resume` > `--rerun-loaders`. Combinations: `--dry-run --rerun-loaders` shows would-have-applied; `--dry-run --resume` reads journal but writes nothing; `--rerun-loaders --resume` continues a prior auto-mode run.

## What this does

1. **Resolve active project + preflight.** Validate `<project-name>` matches `^[a-z][a-z0-9_]*$` (charset; exit 2 with usage on mismatch — path-traversal mitigation). Resolve by running `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-read.sh` (Bash) and parsing its JSON (`.project`, `.projectPath`); else walk up from `$PWD` to find `implementation_process/`, capped at `$HOME` or 5 levels (whichever first; exit 2 if exhausted). When BOTH resolve, compare; mismatch → prompt user to confirm before proceeding (defense vs spoofed session-context). Verify required scripts exist + executable: `project-state-read.sh`, `dev-guides-detect.sh`, `playbook-load-deterministic.sh`, `coverage-mapping-check.sh`, `gate-audit-write.sh`, `fm-helpers.sh`. Verify `/set-code-path`, `/set-playbook-sets`, `/set-user-playbook` command files present. Exit 2 on any preflight failure.

2. **Project-state pass — gap detection.** Run `bash scripts/project-state-read.sh <project>`. Inspect emitted JSON. For `**Review Required:**` and `**Run Mode:**` (spine_memory), also direct-grep the dial line (`grep -i '^\*\*[Rr]eview [Rr]equired:\*\*'` / `grep -i '^\*\*[Rr]un [Mm]ode:\*\*'`) — the reader always emits `.runMode` (defaults `interactive`) so JSON-absence can't detect a missing *line*; gap fires only when the grep finds nothing (idempotent, never reads/trusts an existing autonomous value). Build `gaps[]` for: `**Code Path:**` (absent / `code_path_unknown`), `**Playbook Sets:**` (`playbook_sets_source: "default"` = implicit), `**User Playbook:**` + state (`unset`), `**Worktree By Default:**` (absent), `**Review Required:**` (absent), `**Run Mode:**` (line absent), `**Orchestration policy:**` (`<project>/orchestration-policy.json` absent beside `project_state.md`), `**Frameworks:**` (`frameworks == []` and codePath is known), **E2E preflight seam** (see below).

3. **Project-state pass — single batch prompt** (verbatim; **H5 fix**: do NOT interpolate raw `project_state.md` content into the prompt — show field NAMES + a sanitized resolved-value summary only, max 60 chars per value, control-chars stripped, brackets escaped). Under `--dry-run`, the prompt becomes "would-have-applied" (M9): same content, header changed to "Found {N} project-state gaps (DRY RUN — no writes will occur):". Verbatim form:
   ```
   Found {N} project-state gaps in <project>:
     - Code Path:           absent → /set-code-path will detect+confirm
     - Playbook Sets:       inherits "<framework>/best-practices/<author>" from default
     - User Playbook:       unset
     - Worktree By Default: absent (default false)
     - Review Required:     absent (legacy default: false on projects with completed/ non-empty)
     - Run Mode:            absent → interactive + seed orchestration-policy.json (NEVER autonomous)

   How to proceed?
   [a]pply all — confirm current resolved values as explicit (lossless)
   [s]elect    — interactive per-gap [c]onfirm | [e]dit | [s]kip
   [n]one      — skip project-state pass
   ```
   No default; user MUST pick. On non-`a/s/n` input, re-display verbatim (do not infer).

4. **Project-state pass — apply via journal-backed atomic batch with file-lock (H4).** Before any write, acquire exclusive lock via `flock` on `<project>/.upgrade-project-journal.lock` (refuse with "another /upgrade-project run in progress" + exit 2 if held). Then create `<project>/.upgrade-project-journal.json` with planned operations + per-op `done: false`. For each gap:
   - `**Code Path:**` → invoke `/ai-dev-assistant:set-code-path` via `Skill` (H6: dual-validation — set-code-path already validates internally)
   - `**Playbook Sets:**` → invoke `/ai-dev-assistant:set-playbook-sets <validated-comma-list>`. **H6 fix**: BEFORE invocation, validate each comma-split element matches `^[a-z][a-z0-9/_.-]*$`; refuse with diagnostic on mismatch (defense-in-depth alongside `set-playbook-sets`'s own dev-guides-navigator validation)
   - `**User Playbook:**` → invoke `/ai-dev-assistant:set-user-playbook`
   - `**Worktree By Default:**` → direct `Edit` insert `**Worktree By Default:** false` (no setter exists; literal value, no interpolation)
   - `**Review Required:**` → direct `Edit` insert with computed legacy default (literal value)
   - `**Run Mode:**` (spine_memory) → direct `Edit` insert the literal line `**Run Mode:** interactive` (no interpolation, mirrors the Worktree/Review inserts); then seed the policy sibling when absent via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/orchestration-policy-write.sh" "<project_folder>" interactive` (idempotent, preserves arrays). **MUST write `interactive`; MUST NEVER write `autonomous`** — no legacy project is silently granted autonomy by an upgrade.
   - `**Frameworks:**` → skip silently when codePath is unknown or `code_path_unknown`. Otherwise run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-frameworks.sh" "<codePath>"`. If the result is a non-empty JSON array, direct `Edit` insert `**Frameworks:** <jq -r 'join(", ")' of the array>` (e.g. `drupal, nextjs, claude-code-plugins`) after the last existing metadata field in the top block (same insertion approach as `**Worktree By Default:**`). If the result is empty, skip silently. Never write an empty or placeholder line.
   - `**E2E preflight seam:**` → detected when (a) `**Code Path:**` is known (skip if `code_path_unknown`), (b) `<codePath>/.visual-review/registry.yml` exists, (c) that file does NOT contain `preflight_command:` (any indentation), AND (d) `<codePath>/tests/e2e/` directory exists (signals an e2e harness was set up). The agnostic e2e gate only executes the preflight when the registry carries `e2e.preflight_command`; without this field, projects set up before the seam existed silently skip the preflight. Remediation: resolve the project's `e2e-setup` process recipe (per `references/recipe-resolution.md`, using the `**Frameworks:**` value backfilled above) and read its declared `preflight_command`. With a command in hand, run `bash scripts/ensure-registry-preflight.sh "<codePath>/.visual-review/registry.yml" "<preflight_command_from_recipe>"` (the helper is idempotent — no-ops when the field is already present). If no `e2e-setup` recipe resolves, or the resolved recipe declares no `preflight_command`, SKIP this gap with a flagged note ("e2e preflight seam: no framework recipe declared a preflight_command — set `e2e.preflight_command` in the registry manually if the harness needs one"). NEVER inject a framework-specific preflight command by assumption — a wrong command would fail every e2e run. Under `--dry-run`: report "would resolve e2e-setup recipe and run ensure-registry-preflight.sh for <project> (<registryPath>)" without resolving or invoking the script.
   After each write, mark `done: true` in journal. On any failure: stop, leave journal + lock, surface "partial state — run with `--resume` to continue from {next-undone-op}". On full success, delete journal + release lock. `--resume` re-acquires lock and skips `done: true` entries.
   Under `--dry-run`: emit "would invoke /set-X with args ..." per gap; do NOT acquire lock, write journal, or invoke setters.

4b. **Recipe-adoption sweep — record the map, report the gaps** (runs after Step 4 once `**Frameworks:**` is known; part of the project-level work, so it runs even with `--skip-tasks`; skipped only when frameworks are empty). The eager on-ramp that complements child 1's lazy point-of-need trigger: it resolves + RECORDS process recipes for ALL applicable phases in one pass so the coverage map is visible up front, instead of being discovered one phase at a time mid-work. **It records source decisions and reports coverage; it does NOT pre-cache or follow recipe bodies, and it does NOT approve unverified recipes** — bodies are still Read and followed lazily per-phase at use-time, and `verified:false` recipes still get human review then. This is a recording + visibility pass, not an execution commitment.
   - **Guard.** Re-run `bash scripts/project-state-read.sh <project>` to read the now-current `.frameworks` and `.processRecipes`. If `.frameworks == []` (no codePath, undetectable stack, or user declined the Frameworks gap in Step 4), SKIP the sweep with a one-line note ("recipe-adoption sweep skipped: no **Frameworks:** set"). Never fail.
   - **Snapshot for idempotency.** Capture the set of already-recorded keys from `.processRecipes` (each entry's `key`) BEFORE driving the loader. A key resolved during the sweep that is in this snapshot is reported "already"; one not in it is "newly recorded". The loader's `write_source_record` is itself idempotent (an unchanged line is a no-op — rc 3 — so re-running the sweep produces no churn); this snapshot only labels the report.
   - **Drive the loader once per phase.** For each phase in the declared list in `references/recipe-resolution.md` ("Phases that resolve a framework recipe") — `research`, `design`, `implement`, `review`, `e2e-setup`, `visual-regression` — invoke the `process-recipe-loader` skill (Skill tool) with `phase: <phase>` and `project_folder: <project_folder>`. The loader resolves every framework for that phase, records each resolved `source=` line into `project_state.md` (idempotently), and returns its per-result JSON `{available, source, verified, recorded, action, body_path, notes[]}` + `warnings[]`. Resolution mechanics (source order, trust model, the `project_state` short-circuit, the source-record write) live in `references/recipe-resolution.md` and the loader — do not re-describe them here. **The sweep never Reads `body_path` and never follows a body** (no pre-caching; execution stays lazy).
   - **Non-blocking on every miss.** The sweep is informational and MUST NOT prompt. Treat each no-body outcome as "no recipe yet" in the coverage map — do NOT enter the loader's `action:ask-user` interactive protocol, do NOT ask the user for a path, do NOT research or fabricate. Specifically: `available:false` + `action:ask-user`, a `recipe_not_published:<fw>` warning, a `navigator_unavailable:<fw>` warning, and `results:[]` with `no_frameworks_defined` all map to "no recipe yet" for that (phase, framework). Render `navigator_unavailable` as a transient "no recipe yet (navigator unavailable — re-run)" distinct from the benign "not published yet".
   - **Coverage report.** After all six phases, print the map (per phase, per framework):
     ```
     ## Process-recipe adoption — coverage map (<project>)

     Frameworks: <fw1>, <fw2>
     Swept phases: research, design, implement, review, e2e-setup, visual-regression

     | phase             | <fw1>                          | <fw2>            |
     |-------------------|--------------------------------|------------------|
     | research          | ✓ source=dev-guides (recorded) | — no recipe yet  |
     | design            | ✓ source=local (already)       | — no recipe yet  |
     | implement         | — no recipe yet                | — no recipe yet  |
     | review            | ✓ source=dev-guides (recorded) | — no recipe yet  |
     | e2e-setup         | — no recipe yet                | — no recipe yet  |
     | visual-regression | — no recipe yet (navigator unavailable — re-run) | — no recipe yet |

     Recorded: {newly} newly, {already} already (idempotent). Gaps (no recipe yet): {G} of {phases×frameworks}.
     Bodies are NOT pre-cached — each is Read + followed lazily at its phase; verified:false recipes still get human review at use-time.
     ```
     Per cell: `✓ source=<src> (recorded|already)` when `available:true` (`recorded` = key absent from the pre-sweep snapshot, written this run; `already` = key in the snapshot, no churn); otherwise `— no recipe yet` (append the transient reason for `navigator_unavailable`). Make the gaps visible — the gap count is the headline.
   - **`--dry-run`:** do NOT invoke the loader (it writes). Report "would sweep phases [research, design, implement, review, e2e-setup, visual-regression] across frameworks [<list>] and record resolved `source=` lines into project_state.md — no writes". Use the frameworks Step 4 would have set (the `detect-frameworks.sh` result) when `**Frameworks:**` is not yet on disk. Exit 0.
   - **Unattended-safe.** The sweep auto-runs with no prompt; in a `--headless`/auto run it records what resolves and reports the gaps identically (no interactive arm is ever entered). It never blocks the upgrade.

5. **Task-level pass — discovery** (skip if `--skip-tasks` OR project-pass-aborted). `Glob <project>/implementation_process/in_progress/**/task.md`, then **filter** to exclude paths matching `*/.migration-tmp/*` or `*/completed/*` (anchored to /completed/, not the project's top-level completed/ which is already outside in_progress/**). Per task, `bash scripts/fm-helpers.sh` parses frontmatter; reject task on YAML parse failure with diagnostic. Build per-task `gaps[]`:
   - Missing v3.10.0 frontmatter keys (full set: `id`, `kind`, `parent`, `children`, `blocks`, `blocked_by`, `external_ids`, `status`)
   - Missing `## Phase Status` H2 OR missing `Phase 4: Review` line
   - Missing audit JSONs for **completed** phases only: Phase 1 [x] expects `_dev-guides-load.json`, `_playbook-load.json`, `_coverage-mapping.json`. Validate existing audits with `jq empty <file>`; treat parse-failed as absent (annotate `replaced_corrupt: true` on rewrite).
   - `_pre-analysis.json` absent + `research.md` present → mark `grandfathered`
   - `alignment.md` absent → flag-only
   - **Symlink rejection (H3 — directory-aware, TOCTOU-safe):** resolve task folder via `realpath -e <task>`; assert canonical path is a prefix of `<project>/implementation_process/in_progress/`. Reject task if any of: (a) `<task>` itself is a symlink (`[ -L "<task>" ]`), (b) any directory component of `realpath` differs from the lexical path (catches symlink within hierarchy), (c) any artifact file is a symlink, (d) any descendant of `<task>/validations/` is a symlink. Skip task with diagnostic "symlinked path component detected; refusing for safety". Note: TOCTOU still possible between resolve and read; document as known limit (no full mitigation without OS-level isolation).

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
   - **Audit backfill**: invoke `dev-guides-detect.sh`, `playbook-load-deterministic.sh`, `coverage-mapping-check.sh` per task; wrap each output in standard envelope via jq (`{schema_version: "1.0", gate_type: "<name>", fired_at: NOW, task_folder: <abs>, user_choice: "automatic", bypass_reason: null, gate_specific: <loader-output> + {retrofitted: true}}`); write via `gate-audit-write.sh`. **`dev-guides-detect.sh` requires `--phase` (v4.10.0+):** pass the phase that matches the task's current progress — the highest phase the task has marked `[x]` in `## Phase Status` (Phase 1 → `research`, Phase 2 → `design`, Phase 3 → `implement`); default to `research` when no phase is complete. Backfill only re-fires loaders for phases the task has actually completed.
   - **`_pre-analysis.json` grandfather marker** (optional, user-confirmed in `[s]elect`): write marker audit with `gate_specific.grandfathered: true` and `bypass_reason: "grandfathered_retrofit"`.
   - **`alignment.md`**: flagged only; user invokes `/scope` separately.

8. **Final summary.** Print: project-state fields written + recipe-adoption coverage (recorded count + gaps, or "sweep skipped: no Frameworks") + tasks retrofitted (per-task closures) + already-current count + manual-attention items (alignment.md missing, _pre-analysis.json grandfathered). Exit `0` always under `--dry-run`; exit `0` on success or no-op; exit `2` on resolution/preflight failure.

## Idempotency + safety

- **Journal-backed atomic** project-state batch (Step 4); `--resume` continues from interruption.
- **Recipe-adoption sweep is idempotent + non-blocking** (Step 4b): relies on the loader's idempotent `write_source_record` (unchanged line = no Edit), reports "already" vs "newly recorded" from a pre-sweep snapshot, never prompts (every miss = "no recipe yet"), never pre-caches or follows bodies, never approves `verified:false` recipes.
- **Symlink rejection** at task level (Step 5).
- **Audit JSON validation** before treating as present (Step 5; corrupt → rewrite with `replaced_corrupt: true`).
- **Step 1 guards**: bounded $PWD walk-up (capped at $HOME / 5 levels) + charset-enforced `<project-name>`.
- **Glob filtered** to exclude `.migration-tmp/*` and nested `completed/*` (Step 5).
- **Already-explicit / already-current** → silent skip; **`/set-*` failure** → journal preserves partial state for `--resume`.

## Pointers

- Wizard delegates to: `/set-code-path`, `/set-playbook-sets`, `/set-user-playbook`
- Reader: `scripts/project-state-read.sh` (parses `**Review Required:**` truthy variants; `**Run Mode:**` → `.runMode`, spine_memory). Policy slot: `scripts/orchestration-policy-{read,write}.sh` + `references/orchestration-policy-schema.md`
- Audit writer: `scripts/gate-audit-write.sh` (accepts `gate_specific.retrofitted: true` + `replaced_corrupt: true` additive flags)
- Source-of-truth scaffolders: `commands/new.md` + `skills/project-initializer` (project-side); `references/research-walkthrough.md` Step 2 + `scripts/fm-helpers.sh write_stub_task_md` (task-side)

## Related

- `/ai-dev-assistant:set-code-path` / `:set-playbook-sets` / `:set-user-playbook` — invoked by this wizard
- `/ai-dev-assistant:complete` — Step 3 honors `**Review Required:**` (set this via `/upgrade-project`)
- `/ai-dev-assistant:validate-playbook-adherence` — surfaces implicit-inheritance hint when Playbook Sets defaults
