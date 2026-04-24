# Drupal Dev Framework - Plugin Conventions

## Task Hierarchy (v3.10.0+)

The plugin supports **opt-in epic/sub-task hierarchy** on top of flat tasks (which remain first-class). Concepts:

- **Flat task** — default. No frontmatter needed. Behaves exactly as v3.0.0+.
- **Epic** — a task folder containing `task.md`, `shared/`, `in_progress/<subtasks>/`, and `completed/<subtasks>/`. Declared via `task.md` frontmatter (`kind: epic`, `children: [local:<id>, ...]`).
- **Sub-epic** — a subtask that is itself an epic (second and final nesting level; no sub-sub-epics).
- **Subtask** — a task nested inside an epic's `in_progress/` (while active) or `completed/` (when done). Completion never removes a subtask from its parent epic.

**Key commands:**
- **`/drupal-dev-framework:migrate-to-epic <task>`** — convert a flat task into an epic. Manual, per-task, transactional. Supports `--dry-run` and `--children "a,b,c"`.
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

**7 gates + 1 orchestrator:**
- `validate-tdd` / `validate-solid` / `validate-dry` / `validate-security` — thin wrappers over `code-quality-tools` skills; add task context + persistence + shared envelope
- `validate-guides` — framework-owned; verifies `research.md` + `architecture.md` cite `dev-guides-navigator` guides
- `validate-visual-regression <component> <viewport>` — captures via Playwright MCP, diffs via `odiff`/`pixelmatch`, prompts regression/intentional/cancel on diff. Intentional approval rotates baseline inline (no deferred approval in v1)
- `validate-visual-parity <component> <viewport> <reference>` — compares against design comp (PNG/JPG, Figma URL via MCP, HTML file headless-rendered). React/PSD/Sketch deferred to v2
- `validate-all` — sequential orchestrator; non-interactive CI mode skips visual gates

**Shared result envelope** (per `references/validation-gate-result.md` v1.0): every gate emits `{schema_version, gate, task, run_at, verdict, details, messages}`. Verdicts: `pass | warning | fail | skipped`. Persisted to `<task>/validations/latest/<gate>.json` (overwrite) + `<task>/validations/history.jsonl` (append).

**Screenshot store** (per `references/screenshot-store-schema.md` v1.0) at `<memory_project>/.screenshots/<component>/<viewport>.{png,meta.json}`. 9-field `.meta.json` with `role`, `captured_by` enum, `prior_hash` chain, `source` for parity refs. 1-deep `.previous` history.

**Soft-nudge posture:** `fail` signals but never blocks; visual diffs require explicit user classification; `/validate:all` CI mode explicitly skips prompts rather than silent-defaulting.

**Hard dependency:** `code-quality-tools` (v3.0.0+) added to `plugin.json`. Second hard dep alongside `dev-guides-navigator`.

**NOT wrapped** (keep invoking directly via `/code-quality:*` namespace): `lint`, `coverage`, `review`, `audit`, `ultrareview`, `architecture-debate`, `security-debate`. `/validate:all` surfaces them as discoverability hint.

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

## General
- Current state only — no historical narratives
- Replace outdated content, don't keep alongside new
- Every edit is a chance to prune irrelevant content
- Reference files instead of reproducing content
