<!--
  AUTHORING REFERENCE — for maintainers working on the plugin source.
  This file was named CLAUDE.md through v4.5.0. It was never loaded into
  Claude's context (a plugin-root CLAUDE.md is not — see
  https://code.claude.com/docs/en/plugins-reference), and the misleading name
  tripped `claude plugin validate`. Renamed to CONVENTIONS.md in v4.6.0.
  Instructions that must reach Claude at runtime live in skills/.
-->

# Drupal Dev Framework - Plugin Conventions

## Task Hierarchy (v3.10.0+)

The plugin supports **opt-in epic/sub-task hierarchy** on top of flat tasks (which remain first-class). Concepts:

- **Flat task** — default. No frontmatter needed. Behaves exactly as v3.0.0+.
- **Epic** — a task folder containing `task.md`, `shared/`, `in_progress/<subtasks>/`, and `completed/<subtasks>/`. Declared via `task.md` frontmatter (`kind: epic`, `children: [local:<id>, ...]`).
- **Sub-epic** — a subtask that is itself an epic (second and final nesting level; no sub-sub-epics).
- **Subtask** — a task nested inside an epic's `in_progress/` (while active) or `completed/` (when done). Completion never removes a subtask from its parent epic.

**Key commands:**
- **`/drupal-dev-framework:migrate-to-epic <task>`** — convert a flat task into an epic, OR (v4.4.0+) promote a subtask to a sub_epic (second and final nesting level). The same command handles both paths; the path is chosen by where `<task>` resolves (top-level vs nested under an epic). Manual, per-task, transactional. Supports `--dry-run` and `--children "a,b,c"`. Refuses when the would-be parent is already a `sub_epic` — max nesting depth is 2.
- `/status` is hierarchy-aware — renders a tree for epics, flat list for flat tasks.
- `/next` biases toward sibling subtasks inside the active epic; surfaces `/migrate-to-epic` when a task looks epic-sized.
- `/complete` enforces epic-completion gates (all children done before the epic itself completes).

**When to promote a task to epic:** many heterogeneous acceptance criteria, long-in-progress without phase progression, or user signals "this is too big." Most tasks should stay flat — epic-ification is additive, not aspirational.

**Automated epic proposal (`/propose-epics`) landed in v3.11.0** — bulk-review of flat in-progress tasks via `analysis-agent` (read-only, sonnet), per-task accept/edit/reject/skip, accepted proposals invoke `/migrate-to-epic`. Plus `/research` pre-analysis hook that fires on strong signals (description > 500 chars, ≥3 bullets, explicit conjunctions) at new-task creation time. The scope-contract alignment step landed in v3.12.0 — see `## Alignment Step` below.

## Project codePath Metadata (v3.11.0+)

Projects can declare where their code lives, distinct from the memory folder. Three states:

- **unknown** — never set. Features needing code trigger first-use detect+confirm.
- **docs-only** — user declared no code base. Features needing code skip silently.
- **set** — `/abs/path`. Used by code-aware features.

Commands: `/set-code-path [<path>|--docs-only]` (explicit/sentinel/interactive), `/new` (captures at project creation).

Consumers distinguish states via warnings, not the null value: `code_path_unknown` warning → trigger detect+confirm; `codePath: null` with no warning → docs-only. See `references/code-path-detection.md` for the three-null-states table and the safety filter (hard-rejects `/`, `/etc`, `/usr`, `$HOME` ancestors, etc.).

## Analysis Agent (v3.11.0+)

`analysis-agent` is read-only (Read/Grep/Glob + Bash with mutation-subcommand denylist). Consumed by `/propose-epics` (folder mode, bulk review) and `/research` pre-analysis hook (description mode, pre-folder-creation). Emits structured JSON per `references/analysis-agent-schema.md` v1.0 — never modifies state, never chats with user. Output is consumed programmatically by the calling command.

**Signal orthogonality:** `signals_used[]` contains BOTH epic-decomposition signals (used for the `decision` branch) AND orthogonal signals like `scope_contract_recommended` (v3.12.0+). Consumers branch on `decision` for decomposition and separately inspect `signals_used[]` for scope-contract warrant. The two judgments are independent.

## Validation Gates (v3.13.0+)

Individual `/validate:*` commands for on-demand quality gates. Replaces `/complete`-only all-or-nothing gating with per-aspect, per-moment validation.

**8 gates + 1 orchestrator (v4.1.0+):**
- `validate-tdd` / `validate-solid` / `validate-dry` / `validate-security` — thin wrappers over `code-quality-tools` skills; add task context + persistence + shared envelope
- `validate-guides` — framework-owned; verifies `research.md` + `architecture.md` cite `dev-guides-navigator` guides. **Hardened in v4.1.0 to dual-mode** — soft-nudge standalone, hard-block-capable when invoked from `/review` (via `<!-- /review:hard-block -->` capability marker + `--hard-block` argv flag). **v4.3.0 adds catalog-grounded code-change inference** — gate collects changed files from session edits + `implementation.md` Files Created/Modified + git working tree, then dispatches the `guides-matcher` agent (haiku, read-only) to match them against the cached dev-guides catalog. Slugs the agent matches but no artifact citation covers → `domain_coverage_gaps[]` → demote `pass` → `warning`. Symmetric `/implement` Step 3 component-aware preflight runs `guides-matcher` in plan mode against architecture.md planned components and augments the keyword-detect auto-load list. Catalog is the only taxonomy — no parallel hardcoded map. Suppress gate inference with `--no-code-inference`. See `references/guides-matcher-schema.md`.
- `validate-playbook-adherence` (**new in v4.1.0**) — heuristic cite-checker for loaded plays; literal-string match (`Grep -F`) per match-type; section-aware skip on `Rejected` / `Considered Alternatives` / `Out of Scope` headings; `--hard-block` / `--strict` / `--invoked-by` flags
- `validate-visual-regression` — **reworked v4.13.0 (Task C)**: registry-driven, runs the committed `tests/visual/` suite on `@lullabot/playwright-drupal`; multi-viewport batch; a11y baseline pairing; mask regions; classification UX kept. No positional args (registry-driven). `gate_type: visual_regression`; carries `<!-- visual-review:dispatch-ready -->`. See `## Visual Regression Gate` below.
- `validate-visual-parity <component> <viewport> <reference>` — compares against design comp (PNG/JPG, Figma URL via MCP, HTML file headless-rendered). React/PSD/Sketch deferred to v2 (Task D reworks this on Lullabot)
- `validate-all` — sequential orchestrator; non-interactive CI mode runs visual-regression with `--ci` (any diff → `fail`, no prompts, no baseline writes), skips visual-parity

**Shared result envelope** (per `references/validation-gate-result.md` v1.0): every gate emits `{schema_version, gate, task, run_at, verdict, details, messages}`. Verdicts: `pass | warning | fail | skipped`. Persisted to `<task>/validations/latest/<gate>.json` (overwrite) + `<task>/validations/history.jsonl` (append).

**Screenshot store** (per `references/screenshot-store-schema.md` v1.0): **codePath-native since v4.13.0** — baselines are committed Playwright snapshots at `<codePath>/tests/visual/<surface>.spec.ts-snapshots/`, with `.meta.json` provenance sidecars in-tree. The 9-field `.meta.json` schema is unchanged (`role`, `captured_by` enum, `prior_hash`, `source`); only the location moved (and the legacy `.previous` rotation is retired — git holds history). The v3.13.0 memory-project `.screenshots/` store is a migration source only — `migrate-screenshots-to-codepath.sh` imports it.

**Soft-nudge posture:** `fail` signals but never blocks; visual diffs require explicit user classification; `/validate:all` CI mode explicitly skips prompts rather than silent-defaulting.

**Hard dependency:** `code-quality-tools` (v3.0.0+) added to `plugin.json`. Second hard dep alongside `dev-guides-navigator`.

**NOT wrapped** (keep invoking directly via `/code-quality:*` namespace): `lint`, `coverage`, `review`, `audit`, `ultrareview`, `architecture-debate`, `security-debate`. `/validate:all` surfaces them as discoverability hint.

## Hardened Gates (v4.0.0+)

v4.0.0 converts 7 framework surfaces from soft-prompt to hard-gate, applying the original critique's 5-mechanism pattern uniformly. **BREAKING CHANGE** for users on the soft posture: documented bypass paths are removed; explicit `--skip-*` flags required to skip. Bypass reasons are recorded on disk (`<task>/_<gate>.json`) for retrospective audit.

The 7 hardened surfaces, by category:

**User-prompt surfaces (5)** — fire user prompts with mandated wording from `references/gate-hardening-prompts.md` v1.0:

1. **Pre-analysis epic gate** at `/research` — always-on (was: signal-conditional). Invokes `analysis-agent` regardless of signals; user sees verbatim agent output before pick.
2. **Coverage-mapping requirement** at end-of-`/research` — `## Coverage Mapping` H2 mandatory in research.md; verified by `scripts/coverage-mapping-check.sh`; refuses Phase 1 `[x]` on fail.
3. **Skill-review** at `/complete` — fires when staged/branched changes include `skills/*/SKILL.md`; invokes `plugin-creation-tools:skill-quality-reviewer`.
4. **Plugin-validate** at `/complete` — fires when staged/branched changes include any plugin file; invokes `/plugin-creation-tools:validate`.
5. **Phase-command-bypass** detected by PreToolUse hook on Write to phase artifacts — non-blocking audit when no `/research` / `/design` / `/implement` slash command is active.

**Deterministic surfaces (2)** — fire shell scripts that detect+act without user prompts; bypass-by-declaration is impossible:

6. **Dev-guides preflight** — `scripts/dev-guides-detect.sh` greps task content for auto-load keywords; replaces agent-mediated detection.
7. **Playbook loading** — `scripts/playbook-load-deterministic.sh` reads `project_state.md` and loads via `playbook-read.sh` + dev-guides-navigator; replaces agent-mediated load.

**The 5-mechanism pattern** applied uniformly:

1. Anti-bypass clause (literal block in command body)
2. Show-not-summarize (verbatim agent output before user prompt)
3. Audit on disk (`<task>/_<gate>.json` per fired gate)
4. Mandate exact prompt wording (literal templates; no paraphrase)
5. Refactor "if X, do Y" → "validation gate, always evaluated"

**Audit shape:** unified schema in `references/gate-audit-schema.md` v1.0 with `gate_type` discriminator; per-gate `gate_specific` payload; overwrite-on-fire lifecycle.

**Skip flags:** per-gate `--skip-pre-analysis`, `--skip-coverage-check`, `--skip-skill-review`, `--skip-plugin-validate`. Each writes the audit file with `bypass_reason` field populated. Visible later via `/audit-status` and `/status` "Unaudited gates" section.

**Grandfathering:** v3.x in-flight tasks (those past Phase 1 at v4.0.0 install) keep their original soft contract. Heuristic: `research.md present && _pre-analysis.json absent` → grandfathered.

**5 surfaces deferred to v2** (pending documented bypass evidence): phase transition checks, playbook conflict ack, worktree recommendation, candidate-play surface, `/validate:*` exit codes. Tracked in `dev_framework_improvements_epic/shared/v2-candidates.md` Set D.

`/audit-status` provides per-task audit-state view; `--all` flag for project-wide rollup grouped by health.

## Review Phase (v4.1.0+)

`/drupal-dev-framework:review <task>` is **Phase 4** — runs all hard-blocking validation gates between `/implement` and PR creation, with the v4.0.0 5-mechanism pattern. Driver: feedback memo `feedback_framework_phase_gates.md` ("sometimes your analysis forgets to follow the rules"); shipping framework changes without enforcement leaves the contract underspecified.

**Components:**
- `commands/review.md` (114/120 body lines) — orchestrator; delegates to `/validate:all` (default) or `/validate:team` (`--team`); flags `--dry-run` / `--rerun-failed` / `--no-pr-body` / `--skip-<gate> <reason>` / `--allow-dirty`
- `references/gate-hardening-prompts.md` v1.2 — `review-gate-fail` + `review-summary` templates (byte-identical to inline literals; verified by `tests/gate-prompts-vs-inline.sh`)
- `references/gate-audit-schema.md` v1.1 §5.8 — `_review.json` audit shape (`gate_type: "review"`)
- `commands/complete.md` slimmed (11→9 steps); honors `**Review Required:**` for legacy posture

**Cross-references:** `references/review-phase-walkthrough.md` (full prose); `references/feedback_framework_phase_gates.md` (driver memo).

## Visual + E2E Review (v4.11.0+)

The `visual_and_e2e_review_gates` epic adds **three rendered-output review surfaces** so
`/review` validates not just that source follows the rules, but that the page works and
looks correct:

- **E2E (behavioral)** — does the flow still work? — ATK + Playwright (Task B)
- **Visual regression** — did anything change vs. last green? — `@lullabot/playwright-drupal` (Task C)
- **Visual parity** — does this match the design intent? — Lullabot, shared with VR (Task D)

**Evolve, not greenfield.** v3.13.0 already shipped `validate-visual-regression` /
`validate-visual-parity` on ad-hoc Playwright MCP capture. The epic KEEPS the
`.meta.json` provenance model, the `validation-gate-result.md` envelope, and the
classification UX; REPLACES capture (committed Playwright test files), invocation
(registry-driven batch), and diff tooling; ADDS the E2E gate, the dispatcher, a11y
pairing, and masks.

**Two runtimes, one infrastructure.** E2E and visual review ride one Playwright
install, one `playwright.config.ts`, one DDEV `playwright` service, one surface
registry — split only at the test-library layer (`tests/e2e/` vs `tests/visual/`,
separate `projects[]` entries).

**Opt-in.** A project has zero review surface until a `/setup-*` command runs. The
`**Visual Review:**` field in `project_state.md` points at the surface registry
(`<project>/.visual-review/registry.yml`); absent ⇒ not set up. `/review` on an
un-set-up project runs zero new gates and says so.

**Change-impact dispatcher — a RECOMMENDER, not an enforcer.** `/review` step 6
(v4.11.0+) classifies the merge-base diff and *recommends* gates per
`change-impact-rules.json`; the user opts in **per task** via a `## Review Gates` block
in `task.md` (written once, never re-asked). `visual_parity` is not part of the opt-in
— it auto-runs (soft) on design-implementation tasks. Forcing heavy gates on every CSS
tweak would make users disable the feature.

**Task A — Foundation (v4.11.0)** ships plumbing only — **zero new commands, zero
runtime files in any project**: the surface-registry schema, the change-impact
dispatcher + `scripts/change-impact-classify.sh`, `gate-audit-schema.md` v1.2 (`e2e` +
`visual_regression` gate_types, the `review` payload's `dispatch_plan` key), the
`**Visual Review:**` field in `project-state-read.sh`, and the
`playwright-base.config.ts` reference template. Tasks B/C/D add the user-facing
`/setup-*` and `/validate:*` commands.

**References:** `references/visual-review-walkthrough.md` (full model),
`references/visual-review/{surface-registry-schema,change-impact-rules,change-impact-dispatch}.md`,
`references/visual-review/playwright-base.config.ts`.

## Retrofit Tools (v4.1.0+)

`/drupal-dev-framework:upgrade-project` retrofits the active project to current scaffolder parity — backfills missing fields onto `project_state.md` (Code Path, Playbook Sets, User Playbook + state, Worktree By Default, Review Required) AND iterates in-progress tasks for task-level gaps (frontmatter, Phase 4 line, missing audit JSONs). Active-project-only; never bulk across the registry.

**Pattern:** wizard delegating to existing `/set-code-path`, `/set-playbook-sets`, `/set-user-playbook` for writes. Journal-backed atomic batch (`<project>/.upgrade-project-journal.json`) with `--resume`. Symlink rejection. Bounded $PWD walk-up. Charset validation. Glob filter excludes `.migration-tmp/*` + nested `completed/*`.

**Cross-references:** `references/upgrade-walkthrough.md` (full prose).

## Session Remembrance (v4.5.0+)

Per-project session-lifecycle hooks that survive compaction, `/clear`, and new sessions. **Opt-in per project.**

- **`/install-remembrance-hook`** — interactive, idempotent installer. Fills a session primer (framework facts + free-form user reminders) from `templates/session-primer.md`, then merges two hook entries into `<project>/.claude/settings.json`:
  - **`SessionStart`** (no matcher) — `cat`s the primer to stdout. SessionStart stdout is injected as context, and the event fires on `startup` / `resume` / `clear` / **`compact`** — so one entry also covers post-compaction re-injection. **No `PostCompact` hook** is used: `PostCompact` stdout is not injected into context, so it cannot do this job.
  - **`SessionEnd`** (exec form, `timeout: 10`) — runs `save-session.sh`. SessionEnd's default budget is 1.5 s; a per-hook `timeout` in a project `settings.json` raises it.
- **`/save-session`** — judgement-first persistence: Claude reviews in-flight task state, then runs `save-session.sh`. The `SessionEnd` hook runs the same script unconditionally as a scripted safety net.

**`scripts/save-session.sh`** is pure bash (no AI). It resolves the per-workspace session file (`md5(cwd)` scheme), stamps `savedAt`, scans the task folder for markdown changed since the last save (warns on stderr **only when changes are detected**), and adds an additive `session_saved_at` field to task-folder audit JSONs. The installer copies it into `<project>/.claude/drupal-dev-framework/` — `${CLAUDE_PLUGIN_ROOT}` does not resolve in a project `settings.json`, and an absolute plugin path breaks on plugin update.

The filled primer at `<project>/.claude/drupal-dev-framework/session-primer.md` is **user-editable by hand**. Re-run `/install-remembrance-hook` if the project name, memory path, or code path changes — the primer is a static snapshot.

## Worktree Workflow (v3.16.0+)

Two Claude Code sessions on the same project workspace collide on `~/.claude/drupal-dev-framework/sessions/<md5($PWD)>.json` (last-writer-wins) and on the git working tree itself. Solution: the second session runs in a worktree at `.worktrees/<task_name>/`. Distinct `$PWD` → distinct hash → independent session-context. **No changes to `session-context-writer` — the existing hash naturally separates worktree sessions.**

**Commands:**
- `/worktree <task>` — create a worktree on `feature/<task>` from current HEAD; runs auto-detect setup; pre-seeds session-context. Refuses to double-wrap (refuses when already in a worktree). Drupal/DDEV-aware: warns about `.ddev/config.yaml` `name:` key conflict.
- `/worktree-prune` — list and selectively remove worktrees; per-worktree confirm; honors git's refusal on uncommitted changes; force-remove requires explicit per-worktree confirmation.

**Detection:** `/implement <task>` invokes `worktree-signals.sh` BEFORE Phase Transition Check. Signals (HIGH-strength only trigger): `another_task_active` (recent commits to another task's tracked files within 2 hours), `dirty_tree` (uncommitted changes matching another task), `multi_session` (medium-high; informational), `--worktree` flag, `worktreeByDefault: true` in `project_state.md`. Suppressed when already in a worktree. Soft-nudge — never blocks.

**Lifecycle at `/complete`:** when current task is on a worktree, prompts 3 paths (default 3 — skip):
1. Merge back to main + remove worktree
2. Push branch + open PR (worktree stays)
3. Skip — leave as-is

Merge-conflict path 1 aborts merge, prints conflict files, leaves worktree intact for manual resolution.

**`project_state.md` field:** `**Worktree By Default:** true` opts the project into worktree-always for `/implement`. Absent → false.

**Conventions:** `references/worktree-conventions.md` v1.2 documents directory priority (`.worktrees/` > `worktrees/` > CLAUDE.md > ask), branch naming (`feature/<task>`), gitignore requirement, signal taxonomy, lifecycle paths, DDEV concerns, refusal cases, and (§11) how the command relates to Claude Code's native `--worktree` support.

**Reuses:** `superpowers:using-git-worktrees` skill's core patterns (directory priority, gitignore verify, auto-detect setup); extends with task-aware lifecycle + Drupal/DDEV awareness. Not a hard dependency; replicated in command body.

## Playbook System (v3.15.0+)

Two-layer Drupal best-practices system:

- **Published playbook sets** — namespaced dev-guides categories like `drupal/best-practices/camoa/*`. Each guide is one concrete "do it this way, not that way" rule. Multiple authors can ship parallel sets (`drupal/best-practices/<author>/*`); users subscribe per project.
- **Project-local user playbook** — single markdown file the user maintains. Can OVERRIDE shipped opinions (replace) or EXTEND them (cover topics shipped doesn't). Local always wins on conflict.

**`project_state.md` fields** (v3.15.0+):
- `**Playbook Sets:** drupal/best-practices/camoa, ...` (comma-list) OR `none` (explicit opt-out) OR absent (uses the plugin's `defaults.json` `playbookSets`)
- `**User Playbook:** /abs/path/to/playbook.md` paired with `**User Playbook State:** unset | docs-only-no-playbook | set`
- `**Playbook Resolutions:**` — multi-line list recording per-topic multi-set contradiction choices

**Default voice:** the plugin ships `defaults.json` with `playbookSets: ["drupal/best-practices/camoa"]` — opinionation by default. Forks of the plugin edit `defaults.json` to ship a different default. (This lived in `plugin.json` `defaults.playbookSets` through v4.5.0; moved to `defaults.json` in v4.6.0 because non-standard manifest keys trip `claude plugin validate`.)

**Precedence at decision time:** project-local > active opinion-set(s) > generic dev-guides.

**Conflict surface:** `guide-integrator` v5.0.0+ cross-references plays-by-topic at load time. Local-vs-shipped contradictions emit one-line surfaces (precedence rule applies, no prompt) and persist to `.claude/playbook-conflicts.log`. Multi-set contradictions prompt the user once and persist the choice in `**Playbook Resolutions:**`.

**Maintenance commands** (all user-initiated, framework-drafted, user-approved with diff preview):
- `/playbook-capture` — append a new play; framework drafts entry, shows diff
- `/playbook-review` — walk plays one-at-a-time with `[k/u/r/q]`; immediate-write semantics
- `/playbook-active` — read-only display of subscribed sets, local playbook, recent conflicts
- `/set-playbook-sets` — set/clear active sets; validates each via dev-guides-navigator
- `/set-user-playbook` — set/clear local playbook path; 3-state semantics

**`/complete` candidate-play surface:** at task completion, `analysis-agent` `play_candidates` mode (v1.1+) analyzes task artifacts + `git diff` for repeated decisions worth capturing. Per-candidate `[y]/[n]/[d]` prompt; `[y]` hands off to `/playbook-capture`. `--no-play-candidates` opt-out.

**Schemas:** `references/playbook-schema.md` v1.0 (recommended local playbook structure), `references/playbook-conflict-schema.md` v1.0 (JSONL log line), `references/analysis-agent-schema.md` v1.1 (adds `play_candidates` mode, additive/backward-compatible).

### Validation Team Mode (v3.14.0+)

`/validate:team` is a **sibling** to `/validate:all` — NOT a replacement. It runs the 7 v3.13.0 gates in **isolated Claude Code agent teams** (4 teammates) so each gate is assessed in a fresh context window free of the main session's prior reasoning. Primary driver: **honest validation** (no self-review bias). Secondary benefits: context-window economy, parallel code-gate throughput.

**4-teammate roster:**
- `validator-code-1` (sonnet, worktree) — owns `tdd`, `solid`
- `validator-code-2` (sonnet, worktree) — owns `dry`, `security`
- `validator-docs` (haiku, worktree) — owns `guides`
- `validator-visual` (sonnet, none) — owns `visual-regression` (fanned out per `<component>/<viewport>`)

`validate-visual-parity` is NOT in the roster (deferred to v2 Set B5 — inherits `/validate:all`'s `<reference>`-arg limitation).

**Manifest contract** (per `references/team-manifest-schema.md` v1.0): lead writes `<task>/validations/tmp/team-manifest.json` before spawn. All paths absolute; `visual_fanout[]` present only on visual gates; write-once; teammates treat it read-only.

**Fallback chain:**
1. `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS != "1"` → auto-run `/validate:all` (unless `--no-fallback`)
2. `TeamCreate` fails → same fallback
3. Team already resident in session → REFUSE with cleanup guidance (do NOT auto-cleanup)

**Envelope compatibility:** per-gate envelopes stay at v3.13.0 v1.0 unchanged. Aggregate `_all.json` adds only a `source: "validate:team"` marker — same shape `/validate:all` produces.

**When to use:** pre-PR / pre-merge / pre-release honest-validation moments, long conversations where context economy matters. Prefer `/validate:all` for routine use.

## Alignment Step (v3.12.0+)

Optional scope contract authored before Phase 1 via `/scope <task>`. Produces `alignment.md` with H2 sections (`## Task-Level`, `## Phase 1 — Research`, `## Phase 2 — Architecture`, `## Phase 3 — Implementation`), each carrying the same 4-field shape: Goal / Expected result / Success criteria / Non-goals. See `references/alignment-contract.md` for grammar v1.0.

**When warranted:** analysis-agent emits `scope_contract_recommended` signal when the task has conjunctive phrasing, ≥2 distinct outcome dimensions, or (folder mode) ≥3 acceptance criteria plus description > 60 words. Warranted tasks get a soft-nudge prompt in `/research`, `/design`, `/implement`. User always retains the option to skip — never blocks.

**Conversation convention:** one question at a time, author-authored, never auto-generated. Claude MAY propose a draft, but the user's reply is the final text. Follows superpowers `brainstorming` precedent.

**Task-level retrofit (v3.12.2 in `/research`, v3.13.1 in `/design` + `/implement`):** at every phase entry, commands invoke `alignment-reader` first; if `sections.task_level.present: false`, soft-prompt the user to author task-level scope inline (2-minute conversation) before the phase-level offer. Skippable, single-shot per command invocation, never blocking. Discoverability for users who didn't know `/scope` exists.

**Reader:** `alignment-reader` skill (haiku, user-invocable: false) parses `alignment.md` into structured JSON via `scripts/alignment-read.sh`. Defensive — never throws; emits `warnings[]` on malformed sections. Mirrors `project-state-reader` (v3.11.0) and `task-frontmatter-reader` (v3.10.0).

## Agents
- Frontmatter must include: name, description, capabilities, version, model
- Description starts with "Use when..." for auto-delegation
- Read-only agents must have `disallowedTools: Edit, Write`
- Agents that learn across sessions should have `memory: project`

## Skills
- Frontmatter must include: name, description, version
- Add `model:` matched to complexity (haiku for lookup, sonnet for balanced, opus for complex)
- Internal-only skills must have `user-invocable: false`
- Body uses imperative voice — instructions for Claude, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` for discoverability
- Restrict `allowed-tools` to minimum needed

## Reading Strategy (v4.2.0+)

D-A-D phases (Research → Architecture → Design) are **Type B** work — audit / review / architecture analysis. Read full source and config files; do NOT grep-first. Inherited methods, annotations, config-wired classes, and docblock metadata are invisible to a grep-first pass. See `https://camoa.github.io/dev-guides/development/reading-strategy/` via `dev-guides-navigator`. Cited inline in `commands/research.md`, `commands/design.md`, `commands/implement.md`, `commands/review.md`.

## Effort-Adaptive Commands (v4.8.0+)

Command and skill bodies may use the `${CLAUDE_EFFORT}` string substitution — Claude Code replaces it with the session's active effort level (`low` / `medium` / `high` / `xhigh` / `max`) when the command runs. Use it to scale *depth*, not correctness: an effort-adaptive command does less corroboration at `low` and more at `xhigh`, but never skips a gate or a required step.

**Convention for adding effort-adaptivity:**
- Insert `${CLAUDE_EFFORT}`-conditional language **only at genuine depth decision points** — every line is recurring tokens, so do not narrate effort handling throughout the body.
- Gates, audits, and non-bypassable steps run **regardless of effort**. Effort scales discretionary depth (how many sources to corroborate, how many alternatives to enumerate), never enforcement.
- Pilot first, broaden later. `commands/research.md` Step 6 is the **v4.8.0 pilot** (research depth). Broaden to `/design`, `/review`, and the component/pattern skills only after the pilot has been observed in real use.

## Forked Subagents (v4.2.0+, experimental upstream)

Claude Code 2.1.117+ ships forked subagents (`CLAUDE_CODE_FORK_SUBAGENT=1`) — context-inheriting parallel work. Relevant to `/propose-epics` bulk review and parallel sub-task investigation where shared loaded context (research, dev-guides, playbook) avoids re-establishment cost. **Not enabled by default** — `/validate:team`'s honest-validation guarantee deliberately wants fresh context. See `references/forked-subagents.md` for the framework's evaluation criteria.

## Troubleshooting

Symptom-first triage at `references/troubleshooting.md`. For Claude Code platform-level issues (CLAUDE.md ignored, hooks not firing, MCP not connecting, plugin not loaded), the upstream `Debug Your Config` guide is the authoritative reference — uses `/context`, `/memory`, `/doctor`, `/hooks`, `/mcp`, `/skills`, `/permissions`, `/status` to inspect what actually loaded.

## Online Dev-Guides — Proactive Usage
**ALWAYS consult dev-guides before making Drupal development decisions** unless the relevant guide was already loaded in this session.
- Use the `dev-guides-navigator` skill for topic discovery, caching, and disambiguation
- Do NOT fetch `llms.txt` or dev-guides URLs directly — invoke the navigator skill instead
- The `guide-integrator` and `guide-loader` skills delegate to the navigator
- **Phase 1 (Research):** Load guides for the task's Drupal domain (forms, entities, plugins, etc.)
- **Phase 2 (Design):** Load guides for architecture decisions (services, routing, caching, config)
- **Phase 3 (Implementation):** Load guides for security, SDC, JS patterns before writing code
- If a guide was loaded earlier in the session, do not re-fetch — use the cached content

## Recurring Checks with /loop

Users can poll deploy status or run periodic checks during long sessions:

```
/loop 5m check if drush cr finished and the site is responding on https://mysite.ddev.site
/loop 2m check if the config import completed
/loop 10m /drupal-dev-framework:status
```

Session-scoped — stops when session exits. 3-day auto-expiry.

## Condition-checked autonomy with `/goal` (v4.9.0+)

`/loop` re-runs a prompt on a time interval; `/goal` re-runs the session **until a condition holds**. After each turn a small fast model checks the condition against what the transcript shows and either starts another turn or clears the goal. It fits framework phases with a verifiable end state.

- `/review` writes `_review.json` and per-gate envelopes — a goal like `/goal every hard-block gate in <task>/validations/latest reports pass` runs review-fix loops unattended.
- `/validate:all` (7 gates) is similar — `/goal every gate in the validation summary reports pass or skipped`.
- The evaluator judges only what is **already in the transcript** — it does not run tools or read files. The command must surface gate results inline (both `/review` and `/validate:all` do). Each `/goal` turn bills tokens; keep conditions measurable and bound them (`… or stop after 20 turns`).

Long `/review`, `/research-team`, and `/validate:team` runs can also be dispatched as **background sessions** — `claude --bg "<prompt>"`, `/background` (alias `/bg`) from inside a session, or from Agent View (`claude agents`). A background session keeps running with no terminal attached. This composes with the `channelsEnabled` push-notification tip: background-run + ping-on-done.

## Sandbox and DDEV

If users enable Claude Code sandboxing (`/sandbox`), DDEV commands will fail because Docker socket access is restricted. Required configuration:

```json
{
  "sandbox": {
    "excludedCommands": ["ddev"],
    "filesystem": {
      "allowWrite": ["~/.ddev", "/tmp"]
    }
  }
}
```

`ddev` must be in `excludedCommands` (not `allowWrite`) because it uses the Docker socket which sandboxing blocks at the network level.

## Path-Specific Rules for Drupal Projects

Recommend users create `.claude/rules/` files scoped to file types for Drupal-specific conventions:

- `drupal-php.md` with `paths: ["*.php", "*.module", "*.install"]` — PHP coding standards, service injection, hook naming
- `drupal-twig.md` with `paths: ["*.twig", "*.html.twig"]` — Twig coding standards, accessibility, escaping
- `drupal-scss.md` with `paths: ["*.scss"]` — BEM, Bootstrap usage, mobile-first

These load only when Claude works on matching files, keeping context lean.

## Security & auto-mode posture (v4.9.0+)

**`--dangerously-skip-permissions`.** The framework writes to `.claude/` constantly — `session_context.json`, the `_*.json` gate audits, task folders under `.claude/projects/`. Running Claude Code with `--dangerously-skip-permissions` removes the permission prompts on `.claude/`, `.git/`, and `.vscode/` writes that are the safety net for the framework's own state files. Use it only in throwaway or sandboxed environments, never on a production-adjacent checkout.

**`autoMode.hard_deny` and project settings.** Since Claude Code v2.1.142, a project's `.claude/settings.json` (or `.claude/settings.local.json`) **cannot** set `defaultMode: "auto"` — it is silently ignored, so a repository cannot grant itself auto mode. Auto mode is enabled only from the user's own `~/.claude/settings.json`. A project may still ship an `autoMode.hard_deny` array (unconditional denials — e.g. `core/`, `vendor/`, `web/sites/default/settings.php`, `.ddev/`); that list applies as a guardrail **if** the user has turned auto mode on, but it cannot itself turn auto mode on.

## Documentation & observability notes (v4.9.0+)

**Upstream doc links.** When referencing Claude Code documentation, link the specific current page — `/en/permission-modes`, `/en/worktrees`, `/en/sub-agents` — not the former `/en/common-workflows` hub, which was pruned. Direct per-topic links are stable; the hub is gone.

**OTel skill metrics.** The framework does not ship OpenTelemetry instrumentation. If it ever does, note that `claude_code.skill_activated` carries an `invocation_trigger` attribute distinguishing `user-slash` from `claude-proactive` and `nested-skill` — useful for measuring how often framework commands are user-invoked versus auto-triggered. Recorded here as a future-instrumentation footnote.

## ATK E2E Gate (v4.12.0+)

`/setup-atk` installs **ATK `^2.0` (behavioral) + Playwright** and scaffolds `tests/e2e/`.
`/validate:e2e` runs the gate and emits `_e2e.json` + the standard validation envelope.

Key conventions:
- ATK canned tests live in `tests/e2e/behavioral/atk/` as a **copy** — never modify in-place. Use `--update-atk` after ATK contrib updates.
- Journey specs (`tests/e2e/specs/<slug>.md`) are the reviewable artifact; `<slug>.spec.ts` is regenerable from them.
- `testIdAttribute: 'data-qa-id'` must remain in the `e2e-chromium` project `use:` block in `playwright.config.ts` after any config edit — ATK's injected attributes rely on it.
- `<!-- visual-review:dispatch-ready -->` in `commands/validate-e2e.md` is what makes `/review`'s dispatcher invoke this gate. Never remove it.
- ATK's VR mode is NOT used — Task C (Lullabot) owns visual regression.
- `/validate:a11y` and `/validate:perf` are v2-deferred.

## Visual Regression Gate (v4.13.0+)

`/setup-visual-regression` installs **`@lullabot/playwright-drupal` + Playwright**
and scaffolds `tests/visual/`. `/validate:visual-regression` runs the gate and
emits `_visual_regression.json` + the standard validation envelope. Task C of the
`visual_and_e2e_review_gates` epic — an **evolve** of the v3.13.0 gate.

Key conventions:
- **Screenshot store is codePath-native.** Baselines are committed Playwright
  snapshots at `<codePath>/tests/visual/<surface>.spec.ts-snapshots/`; `.meta.json`
  provenance sidecars travel in-tree. The v3.13.0 `.screenshots/` memory-project
  store is retired (migration source only). Resolved in Task C `research.md` Q1
  (fork option **(b+)**).
- **Generated specs name the test exactly `'visual regression'`.** That fixes
  Playwright's snapshot ordinal at `-1-` so baseline filenames are deterministic.
  Renaming the test orphans every committed baseline — see `tests/visual/README.md`.
- **No baseline write without an explicit `[y]`.** `baseline-manager.sh` runs in
  plan mode first (prints the surfaces it would capture, writes nothing); the
  command shows the plan + `[y]/[n]`; only `--confirmed` runs `--update-snapshots`.
  Every regeneration is logged to `baseline-history.jsonl`.
- **Missing baseline = loud `fail`** with a `--bootstrap` remediation message —
  never a silent auto-create.
- **`<!-- visual-review:dispatch-ready -->`** in `commands/validate-visual-regression.md`
  is what makes `/review`'s dispatcher invoke this gate. Never remove it.
- **Registry shared with `/setup-atk`** at `<codePath>/.visual-review/registry.yml`;
  one `playwright.config.ts` carries both `e2e-*` and `visual-chromium-*` projects.
  Setup is idempotent + order-independent.
- a11y baseline pairing is **warning-only** in v1 (per-surface `a11y_block: true`
  is a v2 candidate).

## General
- Current state only — no historical narratives
- Replace outdated content, don't keep alongside new
- Every edit is a chance to prune irrelevant content
- Reference files instead of reproducing content
