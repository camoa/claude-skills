# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.2.4] - 2026-04-27

### Skill visibility hygiene (Tier 1 of multi-plugin command-naming research)

User-reported: typing `/implement` surfaces both `/drupal-dev-framework:implement` AND the skill `drupal-dev-framework:implementation-task-creator` in the typeahead, because the skill defaults `user-invocable: true` and substring-matches.

Per the research at `/tmp/command-naming-research.md`, plugin namespacing makes true identifier collisions impossible; the issue is purely typeahead substring matching. Fix per `Comprehensive Guide Skills in Claude Code.md` line 197 + 290 + 496: set `user-invocable: false` on internal skills. Hides them from the `/` menu without blocking parent-command Skill-tool invocation.

### Changed

Set `user-invocable: false` on 9 internal skills (frontmatter additions only — no renames, no behavior change, no version-frontmatter dependencies):

- `skills/implementation-task-creator/SKILL.md` — called from `/implement`
- `skills/code-pattern-checker/SKILL.md` — pre-commit helper
- `skills/component-designer/SKILL.md` — called from `/design`
- `skills/requirements-gatherer/SKILL.md` — called from `/new`
- `skills/task-completer/SKILL.md` — called from `/complete`
- `skills/task-folder-migrator/SKILL.md` — called from `/migrate-tasks`
- `skills/tdd-companion/SKILL.md` — inline Phase 3 helper
- `skills/diagram-generator/SKILL.md` — internal architecture viz
- `skills/session-resume/SKILL.md` — `/next` is the public face

These skills remain fully accessible to parent commands via the `Skill` tool — `user-invocable: false` controls menu visibility only (per docs line 290 + 496).

### Skills already correctly hidden (no change needed)

`alignment-reader`, `core-pattern-finder`, `epic-migrator`, `guide-integrator`, `guide-loader`, `memory-manager`, `phase-detector`, `project-initializer`, `project-state-reader`, `screenshot-store-reader`, `session-context-writer`, `task-context-loader`, `task-frontmatter-reader`.

## [4.2.3] - 2026-04-27

### Discoverability fixes (rolls v4.2.2 + new scope-offer for brand-new tasks)

Two complementary discoverability fixes shipped together. v4.2.2 was prepared in this branch but never released as a tag; v4.2.3 supersedes it.

### Fix 1 — Relocate playbook nudge to `project-initializer` (single source of truth)

v4.2.1 added the playbook-config nudge in two caller-layer surfaces — `commands/next.md` (any session) and `commands/new.md` (post-creation) — but missed `skills/project-initializer/SKILL.md` Step 10, the actual final-handoff for `/new`. Putting the nudge in the lowest layer makes it the single source of truth: every caller of `project-initializer` gets it for free, no duplication.

- **`skills/project-initializer/SKILL.md` Step 10** — split into Step 10(a) Playbook-config nudge + Step 10(b) Final handoff. Step 10(a) is the canonical surface; explicit instruction: "Do NOT duplicate this text in caller commands."
- **`commands/new.md` "After Creation" Step 2** — simplified to a one-line pointer at `project-initializer` Step 10(a). Removes two-place drift risk.
- **`commands/next.md` "Playbook-config nudge" section** — unchanged. `/next` covers the orthogonal not-just-created case.

### Fix 2 — Scope offer for brand-new tasks (`/next` discoverability gap)

User-reported: `/next` did not offer `/scope` when a user named a brand-new task. The existing v3.12.0+ alignment-retrofit suggestion only fired when `task.md` already existed — for brand-new tasks (highest-value moment for `/scope`), it was silently skipped.

- **`commands/next.md` "Scope offer for brand-new tasks" section (NEW)** — when user names a NEW task in the Step 2 "User Names New Task" path, surfaces a one-line `[y]/[n]` offer to run `/scope <task>` first. Default `[n]` per v3.12.0+ soft-nudge contract — never blocks, never forces (the alignment system is optional by design; many tasks legitimately don't need a scope contract).
- **`commands/next.md` "Alignment retrofit suggestion" section** — clarified to only cover EXISTING tasks (the orthogonal case to the new-task offer above).

**Why not force `/scope`?** The v3.12.0 alignment system is explicitly soft-nudge ("never blocks", "skippable"). Forcing would break the contract every existing task relies on, and many tasks don't need a scope contract. Discoverability is the right primitive here, not enforcement.

### Coverage by entry point

| Entry point | Surfaces playbook nudge? | Surfaces `/scope` offer? |
|---|---|---|
| `/new` (fresh project creation) | yes — `project-initializer` Step 10(a) | n/a (no task yet) |
| `/next` "User Names New Task" (brand-new task) | n/a (project nudge already fired earlier) | **yes — v4.2.3 (this release)** |
| `/next` "Tasks in Progress" (existing task without alignment.md) | n/a | yes — v3.12.0+ alignment retrofit |
| `/next` (any session, any project, playbook implicit/unset) | yes — `commands/next.md` Playbook-config nudge | n/a |
| `/upgrade-project` (retrofit existing project) | yes — v4.1.0 | n/a (project-level, not task-level) |
| `/research`, `/design`, `/implement` (phase entry) | n/a | yes — task-level alignment retrofit (v3.12.2 / v3.13.1) |

## [4.2.1] - 2026-04-27

### Playbook configuration discoverability

User-reported gap: `/new` does not configure playbook by design (it's deliberately decoupled from `/set-playbook-sets` / `/set-user-playbook`), but the post-creation handoff jumped straight to "create your first task" without surfacing the option to configure playbook first. Fix lands the nudge in two complementary surfaces so it's visible "everywhere" — not just at project creation.

### Added

- **`commands/next.md` "Playbook-config nudge" section.** After resolving the project (Step 1), `/next` now invokes `project-state-reader` and inspects the `playbook` block. When `playbook_sets_source: "default"` (Playbook Sets line absent — implicit inheritance from `plugin.json` defaults) **OR** `user_playbook_state: "unset"`, prints a one-line soft-nudge before the task-selection prompt suggesting `/set-playbook-sets`, `/set-user-playbook`, or `/upgrade-project`. Skipped silently when both fields are explicit. Never blocks. Mirrors the existing v3.12.0+ alignment-retrofit pattern.
- **`commands/new.md` "After Creation" Step 2 — playbook-config nudge.** After `requirements-gatherer` finishes, before printing the "next: `/next`" hint, prints a one-line suggestion to run `/set-playbook-sets` and `/set-user-playbook` before the first task. Notes that `/next` will re-surface the nudge if the user skips it.

### Verified

- `/upgrade-project` already retrofits playbook fields (Step 2 detects `playbook_sets_source: "default"` and `user_playbook_state: "unset"` as gaps; Step 4 invokes `/set-playbook-sets` and `/set-user-playbook` to fix them). No code change needed in the upgrader.

### Coverage by entry point

| Entry point | Surfaces playbook nudge when implicit/unset? |
|---|---|
| `/new` (fresh project creation) | yes — v4.2.1 (this release) |
| `/next` (any session, any project) | yes — v4.2.1 (this release) |
| `/upgrade-project` (retrofit existing project) | yes — v4.1.0 (already shipped) |

## [4.2.0] - 2026-04-27

### 2026-04-25 doc-refresh deltas

Closes the 2026-04-25 Claude Code doc-refresh deltas affecting this plugin (snapshot pinned at upstream commit `c142d14`, covers Claude Code releases 2.1.116–2.1.119). Additive throughout — no behavior change to existing gates or commands.

### Added

- `references/forked-subagents.md` — documents experimental forked subagents (`CLAUDE_CODE_FORK_SUBAGENT=1`, Claude Code 2.1.117+), evaluation criteria for adopting in `/propose-epics` and parallel sub-task investigation, why v4.2.0 keeps `/validate:team`'s honest-validation guarantee on fresh-context spawns instead of forks.
- `references/troubleshooting.md` — symptom-first framework triage table + cross-link to upstream `Debug Your Config` for Claude Code platform-level issues (`/context`, `/memory`, `/doctor`, `/hooks`, `/mcp`, `/skills`, `/permissions`, `/status`).
- Reading-strategy callouts in `commands/research.md`, `commands/design.md`, `commands/implement.md`, `commands/review.md` — explicit Type-B (full-read, no grep-first) discipline, citing `https://camoa.github.io/dev-guides/development/reading-strategy/` via `dev-guides-navigator`.
- `commands/validate-playbook-adherence.md` "Future hardening" section — `UserPromptExpansion` hook (Claude Code 2.1.118+) as a v2 candidate for platform-layer adherence enforcement at slash-command-expansion time.
- `PostToolBatch` future-avenue note (batch-summary aggregation) intentionally NOT inlined into `commands/review.md` — pattern is documented in detail in `code-quality-tools/skills/code-quality-audit/references/post-batch-aggregation.md` and cross-linked in `code-paper-test/commands/test-team.md`. Avoiding compound blockquotes in review.md preserves the one-liner consistency across phase commands.
- CLAUDE.md gains `## Reading Strategy (v4.2.0+)`, `## Forked Subagents (v4.2.0+, experimental upstream)`, and `## Troubleshooting` sections.

### Changed

- Body line counts after additive callouts: research 73, design 48, implement 69, review 116, validate-playbook-adherence 89 — all within v4.0.2 budgets (research ≤100, design ≤80, implement ≤120, review ≤120, adherence ≤100).

### Audit results — `--agent` frontmatter hooks behavior fix (Claude Code 2.1.117+)

Re-audited all 6 frontmatter agents for inline `hooks` and `mcpServers` declarations. The upstream fix makes frontmatter hooks fire in `--agent` (main-session) mode — previously they did not. Result:

- `analysis-agent`, `architecture-drafter`, `contrib-researcher`, `pattern-recommender`, `project-orchestrator` — **no inline hooks or mcpServers**. Fix is **additive benefit only** for these 5 agents.
- `architecture-validator` — **HAS** a `PreToolUse` hook matching `Write|Edit` that returns `block` (enforces the agent's read-only design). The fix making this hook fire in `--agent` mode is **also additive benefit** — the read-only enforcement is desired in main-session mode, not a regression. No code change required.

**Conclusion:** no agent depends on hooks NOT firing in `--agent` mode. Behavior fix is purely additive across the agent surface; no `--agent` invocation pattern needs to be revised.

### Out of scope (deferred to a later cycle)

- OTEL span instrumentation for framework-emitted spans — no framework surface currently emits OTEL.
- Routine templates (nightly audit, PR auto-review, release verification) — defer to v4.3.0 once the v4.1.0 epic pattern stabilizes further.
- Plugin Dependencies declaration on `dev-guides-navigator` — already declared at the `plugin.json` level (`dependencies: ["dev-guides-navigator", "code-quality-tools"]`); deeper dependency-constraints work deferred.
- Linux package manager install docs — host-installation guidance lives in `dev-guides-navigator`/upstream, not this plugin.

## [4.1.0] - 2026-04-26

### Phase 4 review + adherence gates + retrofit + closing pass

`dev_framework_review_phase_and_adherence` epic completes (4 subtasks shipped: review_phase_command, adherence_gates, retrofit_tools, plumbing_docs_tests). Driver: `feedback_framework_phase_gates.md` memo — gates exist but Claude treats them as a menu rather than mandatory. v4.1.0 extends the v4.0.0 5-mechanism hardening pattern to pre-PR validation + adherence checking + retrofit of old artifacts.

### Added

- `commands/review.md` (114/120 body lines) — Phase 4 orchestrator between `/implement` and PR creation. Runs `/validate:all` (default) or `/validate:team` (`--team`), plus the new adherence gates as hard-blocks. Flags: `--dry-run`, `--rerun-failed`, `--no-pr-body`, `--skip-<gate> <reason>`, `--allow-dirty`. Writes `_review.json` audit + `PR_BODY.md` on green. Inline literal templates for `review-gate-fail` + `review-summary` (rationalization-resistance).
- `commands/validate-playbook-adherence.md` (85/100 body lines) — heuristic cite-checker for loaded plays. Literal-string match (Grep `-F`) per match-type to avoid regex injection. Section-aware skip (`Rejected` / `Considered Alternatives` / `Out of Scope` headings) blocks gaming. Defensive on missing/malformed `_playbook-load.json`.
- `commands/upgrade-project.md` (114/120 body lines) — single retrofit command. Two passes: project-state field backfill (delegates to `/set-*` commands) + iterates in-progress tasks for task-level gaps via `--rerun-loaders`. Active-project-only. Journal-backed atomic batch with `--resume`. Symlink rejection. Bounded `$PWD` walk-up. Charset validation.
- `references/review-phase-walkthrough.md` (174 lines) — full prose for `/review`.
- `references/upgrade-walkthrough.md` (200 lines) — full prose for `/upgrade-project`.
- `references/gate-hardening-prompts.md` v1.1 → v1.2 — additive bump adds `review-gate-fail` + `review-summary` templates byte-identical to inline literals.
- `tests/gate-prompts-vs-inline.sh` — cross-file byte-equivalence between v1.2 templates and inline literals in `commands/review.md`.
- `tests/review-command-spec.sh`, `tests/validate-playbook-adherence-spec.sh`, `tests/upgrade-project-spec.sh`, `tests/project-state-read-spec.sh` — invariant + RCE-regression test harnesses.
- CLAUDE.md `## Review Phase (v4.1.0+)` + `## Retrofit Tools (v4.1.0+)` sections.

### Changed

- `commands/complete.md` slimmed (11→9 steps; 61→59 body lines). Removed Steps 3-5 (gates moved to `/review`). New Step 3 honors `**Review Required:**` field for legacy posture.
- `commands/validate-guides.md` extended to dual-mode — `<!-- /review:hard-block -->` HTML capability marker + `--hard-block` / `--strict` argv flags promote `warning` → `fail`. Standalone soft-nudge behavior preserved.
- `references/gate-audit-schema.md` v1.0 → v1.1 — adds `review` gate_type (§5.8 payload). v4.1.0 also documents additive optional flags `gate_specific.retrofitted` + `gate_specific.replaced_corrupt` + `gate_specific.grandfathered` (no version bump; additive optional fields per §7 versioning policy).
- `scripts/gate-audit-write.sh` — accepts `gate_type: "review"` and `schema_version: "1.1"`.
- `scripts/project-state-read.sh` — broader case-sensitivity audit: char-class header pattern applied to all 6 fields for case-insensitive header match without relying on awk's `IGNORECASE` (gawk-specific). Added `parse_bool()` shared bash function (DRY) used for both `Worktree By Default` + `Review Required`. New `**Review Required:**` field parsed; `reviewRequired: bool | null` added to emitted JSON.
- `scripts/command-body-lengths.sh` — adds `review` budget (120); 5/5 phase commands within budget.
- `scripts/fm-helpers.sh` `write_stub_task_md` + `references/research-walkthrough.md` task scaffold — Phase 4 line included by default.
- `agents/*.md` (6 files) — added explicit `tools:` allowlist (resolves pre-existing `/plugin-creation-tools:validate` finding).

### Fixed

- **🔒 SECURITY (RCE)**: `scripts/project-state-read.sh:125` — replaced `eval echo "$CODE_PATH_RAW"` with bash parameter expansion `${CODE_PATH_RAW/#\~/$HOME}`. Pre-existing since v3.11.0 — adversarial `**Code path:** $(rm -rf ~)` would execute on every script invocation. Paper-test team caught + this PR fixes. Smoke-tested: `$(touch /tmp/RCE-MARKER)` payload no longer executes.

### Honest caveats

- v4.1.0 is **broad-but-shallow**: many small focused changes across docs/tests/scripts. Each subtask paper-test-reviewed pre-merge (3 PRs caught + fixed: review_phase_command 12 blockers; adherence_gates 14 blockers; retrofit_tools 21 blockers including the RCE).
- The 5-mechanism v4.0.0 pattern was designed for **deterministic** gates. Adherence gates introduce **content-semantic interpretation** (heuristic cite-checking has inherent gaming surface). Section-aware skip mitigates the most obvious vector; defense-in-depth (LLM-grading citations) is a v2 candidate.
- `homepage` field absent on `plugin.json` + `marketplace.json` (optional spec field) — deferred to a separate metadata-polish PR.
- `--all` bulk mode for `/upgrade-project` across registry — explicit non-goal; v2 candidate.

## [4.0.2] - 2026-04-25

### Token efficiency — 3 plugin-level cuts (additive; no contract change)

After v4.0.0 hardened gates shipped, post-release meta-analysis surfaced ~80K tokens/session of avoidable runtime cost. v4.0.2 ships three independent additive cuts.

#### Cut 1 — Phase command body split

`commands/research.md`, `design.md`, `implement.md`, `complete.md` were reloaded into context on every Skill invocation. Bodies compressed from 455/358/384/268 lines to 76/51/72/66 lines (1465 → 265 total, ~82% reduction). Tutorial-depth content moved to new `references/<phase>-walkthrough.md` files (loaded only when explicitly read; no hook or skill auto-loads).

- Added `scripts/command-body-lengths.sh` — enforces runtime budgets (research ≤100, design ≤80, implement ≤120, complete ≤100). Exits non-zero on overrun. `--json` mode for CI.
- Added `references/research-walkthrough.md`, `references/design-walkthrough.md`, `references/implement-walkthrough.md`, `references/complete-walkthrough.md` (full prose preserved verbatim from v4.0.1 command bodies).

#### Cut 2 — Conditional UserPromptSubmit hook output

`hooks/context-reminder.sh` and `hooks/loaded-context-summary.sh` now md5-hash their rendered output, cache it under `~/.claude/drupal-dev-framework/sessions/<workspace_hash>.last-<hook>.md5`, and emit empty `{}` envelopes when state is unchanged turn-over-turn. Cache invalidates automatically on any state change (task.md edits, loadedGuides[] growth, project_state.md edits, active task switch). Cache write failures degrade silently to "always emit" — hooks remain best-effort.

- New env var `DDF_HOOK_DEBUG=1` emits `<hook>: skipped (state unchanged)` / `<hook>: emit (state changed)` to stderr for verification.
- Added `scripts/hook-cache-status.sh` — prints current cached hashes per hook for the active workspace.

#### Cut 3 — gate-hardening-prompts.md v1.0 → v1.1

Compressed presentation-only scaffolding (per-template intro paragraphs, repeated default annotations) into a single Templates index table at the top of the file. **Every literal block (the bytes inside ``` fences under each `## Template ID:` heading) preserved byte-for-byte from v1.0** — the rationalization-resistance contract is the literal-text guarantee, not the surrounding prose.

- `pre-analysis-decision` template stays at 28 lines (3 conditional outcome blocks are essential to the contract — explicitly preserved per architecture decision).
- 4 of 5 templates ≤12 lines each.
- Added `tests/gate-prompts-literal.sh` — extracts each template's literal block from baseline (`main:references/gate-hardening-prompts.md`) and current file; cmp-diffs them; fails on any byte difference. Catches accidental literal drift in future PRs.

### Files added

- `references/research-walkthrough.md`
- `references/design-walkthrough.md`
- `references/implement-walkthrough.md`
- `references/complete-walkthrough.md`
- `scripts/command-body-lengths.sh`
- `scripts/hook-cache-status.sh`
- `tests/gate-prompts-literal.sh`

### Files modified

- `commands/{research,design,implement,complete}.md` — runtime bodies compressed
- `hooks/context-reminder.sh` — md5-cache + DDF_HOOK_DEBUG instrumentation
- `hooks/loaded-context-summary.sh` — same pattern
- `references/gate-hardening-prompts.md` — v1.0 → v1.1 (additive)
- `.claude-plugin/plugin.json` — version 4.0.1 → 4.0.2

### No behavior change

All v4.0.0 hardened gates still fire and produce identical audit output. Skip flags unchanged. Bypass-reason capture unchanged. No grandfathering rules change.

## [4.0.1] - 2026-04-25

### Fixed — 4 documentation drift bugs surfaced by post-epic plugin-creation-tools validation

After `dev_framework_improvements_epic` completed (2026-04-25), running the full plugin-creation-tools validation suite (plugin-structure-auditor + skill-quality-reviewer + /plugin-creation-tools:validate) cumulatively across the v3.9.0 → v4.0.0 arc surfaced 4 epic-level drift bugs. Each is a doc/description that fell out of sync as releases shipped through the epic but the corresponding stale text was missed.

1. **`README.md` line 263** — `Current version: **3.10.0**` was stale since v3.11.0 shipped. Updated to **4.0.1**.
2. **`marketplace.json` plugin description** stopped at v3.14.0; missed v3.15.0 / v3.16.0 / v4.0.0 summary clauses. Extended to cover all three releases plus the `recommended: plugin-creation-tools` hint added in v4.0.0.
3. **`skills/guide-integrator/SKILL.md`** v5.1.0 description said "delegates to dev-guides-navigator" without mentioning v4.0.0's deterministic detection (`scripts/dev-guides-detect.sh`). Updated to lead with the deterministic-detection mechanism.
4. **`agents/analysis-agent.md`** v1.1.0 description said "Invoked by /research pre-analysis hook at new-task creation" without the v4.0.0 always-on qualifier; also omitted `play_candidates` mode (v1.1.0+) entirely. Updated to enumerate all 3 modes (folder / description / play_candidates) with their v3.x → v4.0.0 evolution noted.

### Added — `GETTING_STARTED.md`

Tight 5-minute walkthrough for new users. Covers install → first project → first task → 3-phase walkthrough → returning to work + common situations (status, epic migration, playbooks, worktrees). README's terse "Quick Start" section is for users who already know the workflow; `GETTING_STARTED.md` is for users who don't. README now opens with a prominent banner pointing to it.

### Pre-existing tech debt NOT fixed in v4.0.1

These predate the epic and are out of scope for this patch:
- 7 skills missing `model:` frontmatter field (predate v3.10.0; framework still works without explicit model — falls back to inherit)
- `guide-loader` description vague (predates this epic)
- `plugin-creation-tools/README.md` missing (different plugin)
- marketplace.json `owner.email` empty string

### Why patch, not minor

All 4 fixes are documentation drift — agent + skill + reference descriptions catching up to behavior that already shipped. No contract change, no feature change, no behavior change. Patch per versioning policy.

## [4.0.0] - 2026-04-24

### ⚠️ BREAKING CHANGES

v4.0.0 converts 7 framework surfaces from soft-prompt to hard-gate. Users on the soft posture will experience a behavior change:

- **Pre-analysis epic gate** at `/research` is now **always-on** — invokes `analysis-agent` regardless of whether strong signals fire. Previously: signal-conditional. Bypass via `--skip-pre-analysis [reason]` flag.
- **Coverage-mapping requirement** in research.md is now **enforced** — `## Coverage Mapping` H2 mandatory; refuses Phase 1 `[x]` on fail. Previously: optional traceability walkthrough only. Bypass via `--skip-coverage-check [reason]`.
- **`skill-quality-reviewer`** (from plugin-creation-tools) is **invoked at `/complete`** when staged/branched changes include `skills/*/SKILL.md`. Previously: never invoked automatically. Bypass via `--skip-skill-review [reason]`.
- **`/plugin-creation-tools:validate`** is **invoked at `/complete`** when staged/branched changes include any plugin file. Previously: never invoked automatically. Bypass via `--skip-plugin-validate [reason]`.
- **Phase-command-bypass** detected via PreToolUse hook on Write to phase artifacts. Direct Write to `research.md` / `architecture.md` / `implementation.md` without an active phase command writes a non-blocking audit. Previously: silent.
- **Dev-guides preflight** uses **deterministic detection** (`scripts/dev-guides-detect.sh`) instead of agent-mediated keyword matching. Eliminates bypass-by-declaration ("agent claimed loaded but didn't").
- **Playbook loading** uses **deterministic load** (`scripts/playbook-load-deterministic.sh`) for the same reason.

### Grandfathering

v3.x in-flight tasks (those past Phase 1 at v4.0.0 install) keep their original soft contract. Heuristic: `research.md present && _pre-analysis.json absent` → grandfathered. New tasks created after v4.0.0 install get the hardened gates.

### Added — 5-mechanism pattern (uniform across all 7 surfaces)

From the original critique in `dev_framework_gate_hardening` task.md:

1. **Anti-bypass clause** — literal block in command body listing rationalization patterns NOT valid as skip reasons
2. **Show-not-summarize** — verbatim agent output before user prompt
3. **Audit on disk** — `<task>/_<gate>.json` per fired gate
4. **Mandate exact prompt wording** — literal templates from `references/gate-hardening-prompts.md` v1.0
5. **Refactor "if X, do Y" → "validation gate, always evaluated"** — the if-condition is what the gate DOES, not whether it RUNS

### Added — 5 deferred surfaces (NOT hardened in v4.0.0)

Tracked in `dev_framework_improvements_epic/shared/v2-candidates.md` Set D with "documented bypass causing harm" promotion trigger:

- Phase transition checks (no documented incident)
- Playbook conflict acknowledgment (already minimal one-liner)
- Worktree recommendation (medium-medium tie; false-positive cost real)
- `/complete` candidate-play surface (auto-extract rejected on hallucination grounds)
- `/validate:*` exit codes (deliberate v3.13.0 soft-nudge design)

### New files (10)

**References (2):**
- `references/gate-audit-schema.md` v1.0 — unified schema for 7 audit file types
- `references/gate-hardening-prompts.md` v1.0 — literal mandated wording for 5 user-prompt surfaces

**Scripts (5):**
- `scripts/gate-audit-write.sh` — atomic JSON-validated audit writer
- `scripts/coverage-mapping-check.sh` — deterministic `## Coverage Mapping` check
- `scripts/dev-guides-detect.sh` — deterministic auto-load keyword detection
- `scripts/playbook-load-deterministic.sh` — deterministic playbook load
- `scripts/phase-command-bypass-detect.sh` — PreToolUse hook helper

**Hooks (2):**
- `hooks/phase-command-bypass.sh` — PreToolUse hook on Write
- `hooks/loaded-context-summary.sh` — UserPromptSubmit hook

**Commands (1):**
- `commands/audit-status.md` — read-only audit-state view

### Updated files (10)

- `commands/research.md` — pre-analysis always-on + coverage-mapping check + deterministic dev-guides preflight
- `commands/design.md` — deterministic dev-guides preflight
- `commands/implement.md` — deterministic dev-guides preflight
- `commands/complete.md` — skill-review + plugin-validate gates
- `commands/status.md` — Unaudited gates section
- `skills/guide-integrator` v5.0.0 → 5.1.0 — delegates to deterministic scripts
- `agents/analysis-agent` v1.0.0 → 1.1.0 — documents always-on invocation pattern
- `.claude-plugin/plugin.json` — `3.16.0` → `4.0.0`; new `recommended: ["plugin-creation-tools"]`; new `"hardening"` keyword; 2 new hooks registered (PreToolUse Write matcher + UserPromptSubmit second hook)
- `CLAUDE.md` — new `## Hardened Gates (v4.0.0+)` section before Worktree Workflow
- `README.md` — `/audit-status` row in commands table; Tech Refs 9 → 11 (adds gate-audit-schema + gate-hardening-prompts)

### Why major

The contract change is real: users who relied on agent-judgment-based gate skipping (e.g., "I'm sure this task is flat, signals don't apply") have that path removed. They must use explicit `--skip-*` flags now. That's a breaking change for users on the soft posture per semver.

### Philosophy

Hardening earns its place when (a) there's documented evidence of bypass causing harm (not "in theory"), (b) the bypass mechanism is rationalization-prone (the AI talks itself out of running it), and (c) the hardening cost is smaller than the bypass cost. v4.0.0 ships hardening for 7 surfaces that pass all three filters; defers 5 surfaces that don't.

## [3.16.0] - 2026-04-24

### Added — Worktree Awareness

Make git worktrees the standard mechanism for running parallel tasks on the same drupal-dev-framework project. Two Claude Code sessions on the same workspace collide on `~/.claude/drupal-dev-framework/sessions/<md5($PWD)>.json` and on the git working tree itself; a worktree at `.worktrees/<task_name>/` solves both — distinct `$PWD` → distinct hash → independent session. **No changes to `session-context-writer`.**

### New commands (2)

- `/drupal-dev-framework:worktree <task>` — 10-step creation: resolve task, refuse-if-in-worktree, directory priority (`.worktrees/` > `worktrees/` > CLAUDE.md > ask), gitignore verify + commit if missing, DDEV `name:` warning (Drupal-specific), `git worktree add` with `feature/<task>` branch, auto-detect setup (`composer install` / `npm install`), optional `--with-baseline`, pre-seed session-context, summary
- `/drupal-dev-framework:worktree-prune` — per-worktree `[y]/[n]/[q]` cleanup; lists state (branch merged? task completed?); honors git's refusal on uncommitted changes; force-remove requires explicit per-worktree confirmation

### New reference (1)

- `references/worktree-conventions.md` v1.0 — directory priority, branch naming, gitignore requirement, detection signal taxonomy (HIGH/MEDIUM-HIGH), 3-path lifecycle at `/complete`, DDEV compatibility, refusal cases, versioning policy

### New scripts (2)

- `scripts/worktree-detect.sh` — defensive in-worktree state check (uses `git rev-parse --git-dir` vs `--git-common-dir` difference); emits `{schema_version, in_git_repo, in_worktree, worktree_path, main_path, branch, warnings}`
- `scripts/worktree-signals.sh` — computes detection signals for `/implement`: `another_task_active` (commits to other tasks' files within 2 hours), `dirty_tree` (uncommitted changes), `multi_session` (2+ session-context files for same project), `project_opt_in` (`Worktree By Default: true`); resolves codePath via `project-state-read.sh`; HIGH threshold: at least one HIGH signal or EXPLICIT user/project flag

### `project_state.md` schema addition

- `**Worktree By Default:** true` — opts project into worktree-always for `/implement` (otherwise signal-driven)

### Updated artifacts

- `commands/implement.md` — new "Worktree recommendation" pre-step BEFORE Phase Transition Check; soft-nudge with `[c]reate / [m]ain tree / [a]bort`; `--worktree` flag chains into `/worktree`; `--in-main-tree` flag suppresses
- `commands/complete.md` — new "Worktree merge prompt" sub-step BETWEEN quality gates and candidate-play surface; 3-path (merge-back / push+PR / skip); default skip; merge-conflict path 1 aborts merge + leaves worktree for manual resolution
- `scripts/project-state-read.sh` — parse new `Worktree By Default` field; emit `worktreeByDefault: bool`
- `skills/project-state-reader` v1.1.0 → 1.2.0 — documents new field
- `.claude-plugin/plugin.json` — `3.15.0` → `3.16.0`; new `worktree` keyword
- `CLAUDE.md` — new `## Worktree Workflow (v3.16.0+)` section before Playbook System block
- `README.md` — 2 new commands; Technical Contract References 8 → 9

### Detection signals (HIGH-strength)

| Signal | Evidence |
|---|---|
| `another_task_active` | Another task folder has `implementation.md` AND `git log --since="2 hours" --name-only` shows commits to its tracked files |
| `dirty_tree` | `git status --porcelain` shows modified files matching another task's tracked files |
| `multi_session` | (MEDIUM-HIGH) 2+ session-context files in `~/.claude/drupal-dev-framework/sessions/` reference the same project |
| `--worktree` user flag | EXPLICIT |
| `Worktree By Default: true` in `project_state.md` | EXPLICIT |

Recommendation fires only on HIGH or EXPLICIT signals; suppressed when already in a worktree; printed only on `/implement` (not `/research` or `/design` — read-mostly phases).

### DDEV compatibility

DDEV explicitly supports worktrees ([DDEV Contributor Training, March 2026](https://ddev.com/blog/git-worktree-contributor-training/)) but requires the `name:` key removed from `.ddev/config.yaml`. Framework detects + warns; **never auto-edits** the config. User picks `[c]ontinue / [a]bort / [s]how-instructions`.

### Why minor, not major

Purely additive. Existing `/implement` works unchanged when no signals fire. Existing `/complete` works unchanged outside worktrees. `session-context-writer` and all `/validate:*` commands consumed unchanged. v3.15.0 Playbook System orthogonal — no integration needed.

### Reused vs extended

Reused: `superpowers:using-git-worktrees` core patterns (directory priority, gitignore verify, auto-detect setup). Replicated in command body — not a hard dependency.

Extended with: task-aware lifecycle (`/implement` recommendation, `/complete` merge prompt), Drupal/DDEV awareness, session-context pre-seed, conservative HIGH-only signal threshold (false positives are worse than false negatives).

### Deferred to v2

- Configurable detection-window beyond 2 hours
- Detection signals on `/research` and `/design`
- `/migrate-to-worktree` for in-flight tasks
- Refined heuristics from real-world false-positive reports
- Multi-task worktree reuse (single worktree, multiple tasks)
- Auto-edit `.ddev/config.yaml` (with backup + commit)
- Test-baseline runs default-on for Drupal projects
- Distributed / cross-machine worktree-equivalent

## [3.15.0] - 2026-04-24

### Added — Playbook System

Two-layer Drupal best-practices system: shipped playbook sets (namespaced dev-guides categories) + per-project local user playbook. **Opinionation by default** — `plugin.json` ships `defaults.playbookSets: ["drupal/best-practices/camoa"]`. Local playbook can OVERRIDE shipped opinions or EXTEND them with topics shipped doesn't cover; local always wins on conflict.

The camoa playbook is **already published** at `https://camoa.github.io/dev-guides/drupal/best-practices/camoa/` (20 guides as of 2026-04-24). v3.15.0 ships the framework integration over the existing content.

### New commands (5)

- `/drupal-dev-framework:set-playbook-sets` — set/clear active sets; validates each via `dev-guides-navigator`. Accepts comma-list, literal `none`, or `default` (revert to plugin default).
- `/drupal-dev-framework:set-user-playbook` — set/clear local playbook path; 3-state field (`unset` / `docs-only-no-playbook` / `set <path>`); explicit / `--docs-only` / interactive detect-and-confirm modes.
- `/drupal-dev-framework:playbook-capture` — interactive draft + diff preview + append. User is the deterministic approval gate.
- `/drupal-dev-framework:playbook-review` — per-play `[k]eep / [u]pdate / [r]emove / [q]uit` walk; immediate-write semantics; quit preserves committed work; `/loop`-able.
- `/drupal-dev-framework:playbook-active` — read-only display of subscribed sets, local playbook, recent conflicts.

### New references (2 + 1 schema bump)

- `references/playbook-schema.md` v1.0 — recommended local playbook structure (H3-per-play with What/Rationale/When/Example), freeform fallback contract, defensive parser invariants
- `references/playbook-conflict-schema.md` v1.0 — JSONL log line for `.claude/playbook-conflicts.log`; local-vs-shipped + multi-set-contradiction types
- `references/analysis-agent-schema.md` v1.0 → v1.1 — adds `play_candidates` mode used by `/complete` candidate-play surface; existing `folder` and `description` modes unchanged (backward-compatible — additive only)

### New scripts (2)

- `scripts/playbook-read.sh` — defensive markdown parser; never throws; emits warnings on malformed plays; handles freeform fallback
- `scripts/playbook-conflicts-write.sh` — atomic JSONL append with schema-version + required-field validation

### `project_state.md` schema additions

- `**Playbook Sets:** <comma-list>` OR `none` OR absent (defaults from plugin.json)
- `**User Playbook:** <abs path>` paired with `**User Playbook State:** unset | docs-only-no-playbook | set`
- `**Playbook Resolutions:**` — multi-line list recording per-topic multi-set contradiction choices

### Updated artifacts

- `skills/guide-integrator` v4.1.1 → 5.0.0 — loads playbook sets via `dev-guides-navigator` + local playbook via `playbook-read.sh`; cross-references plays-by-topic; emits `loaded_playbook_sets[]`, `loaded_local_playbook`, `conflicts[]`; surfaces conflicts once per session per topic with persistence.
- `skills/project-state-reader` v1.0.0 → 1.1.0 — parses new fields; falls back to plugin.json `defaults.playbookSets` when `Playbook Sets` field absent; emits `playbookSetsSource: explicit | explicit-none | default`.
- `scripts/project-state-read.sh` — extended with new field parsing + plugin.json default resolution.
- `commands/research.md`, `design.md`, `implement.md` — dev-guides preflight Step 1 documents v3.15.0 guide-integrator behavior (loads playbook layers, surfaces conflicts).
- `commands/complete.md` — new "Candidate-play surface" section between pre-completion checks and task move; invokes `analysis-agent` `play_candidates` mode; per-candidate `[y]/[n]/[d]` prompt; `--no-play-candidates` opt-out; skipped when `userPlaybookState != "set"`.
- `hooks/context-reminder.sh` (UserPromptSubmit) — emits `Playbook: <sets> + <local>` line below Project line when at least one of `playbookSets` or `userPlaybook` is configured. Silent otherwise.
- `.claude-plugin/plugin.json` — `3.14.2` → `3.15.0`; new top-level `defaults.playbookSets` field; new `playbook` keyword.
- `README.md` — 5 new commands in commands table; Technical Contract References 6 → 8.
- `CLAUDE.md` — new `## Playbook System (v3.15.0+)` section before Validation Team Mode block.

### Precedence rule

When the same topic is addressed by multiple layers:

1. Project-local playbook (always wins when present)
2. Active opinion-set(s) (winner determined by `**Playbook Resolutions:**` if multi-set; else `null` and prompt user)
3. Generic dev-guides (lowest precedence)

### Conflict handling

- **Local-vs-shipped:** precedence rule applies silently; one-line surface once per session per topic; persisted to `.claude/playbook-conflicts.log`.
- **Multi-set contradiction:** framework refuses silent pick; prompts user (`[1]/[2]/cancel`); persists choice in `**Playbook Resolutions:**` for future sessions.
- **Local extending (no contradiction):** loads silently; no conflict event.

### Why minor, not major

Purely additive. No breaking changes:

- Existing commands (`/research`, `/design`, `/implement`, `/complete`, `/validate:*`) work unchanged when no playbook is configured.
- Existing skills (`alignment-reader`, `task-frontmatter-reader`, etc.) consumed unchanged.
- `analysis-agent` v1.0 outputs unchanged for existing modes; new `play_candidates` mode is opt-in via explicit `mode` parameter.
- `project_state.md` parsing is forward-compatible: projects without the new fields just get default behavior.
- `dev-guides-navigator` plugin and `code-quality-tools` consumed unchanged.

### Default voice (political note)

`plugin.json` ships `defaults.playbookSets: ["drupal/best-practices/camoa"]`. Forks of the plugin (alternative opinion-curators) override this field to ship a different default. The choice is documented as a deliberate decision, not implicit.

### Deferred to v2

- `/validate:playbook` adherence gate — pattern adherence requires agentic judgment; needs machine-readable playbook format first
- Global `~/.claude/rules/playbook.md` surface — not needed (dev-guides serves this via subscription); CC Issue #21858 (`globs:` ignored at user-level) is irrelevant to the design
- Determinism measurement / before-after eval — anecdotal user judgment is the only signal in v3.15.0
- Multi-set contradiction silent resolution beyond per-topic prompt
- Migration tooling for existing patterns docs in non-standard locations

## [3.14.2] - 2026-04-24

### Fixed — `/validate:guides` applicability auto-skip for non-Drupal tasks

Surfaced by the v3.14.0 dog-food run on `dev_framework_isolated_validators`: `/validate:guides` returned `fail` because neither `research.md` nor `architecture.md` cited a dev-guides-navigator guide. But the task is non-Drupal plugin-framework work (agent-teams orchestration), so guide citations weren't expected — the dev-guides catalog covers Drupal/Next.js/frontend, not this domain. The verdict was technically correct against the rule but a false positive against intent.

The v1 gate's "Why this gate exists" prose already acknowledged the limitation: *"Not relevant for trivial config changes, test-only tasks, or documentation-only work. v1 has no auto-skip; user decides when to invoke."* That worked when humans invoked the gate manually but breaks when `/validate:all` or `/validate:team` invokes it autonomously.

**Fix:** new Step 2 "Applicability check" in `validate-guides.md`. Before inspecting phase artifacts:

- If `codePathState` is `docs-only` or `unset` → emit `verdict: "skipped"` with reason
- If `codePathState == "set"` → quick-scan codePath for domain markers:
  - **Drupal:** `*.info.yml`, `*.module`, `composer.json` containing `"drupal/core"`, or `*.theme` directory
  - **Next.js:** `package.json` with `"next"` dep, or `next.config.{js,ts,mjs}`
  - **Frontend/CSS:** `*.scss`, `*.css`, `tailwind.config.*`, or `package.json` with `"react"`/`"vue"`/`"svelte"`
- At least one marker → applicable; continue to citation check
- No markers → emit `verdict: "skipped"` with reason

Detection is shallow (top-level + 1-deep) and intentionally generous. False positives (running citation check on a marginally-Drupal task) are cheaper than false negatives.

`details.applicability` field added to the envelope so consumers can see what fired:

```json
"applicability": {
  "decision": "applicable | skipped",
  "reason": "<one-line explanation>",
  "markers_found": ["drupal", "frontend"]
}
```

### Files changed

- `commands/validate-guides.md` — new Step 2 (applicability check); Steps 3-8 renumbered; envelope details adds `applicability` field; verdict-messages section adds skipped-applicability example; "Why this gate exists" prose updated to describe the auto-skip
- `.claude-plugin/plugin.json` — `3.14.1` → `3.14.2`
- root `marketplace.json` — plugin version + `metadata.version` `1.14.20` → `1.14.21`

### Not changed

- Envelope schema v1.0 (just adds an optional `details.applicability` sub-field; existing consumers ignore it)
- Citation-extraction logic (Step 4) and verdict rules (Step 5) — both unchanged
- `/validate:team` command body — `/validate:guides` semantics shifted underneath, but the team-mode wrapper is agnostic to per-gate verdict logic

### Why patch, not minor

Bug fix for a false-positive verdict surfaced by the v3.14.0 dog-food. No new behavior the user explicitly opts into — the auto-skip kicks in transparently. Existing Drupal tasks see no change (markers match, citation check runs as before). Patch per versioning policy.

### Re-dog-food on this fix

`/validate:team dev_framework_isolated_validators` is expected to now return `skipped` for the `guides` gate (codePath is `/home/camoa/workspace/claude_memory/marketplaces/camoa-skills` — Claude Code plugin marketplace, no Drupal/Next.js/frontend markers).

## [3.14.1] - 2026-04-24

### Fixed — Two `/validate:team` doc gaps surfaced by post-merge goal review

Reviewing the v3.14.0 PR against the task's original pain points + alignment success criteria surfaced two documentation gaps the paper-test didn't catch. Both are documentation-level; no contract change.

**1. Worktree-creation-failure fallback.** Architecture §15 Risk #4 specified that if a teammate's worktree creation fails, the lead should retry that teammate with `isolation: "none"` and print a warning. This behavior was in architecture but missing from the command body's error-cases table. Added to `validate-team.md` with explicit warning string format and a note that absolute-path writes reach the lead regardless of isolation mode.

**2. Visual teammate mailbox fan-out contract.** v3.14.0's Step 6 specified one mailbox line per gate — but the visual teammate fans out over N × (`<component>`, `<viewport>`) pairs. The command didn't say whether it emits per-component lines, one aggregate line, or both. Clarified: the visual teammate emits **both** — per-component progress lines in format `"visual-regression:<component>/<viewport> complete, verdict: <verdict>"`, then one aggregate line `"visual-regression complete, verdict: <worst-verdict>"` matching the format other teammates use. Spawn prompt contract updated to specify this explicitly.

### Files changed

- `commands/validate-team.md` — Step 5 spawn prompt adds visual-specific fan-out mailbox contract; Step 6 adds "Visual teammate fan-out" paragraph; error-cases table adds worktree-creation-failure row
- `.claude-plugin/plugin.json` — `3.14.0` → `3.14.1`
- root `.claude-plugin/marketplace.json` — plugin entry `3.14.0` → `3.14.1` + `metadata.version` `1.14.19` → `1.14.20`

### Not changed

- `team-manifest-schema.md` — manifest contract is unchanged (both gaps are command-body / spawn-prompt concerns, not manifest fields)
- Envelope schema
- Roster, fallback chain, or any other v3.14.0 contract

### Why patch, not minor

Both changes are additive documentation clarifications of previously-undefined behavior. No consumer could have relied on the prior (silent) behavior for either case — v3.14.0 shipped less than 24 hours ago with zero recorded runs. Patch bump per the versioning policy.

## [3.14.0] - 2026-04-24

### Added — `/validate:team` command for isolated validation

New `/drupal-dev-framework:validate-team` command runs the 7 v3.13.0 `/validate:*` gates in **independent Claude Code agent-team sessions** so each gate is assessed by a fresh context free of the main session's prior reasoning. Primary driver: **honest validation** — the validator cannot be anchored on what the main session just built. Secondary benefits: context-window economy, parallel throughput for code gates.

**Sibling to `/validate:all`, not a replacement.** Users on machines without `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` keep using `/validate:all` with no downgrade path. `/validate:team` automatically falls back to `/validate:all` when the experimental flag is unset, when `TeamCreate` fails, or when a team is already resident in the session (cleanup required in that last case — command refuses rather than auto-cleans).

**4-teammate roster:**

| Teammate | Gates | Model | Isolation |
|---|---|---|---|
| `validator-code-1` | `tdd`, `solid` | sonnet | worktree |
| `validator-code-2` | `dry`, `security` | sonnet | worktree |
| `validator-docs` | `guides` | haiku | worktree |
| `validator-visual` | `visual-regression` (fanned out) | sonnet | none |

`validate-visual-parity` is NOT in the roster — inherits `/validate:all`'s limitation requiring an explicit `<reference>` arg. Users who need parity run `/drupal-dev-framework:validate-visual-parity` manually.

### Added — `team-manifest-schema.md` v1.0

Canonical schema for `team-manifest.json` — the minimum-context package the lead writes before spawn. Lives at `<task>/validations/tmp/team-manifest.json`, written once, read by teammates, deleted by lead at cleanup.

Key invariants:
- All paths absolute (teammates in worktrees can't resolve relatives back to main)
- `visual_fanout[]` present only on visual-regression gate entries (omitted, not empty, for code gates)
- `gates[]` non-empty
- `assigned_to` is a suggestion — file-lock task claiming (agent-teams runtime) decides actual ownership
- Write-once; teammates treat it read-only; mid-run state flows through envelopes + mailbox

### Fallback behavior

Automatic and silent-of-failure:
- Env var unset → print fallback message + auto-run `/validate:all`
- `TeamCreate` fails → same fallback
- `--no-fallback` flag → refuse rather than fall back (for CI users who want team-or-nothing)

User never has to re-invoke manually.

### Files changed

**New files:**
- `commands/validate-team.md` — lead-side orchestration (Steps 1-9: resolve task, detect availability, read context, write manifest, spawn 4 teammates, stream progress, aggregate, cleanup, persist)
- `references/team-manifest-schema.md` — canonical `team-manifest.json` v1.0 spec (13 sections covering shape, field contracts, invariants, absolute-path rationale, lifecycle, versioning)

**Updated files:**
- `.claude-plugin/plugin.json` — `3.13.5` → `3.14.0`
- `README.md` — commands table gains `/validate:team` row; Technical Contract References 5 → 6; CLI-version note acknowledges agent-teams v2.1.32+
- `CLAUDE.md` — new `## Validation Team Mode (v3.14.0+)` sub-section in Validation Gates block
- root `.claude-plugin/marketplace.json` — plugin entry version `3.13.5` → `3.14.0` + `metadata.version` patch `1.14.18` → `1.14.19`

### Not changed

- Validation envelope schema (`references/validation-gate-result.md` v1.0) — teammates write the same shape v3.13.0 gates produce; aggregate adds only a `source: "validate:team"` marker
- Screenshot store schema (`references/screenshot-store-schema.md` v1.0)
- Skills: `alignment-reader`, `screenshot-store-reader`, `project-state-reader`, `task-frontmatter-reader` — all consumed unchanged
- `/validate:*` per-gate commands — siblings; `/validate:team` invokes them by running their flows in spawned teammate sessions
- `/validate:all` — strictly unchanged; `/validate:team` is a sibling orchestrator

### Deferred to v2

- Set B1 — parallel visual gate execution (blocked on A2 deferred visual approvals)
- Set B2 — `TaskCompleted` hook for streaming per-gate results
- Set B3 — `--json` output mode on `/validate:team` itself
- Set B4 — `/validate:team --cleanup` subcommand for crash recovery
- Set B5 — `validate-visual-parity` in team mode (inherits `/validate:all`'s `<reference>`-arg limitation)

All five tracked at epic level in `dev_framework_improvements_epic/shared/v2-candidates.md` Set B.

### Dependency note

Hard dependencies unchanged: `dev-guides-navigator`, `code-quality-tools` (both present since v3.13.0). Runtime dependency on Claude Code CLI v2.1.32+ (agent-teams minimum) is a soft requirement — gracefully degrades to `/validate:all` when teams are unavailable.

### Philosophy

Ship the honest-validation primitive with a narrow, provable contract. Defer every optimization and every ergonomic until real pain surfaces. Dog-food on self before calling it done — v3.14.0 merges only after `/validate:team dev_framework_isolated_validators` returns `pass` on `/validate:guides` from a fresh session.

## [3.13.5] - 2026-04-24

### Added — Post-phase epic check in `/research`, `/design`, `/implement`

Pre-analysis hook (v3.11.0+) decides epic-vs-flat **before** task creation based on very thin signals — just the task name + sometimes a short user description. In practice this fires a false-negative often: the real scope only emerges after `/scope` authors `alignment.md`, after research surfaces sub-problems, and after architecture commits to a component breakdown. By the time the task is obviously epic-shaped, the framework has no mechanism to surface the offer — v3.12.2's alignment retrofit in `/research` checks for `scope_contract_recommended` but explicitly ignores `epic_candidate`.

Concrete live example: a 4-area Drupal homepage redesign (Video + Trending + Trust Bar + Footer) created via `/next` → "Create new task" → `/research` flow. Task name alone didn't fire pre-analysis signals. Alignment conversation revealed 4 clear deliverables. No epic offer ever surfaced. User had to invoke `/propose-epics` or `/migrate-to-epic` manually AFTER-the-fact.

**Fix:** add a **post-phase epic check** step to each of the three phase commands. Runs at end-of-phase, before the traceability walkthrough. Invokes `analysis-agent` in **folder mode** with full-to-date task context:

- `/research` — checks with `task.md` + `alignment.md` + `research.md`
- `/design` — checks with everything above + `architecture.md`
- `/implement` — checks with everything above + `implementation.md`, **BEFORE any code is written** (last safe migration moment)

If `analysis-agent` returns `epic_candidate`, surface a 3-way offer: `[y]es` migrate via `/migrate-to-epic`, `[n]o` keep flat (default), `[d]iscuss` show rationale + `signals_used[]` and re-ask. If `keep_flat` or `insufficient_info`, proceed silently — agent has full context and its judgment is authoritative.

**Design principle:** **research is when epic-vs-flat is actually decidable.** Pre-analysis stays as an early hint for very obvious cases, but the authoritative check moves to each phase boundary. Later checks have strictly more context than earlier ones — if `/design`'s post-check says `epic_candidate` and pre-analysis said `keep_flat`, trust the later call.

**Per-phase framing differences:**

- `/research` post-check — "pre-analysis couldn't see this shape — research is where it became clear"
- `/design` post-check — "the architecture surfaced decomposition that pre-analysis + post-research checks hadn't caught"
- `/implement` post-check — **stronger wording** acknowledging the cost-of-delay: "Once code starts, migrating to an epic is much harder. Worth pausing to decide now."

### Files changed

- `commands/research.md` — new "Post-phase epic check (v3.13.5+)" section after research writes, before traceability walkthrough. "What This Does" list updated (11 steps, new step 9)
- `commands/design.md` — same pattern for Phase 2 context. "What This Does" list updated (10 steps, new step 8)
- `commands/implement.md` — same pattern for Phase 3 context, with explicit BEFORE-CODE-STARTS positioning. "What This Does" list updated (13 steps, new step 11)

### Not changed

- `analysis-agent` — unchanged (already supports folder mode per v3.11.0 `references/analysis-agent-schema.md`; we just invoke it at new times)
- Pre-analysis hook in `/research` — unchanged (still fires pre-task-creation; v3.13.5 adds a complementary post-phase check, doesn't replace pre-analysis)
- `/migrate-to-epic` — unchanged (consumed as-is)
- `/propose-epics` — unchanged (still useful for batch review of tasks that missed all three post-phase checks, e.g. pre-v3.13.5 tasks)

### Philosophy

When a fix has a narrow version (one command) vs a fuller version (all affected surfaces), the fuller version is the right default. The root cause — "epic check uses weak signals and ignores richer post-phase context" — was symmetric across all three phase commands. Shipping to just one would leave the same latent bug on the other two.

## [3.13.4] - 2026-04-24

Two phase-command UX fixes discovered during live use of `/design` on a non-Drupal plugin-framework task. Both bundled here as a single quick-fix release.

### Added — Traceability walkthrough sub-step in `/research`, `/design`, `/implement`

Users had no in-command way to see how the newly-authored `research.md` / `architecture.md` / `implementation.md` addresses the task's research questions + acceptance criteria — they had to read the whole artifact and cross-reference by hand.

**Fix:** after each phase command authors its artifact, offer an opt-in walkthrough that maps acceptance criteria (pulled from `alignment.md` Success criteria, falling back to `task.md` Acceptance Criteria) to the artifact's sections. User picks `[c]ontinue` / `[r]evise` / `[d]iscuss` and can inline-edit or discuss any row.

**Pattern:**
- Step 1: single-line `[y]es / [n]o` opt-in prompt. Default `[n]`.
- Step 2 (on `[y]`): map each criterion → artifact section reference (honest — unaddressed criteria marked `— NOT YET ADDRESSED —`, never invented).
- Step 3: print the table.
- Step 4: 3-way prompt (`[c]` / `[r]` / `[d]`) with inline revise + discuss paths.

**Never blocks.** Opt-in twice (`[n]` in Step 1 or `[c]` in Step 4) always proceeds. No persistence except edits the user approves under `[r]`.

**Per-phase adaptations:**
- `/research` — maps research questions (from `task.md`) AND task-level ACs (from `alignment.md`) to `research.md` sections.
- `/design` — maps task-level ACs to `architecture.md` sections (+ optional `architecture/{component}.md` files).
- `/implement` — maps task-level ACs to `implementation.md` progress status (`[complete]` / `[in-progress]` / `(planned)` / `— NOT YET ADDRESSED —`). Particularly useful mid-flight as a sanity check.

### Added — Dev-guides pre-flight sub-step in `/research`, `/design`, `/implement`

Before v3.13.4, each phase command's "What This Does" list said *"Loads dev-guides via `guide-integrator` (unless already loaded this session)"* — but that was documentation-of-intent, not an explicit directive to Claude to invoke the skill. The skill fired only via proactive-skill-detection, which is unreliable on non-Drupal tasks (plugin framework, docs-only, Claude Code work). Result: live observation on `dev_framework_isolated_validators` showed dev-guides were never consulted, even though applicable methodology guides (TDD, SOLID, DRY, security, quality-gates) and cross-cutting guides (Next.js, design systems, CSS) existed.

**Fix:** new explicit "Dev-guides pre-flight" sub-step runs after Phase Transition Check, BEFORE the alignment sub-step. Two-part structure:

1. **Explicit invocation** of `guide-integrator` (no reliance on proactive detection).
2. **Always-prompt** the user — NEVER silent-skip — with the current auto-loaded set displayed, then `[c]ontinue` / `[a]dd (scan dev-guides-navigator catalog)` / `[n]one (decline all)`.

**Why "never silent-skip":** dev-guides cover material beyond Drupal (methodology, Next.js, design systems, CSS). Even when auto-detection finds N guides, the user may want to `[a]dd` more. When auto-detection finds zero (common on non-Drupal tasks), the user would have had no signal that guides exist. Silent-skip was hiding the catalog.

**Discoverability > compliance.** `[n]` is a first-class choice — users who explicitly don't want guides can decline without guilt. The fix is about surfacing the option, not mandating use.

### Files changed

- `commands/research.md` — new "Dev-guides pre-flight" section (runs after pre-analysis hook, before Phase 1 alignment). New "Traceability walkthrough sub-step" section (runs after `research.md` authoring, before session-context-writer). Both referenced from updated "What This Does" list
- `commands/design.md` — same pair of sections, adapted for Phase 2 context. Updated "What This Does" list
- `commands/implement.md` — same pair of sections, adapted for Phase 3 context (including mid-flight re-invocation note for the walkthrough). Updated "What This Does" list

### Not changed

- `guide-integrator` skill — unchanged (auto-load rules preserved; v3.13.4 just invokes it explicitly and adds the user prompt layer above it)
- `dev-guides-navigator` plugin — unchanged (consumed unchanged by `[a]dd` branch)
- `alignment-reader` skill — unchanged
- Phase-alignment sub-steps (v3.12.0/v3.12.2/v3.13.1 work) — unchanged in logic; dev-guides pre-flight runs just ahead of them

## [3.13.3] - 2026-04-24

### Changed — Alignment-related prompt wording in `/research`, `/design`, `/implement`

v3.12.4 already rewrote alignment prompts in plain language, but live use kept surfacing them as too jargon-heavy: "scope the task," "phase-level scope contract," "what X phase commits to," "deferred to implementation" — all framework vocabulary that assumes the user already understands the alignment system. Users who didn't read the framework docs were unsure whether to say yes.

**Fix:** rewrite all 8 alignment prompts across the three phase commands using a consistent **example-driven** pattern:

- **Lead with the phase action** — "Before I dig into research," "Before I start designing," "Before I start coding"
- **One-sentence question** in the user's vocabulary — no "scope contract," no "phase commits to," no "deferred"
- **Concrete example block** showing the shape of the output (4 fields with placeholder hints), so the user can see what "yes" produces before deciding
- **Option labels with low-friction tails** — `[n]` carries `(can always add this later)` instead of an implied nag

**Prompts rewritten:**

- `commands/research.md`:
  - Pre-analysis task-level nudge (L133)
  - Task-level retrofit prompt (v3.12.2 retrofit check, L150)
  - Phase 1 phase-level offer (L162)
  - Phase 1 lighter-touch re-offer after declined task-level (L165)
- `commands/design.md`:
  - Step 2a task-level retrofit (v3.13.1)
  - Step 2b Phase 2 phase-level offer (v3.12.0)
- `commands/implement.md`:
  - Step 3a task-level retrofit (v3.13.1)
  - Step 3b Phase 3 phase-level offer (v3.12.0)

**No logic changes** — all decision branches, defaults, and option semantics (`[y]` / `[n]` / `[later]` / `[skip]`) are unchanged. Pure UX / plain-language pass.

**No consumer-facing artifact changes** — `alignment.md` schema unchanged; reader output unchanged; `/scope` flow unchanged.

**Why example-driven beats description-driven:** the user can see a 4-line concrete template of what's being offered, decide in seconds whether that's worth 2 minutes of Q&A, and skip it with no ambiguity. Removes the common failure mode where jargon-heavy prompts prompt a clarifying question before the user can even answer.

## [3.13.2] - 2026-04-24

### Fixed — `alignment-reader` reported stub H2 sections as `present: true`

Discovered while running v3.13.1 `/design` against a task with a placeholder `alignment.md` (Task-Level populated; Phase 1/2/3 H2 headers present but only a "to be authored later" stub under each).

**Bug:** `alignment-read.sh` computed `sections.<key>.present` purely from the presence of the H2 heading. A stub like:

```markdown
## Phase 2 — Architecture

_To be authored inline when `/design` is invoked._
```

...parsed as `phase_2.present: true` even though no H3 fields carried content. Downstream, the v3.12.0 phase-alignment sub-step in `/design` (and `/implement`, and `/research`) interprets `present: true` as "scope exists, skip the offer" — so stubbed sections silently suppressed legitimate alignment offers. Exactly the `/design` false-positive path.

**Fix:** tighten the `present` semantics in the reader to require **H2 exists AND at least one field carries non-empty content** (populated prose body, ≥1 task-list criterion, ≥1 non-goal bullet, or fallback prose body). Empty stubs now return `present: false` plus a new `section_empty_stub` warning — surfaced to consumers who want to know the H2 was seen but contained nothing.

Spec updated: `references/alignment-contract.md` §2 (section-presence semantics paragraph) + §6 (warning code table).

**Consumer impact:** `/research` / `/design` / `/implement` now correctly skip-or-offer based on real content. Stub sections no longer silently suppress the phase-level alignment offer. No command-file changes required — the commands already check `present`; they just now get an honest answer.

**Verified against:**
- `dev_framework_isolated_validators/alignment.md` (Task-Level populated, Phase 1/2/3 stubs) → `task_level.present: true`, phase_N `present: false`, 3 `section_empty_stub` warnings
- `completed/dev_framework_granular_validation/alignment.md` (Task-Level only, no phase sections at all) → `task_level.present: true`, no phase warnings (true absence vs stub correctly distinguished)

### Files changed

- `scripts/alignment-read.sh` — `$present_keys` now derived from content-bearing records (`field`, `criterion`, `non_goal`, `criteria_prose`, `non_goals_prose`), not `section_start` alone. New `$empty_stub_keys` derives from the set difference. New `$w_empty_stub` warning stream
- `references/alignment-contract.md` — section-presence semantics paragraph added to §2; new `section_empty_stub` row in §6 warning code table

### Not changed

- `alignment-reader` skill wrapper — unchanged (delegates to the script)
- `commands/research.md`, `commands/design.md`, `commands/implement.md` — no changes needed; fix is isolated to the reader
- Public JSON envelope shape — unchanged (only the semantics of `present` tightened)

## [3.13.1] - 2026-04-24

### Fixed — Task-level alignment retrofit in `/design` and `/implement`

Before v3.13.1, only `/research` offered task-level alignment retrofit (v3.12.2+). `/design` and `/implement` had an explicit `**Note:**` stating "that decision is considered final by the time they reach Phase 2/3 — the task is already underway." In practice that justification didn't hold for two real scenarios:

1. **Phase executed outside the plugin command** — `research.md` authored manually (plan-mode handoff, staged-file rewrite, pre-v3.12.0 tasks). The user never had a chance to be offered task-level alignment because `/research` never ran.
2. **Tasks jumping directly to Phase 2/3** — pre-existing flat tasks where the user reaches `/design` without ever running `/research`.

In both cases, users who don't know the alignment feature exists had no path to discover it at Phase 2 or Phase 3 entry.

**Fix:** `/design` and `/implement` now run the same task-level retrofit branch that `/research` ships — adapted for phase-aware phrasing:

- New **Step 2a** (design) / **Step 3a** (implement) runs BEFORE the existing phase-level scope offer
- Invokes `alignment-reader`. If `sections.task_level.present: false`, soft-prompts the user to author a task-level contract in 2 minutes
- `[y]` → executes the task-level flow from `scope.md` inline, then refreshes `alignment-reader` so the phase-level step sees the new section
- `[n]` / `[skip]` → final for this command invocation, no re-nag
- `sections.task_level.present: true` → skip silently

Deliberately simpler than `/research`'s Phase 1 retrofit: **skips the `analysis-agent` folder-mode warrant check**. By Phase 2/3 the task has concrete `research.md`/`architecture.md` content; re-running the analysis-agent for a warrant signal would be redundant. Offer unconditionally on missing task-level, soft phrasing, skippable — never blocks.

**Phase-level offer flow unchanged** except for one conditional: when the user declines task-level retrofit in Step 2a/3a (i.e., task_level still not present), the phase-level offer is also skipped (no phase-level foundation without task-level, matching existing "otherwise proceed silently" branch).

**Rationale:** discoverability. Task-level alignment is a first-class feature; users who don't know it exists should be **offered** it at every phase entry, not required to already-know-and-invoke `/scope`. Single-shot per command invocation, fully skippable, never blocking. Matches v3.12.0's soft-nudge posture.

### Files changed

- `commands/design.md` — replaced single-step Phase 2 alignment sub-step with Step 2a (task-level retrofit, new) + Step 2b (phase-level offer, existing). Removed `**Note:**` justifying asymmetric behavior
- `commands/implement.md` — same pattern: Step 3a (retrofit) + Step 3b (phase-level). Same `**Note:**` removal

### Not changed

- `commands/research.md` — already had task-level retrofit (v3.12.2+). No change
- `alignment-reader` skill — no change
- `commands/scope.md` — no change (retrofit flows call it inline the same way)
- No version bump to any hard dependency

## [3.13.0] - 2026-04-24

### Added — Granular Validation Commands (sub-task granular_validation of dev-framework improvements epic)

Individual quality-gate commands invokable on demand, plus two new visual gates and an orchestrator. Replaces the all-or-nothing `/complete`-only gating with a per-aspect, per-moment validation surface.

**7 new gate commands + 1 orchestrator:**

- `/drupal-dev-framework:validate-tdd` — wraps `/code-quality:tdd`
- `/drupal-dev-framework:validate-solid` — wraps `/code-quality:solid`
- `/drupal-dev-framework:validate-dry` — wraps `/code-quality:dry`
- `/drupal-dev-framework:validate-security` — wraps `/code-quality:security`
- `/drupal-dev-framework:validate-guides` — **new, framework-owned.** Verifies research.md + architecture.md cite `dev-guides-navigator` guides
- `/drupal-dev-framework:validate-visual-regression` — **new, framework-owned.** Captures screenshot via Playwright MCP (fallback: claude-in-chrome), diffs against stored baseline via `odiff` (fallback: `pixelmatch`), prompts on diff: regression / intentional (baseline rotates inline) / cancel
- `/drupal-dev-framework:validate-visual-parity` — **new, framework-owned.** Same infrastructure; reference is an external design comp (PNG/JPG passthrough, Figma URL via MCP, HTML file rendered headless). v1 explicitly defers React / PSD / Sketch / Adobe XD
- `/drupal-dev-framework:validate-all` — sequential orchestrator. Runs 5 non-visual gates + visual-regression for every stored baseline (collapsing into one `gates[]` entry with worst verdict); visual-parity always skipped (requires explicit reference arg). Aggregate envelope with `summary` counts and discoverability hint pointing to unwrapped `code-quality-tools:*` capabilities (`lint`, `coverage`, `review`, `audit`, `ultrareview`). CI-mode (non-interactive TTY or `$CI` env var) skips visual gates entirely — explicit-skip rather than silent-defaults

Each gate emits a shared JSON envelope (`references/validation-gate-result.md` v1.0, schema_version `"1.0"`) persisted to `<task>/validations/latest/<gate>.json` (overwrite) + `<task>/validations/history.jsonl` (append). Verdict vocabulary: `pass | warning | fail | skipped`.

**Screenshot store — new project-scoped resource.** Located at `<memory_project>/.screenshots/<component>/<viewport>.{png,meta.json}`. Stores regression baselines AND parity references with 9-field `.meta.json` (schema_version, role, viewport, captured_at, sha256, originating_task, captured_by enum, prior_hash, source — populated for parity refs only with `{type, uri}`). 1-deep history via `.previous.png` + `.previous.meta.json` siblings; unconditional drop on next update. Hash integrity checks at every write.

**New skill + scripts:**

- `screenshot-store-reader` (v1.0.0, haiku, user-invocable: false) — defensive wrapper over `scripts/screenshot-store-read.sh`. Mirrors `alignment-reader` / `project-state-reader` / `task-frontmatter-reader` pattern
- `scripts/screenshot-store-read.sh` — inspects store state; 6 warning codes (`store_missing`, `component_missing_meta`, `meta_schema_mismatch`, `hash_mismatch`, `orphan_meta`, `error`); never throws except on IO errors
- `scripts/screenshot-store-write.sh` — `write-baseline` + `write-parity-reference` modes; 6-step atomic rotation with sha256 verification and rollback on failure; input-validation regexes on component names, viewports, enum values

**New references:**

- `references/screenshot-store-schema.md` — canonical `.meta.json` v1.0 + directory layout + rotation rules + 6 warning codes + 3 example metas + versioning policy
- `references/validation-gate-result.md` — shared result envelope v1.0 for all `/validate:*` commands; per-gate `details` shapes (wrappers vs framework-owned vs visual); aggregate envelope spec; 4 full example envelopes

**Plugin dependencies:** `code-quality-tools` added to `.claude-plugin/plugin.json` `dependencies[]`. Now two hard deps (alongside `dev-guides-navigator`). Minimum supported code-quality-tools version: 3.0.0 (runtime preflight in each wrapper).

**`/validate` (existing, unchanged) vs `/validate-*` (new)** — documented disambiguation in `commands/validate.md`. Original `/validate` checks architecture-fit; new `/validate-*` family checks quality gates. Complementary, not conflicting.

### v1 explicit non-goals (v2 candidates documented)

Tracked in the task's `v2-candidates.md`:

- AI-driven gate applicability judgment (auto-skip inapplicable gates)
- Deferred visual-change approvals via `/complete` batch hook (`.candidate` staging)
- Extended `.meta.json` fields (ignore regions, DPR, capture-engine version, etc.)
- Parallel `/validate:all` execution
- Per-component visual coverage manifest for `/validate:all`

### Validated

- Scripts smoke-tested on 7 fixtures (first baseline, rotation, 1-deep enforcement, parity with provenance, 3 input-validation errors). prior_hash chain integrity verified across 3 rotations
- Quick-trace paper test on pattern-validating wrapper (`validate-tdd`) found 3 MAJOR pattern issues BEFORE replication (task-root ambiguity, sibling-command invocation pattern, exit-code semantics) — all fixed before replicating to solid/dry/security
- Structured 3-phase paper test across the cross-artifact integration found 3 MAJOR + 5 MINOR + 3 NIT, no BLOCKERs: sed-replica drift in solid/dry/security (stale "tdd.md" refs), `/validate:all` per-component aggregation rule undefined, `/validate:all` CI-mode handling undefined. All 3 MAJORs + 3 of 5 MINORs applied
- Plugin-structure auditor: 24/30. 2 MAJORs fixed (over-granted `Edit`/`Task` on wrappers tightened; `/validate` vs `/validate-*` disambiguation documented)

## [3.12.4] - 2026-04-24

### Fixed — alignment conversation UX (two gaps)

Surfaced during live use of `/research granular_validation` in the camoa-skills repo: the scope-contract conversation was noisy on existing-content tasks and its sub-step prompts were framework-jargon rather than plain language. Both were pure UX defects in v3.12.0-3.12.3.

**Gap 1 — `/scope` was interrogative, not conversational.** The task-level flow asked 5 rigid prompts ("What is the single-sentence Goal of `<task>`? Start with a verb.") even when `task.md` already had substantive Goal / Acceptance Criteria / Current State content. Users ended up restating what they'd already written.

**Fix:** `/scope` now reads existing context first (task-frontmatter-reader + task.md body + current alignment.md), picks a conversation mode based on what's already there, and starts from reflection rather than interrogation:

| task.md state | Conversation mode |
|---|---|
| Substantive Goal + ACs (≥40 words) | **Reflect-and-refine** — paraphrase what's there, ask if the paraphrase captures the real driver |
| Partial content | **Draft-and-confirm** — propose a draft from available context, ask what's missing or wrong |
| Stub / empty | **Open exploration** — ask openly; multi-sentence answers welcome |

Phase-level (`--phase 1|2|3`) uses the same three modes, scoped to one phase. The 4 fields (Goal / Expected result / Success criteria / Non-goals) are still the output contract — but they surface from conversation, not from a rigid prompt script.

**Gap 2 — phase-alignment sub-step prompts were framework-jargon.** `/research`, `/design`, `/implement` asked "Author the Phase N — <Phase> section of alignment.md now? [y]es / [n]o / [skip]" — which assumes the user reads framework docs and knows what "alignment.md" and "Phase N sections" mean.

**Fix:** all phase-alignment prompts rewritten in plain language that explains what the choice means BEFORE asking:

- `/research` pre-analysis scope nudge: now says "Before diving into research: this task looks scope-heavy (multiple deliverables or complex criteria). Want to pin down the scope first in a short conversation — goal, what success looks like, what's explicitly out of scope — so research doesn't drift?"
- `/research` retrofit-check nudge: now says "This task doesn't have a declared scope yet, and I'm picking up signals that scope might drift during research..."
- `/research` / `/design` / `/implement` phase sub-step prompts: "You've scoped the whole task. Want to also scope just this phase — what research/design/implementation does in this pass — or skip and start?"

No schema, agent, skill, or script changes. Pure command-body rewrites. `commands/scope.md`, `commands/research.md`, `commands/design.md`, `commands/implement.md`. plugin.json 3.12.3 → 3.12.4; marketplace plugin entry synced; metadata 1.14.11 → 1.14.12.

## [3.12.3] - 2026-04-23

### Fixed — `scope_contract_recommended` signal coverage (two gaps)

**Gap 1 — subtask/epic blindness.** `analysis-agent`'s step 1 aborted with `decision: keep_flat` when `kind != flat`, which silently suppressed ALL signal evaluation — including the orthogonal `scope_contract_recommended` signal added in v3.12.0. Net effect: subtasks and epics got no scope-contract nudge from `/research` even when warrant was obvious. Since every subtask of an epic is `kind: subtask`, the feature was effectively blind to the most common hierarchy-aware scope case.

**Fix:** Split step 1 into two independent gates:
- **Decomposition gate** — open only on `kind: flat` + non-completed. Controls `epic_candidate` + `proposed_children[]` emission. Unchanged semantics.
- **Orthogonal-signal gate (new)** — open on ANY non-completed kind. Controls `scope_contract_recommended` (and future orthogonal signals) evaluation.

Non-flat tasks now proceed through steps 2-5 and emit `signals_used[]` including `scope_contract_recommended` when triggers fire. The decision stays `keep_flat` (never `epic_candidate`) for subtasks/epics.

**Gap 2 — thin-content / stub-task circularity.** The three existing `scope_contract_recommended` triggers (a, b, c) all required existing content to fire: outcome dimensions, conjunctive phrasing, or ≥3 ACs + >60 words. Brand-new or stub tasks have none of that — which is exactly the case where a scope contract helps most. The agent returned `insufficient_info` or `keep_flat` with empty signals; no nudge fired.

**Fix:** New trigger (d) — fires on thin content:
- Folder mode: task.md Goal empty/placeholder AND combined body (Goal + AC + description) < 40 words, OR ≤1 AC AND description < 40 words
- Description mode: `task_description_text` < 40 words

Covers brand-new tasks (description-mode pre-analysis hook), stub tasks opened with `/research`, and short-description subtasks created during epic decomposition.

**Combined effect on `/research` UX:** every non-completed task now gets the scope-contract offer when warranted:
- Rich existing task with conjunctive scope → triggers (a), (b), or (c) fire
- Brand-new task or stub → trigger (d) fires
- Subtask of an epic → orthogonal-signal gate opens and any trigger (a-d) fires

No schema bump (additive per v1.x policy). No command/skill/script behavior changes — only `agents/analysis-agent.md` (step 1 gate split + trigger (d) added) and `references/analysis-agent-schema.md` (docs match).

## [3.12.2] - 2026-04-23

### Fixed — `/research` retrofit-aware scope offer

**Bug:** `/research` silently skipped the task-level alignment nudge when invoked on a pre-existing task that never went through the pre-analysis hook (e.g., tasks created before v3.11.0, or tasks that existed when their scope contract was omitted). The feature effectively did nothing for retrofit flows.

**Fix:** `/research` Phase 1 alignment sub-step now runs a task-level retrofit check when ALL of the following are true:
- Task folder existed before this `/research` invocation (not a fresh creation)
- No `## Task-Level` section in `alignment.md` (or file missing)
- Pre-analysis hook did NOT run this session

When those conditions hold, the command invokes `analysis-agent` in folder mode to check scope warrant and, if `scope_contract_recommended` fires, offers task-level authoring before continuing to Phase 1 alignment. Failure modes (agent timeout / error) proceed silently — never blocks.

Fresh-task and already-authored flows are unchanged (skip the new check entirely). `/design` and `/implement` retain their existing "task-level decline is final post-creation" posture — only `/research` needs to handle retrofit.

No schema change. No new artifacts. `analysis-agent`, `alignment-reader`, and `scope` command unchanged. Behavior change isolated to `commands/research.md`.

## [3.12.1] - 2026-04-23

### Fixed — Private reference scrub (no behavior change)

Documentation-only patch removing internal/private references that leaked into the shipped plugin during v3.10.0–v3.12.0 development.

- **"P7" terminology removed** — 18 references across 7 files. "P7" was private pain-point numbering from internal epic planning; it was undefined in plugin docs and confusing to marketplace users. Replaced with clear terms: "scope contract", "alignment step", "alignment conversation". No user-visible behavior change.
- **Stale sub-task numbering removed** — `/migrate-to-epic`, `/next`, `/complete`, `/propose-epics` command bodies contained "sub-task 3.1", "sub-task 3.2" references to internal roadmap items. Some (like `/propose-epics`) were documented as "future" despite having shipped in v3.11.0. Replaced with concrete version numbers or removed.
- **Private project-file paths removed** — `alignment-reader`, `project-state-reader`, `analysis-agent`, `alignment-contract.md` each pointed at files like `dev_framework_task_contract/architecture.md` in the maintainer's private memory directory that marketplace users will never have. Dropped.
- **Example JSON using private names replaced** — `session-context-writer` SKILL had `"currentEpic": "dev_framework_improvements_epic"` as the example value; `alignment-contract.md` used `"task_name": "dev_framework_task_contract"` in the reader-output example. Both replaced with generic placeholders.
- **CHANGELOG future-task name redacted** — v3.10.0 entry named a specific-future-task (`dev_framework_next_orchestrator_dedup`) that was private roadmap. Generalized to "tracked for a future release".
- **Minor grammar fixes** — article/spacing artifacts from automated replacement cleaned up.

No command, skill, agent, or script behavior changes. Schema stays v1.0; no migrations needed.

## [3.12.0] - 2026-04-23

### Added — Task Contract / P7 Alignment Step (sub-task 3.3 of dev-framework improvements epic)

An optional, author-driven scope contract authored before research begins, plus per-phase alignment as the first sub-step of each phase. The whole feature is soft-nudge; never blocks the task lifecycle. Existing tasks without `alignment.md` work unchanged.

**New command `/drupal-dev-framework:scope <task-name> [--phase 1|2|3]`** — authors or retrofits `alignment.md` via a 4-field P7 conversation: Goal / Expected result / Success criteria / Non-goals. Without `--phase`, writes the `## Task-Level` section. With `--phase N`, writes the corresponding phase section. Same code path covers new-task authoring and retrofit of existing tasks. Overwrite guard: `[o]verwrite / [e]dit / [c]ancel` with default cancel. Conversation follows the superpowers `brainstorming` convention — one question at a time, author-authored, never auto-generated.

**New `references/alignment-contract.md`** — canonical grammar v1.0 for `alignment.md`:
- H2 sections: `## Task-Level`, `## Phase 1 — Research`, `## Phase 2 — Architecture`, `## Phase 3 — Implementation` (em-dash canonical; hyphen and en-dash tolerated on read, rewritten to em-dash on any write)
- H3 fields: `### Goal`, `### Expected result`, `### Success criteria` (task-list), `### Non-goals` (bullet list)
- 8 defensive warning codes: `file_missing`, `unknown_section`, `missing_field`, `unknown_field`, `empty_field`, `success_criteria_not_checklist`, `non_goals_not_bulleted`, `error`
- JSON output contract + versioning policy (additive fields at v1.x; major bump only on semantics change)

**New `alignment-reader` skill v1.0.0** (haiku, user-invocable: false) — defensive parser wrapper around `scripts/alignment-read.sh`. Structured JSON output with `sections.{task_level, phase_1, phase_2, phase_3}` and a `warnings[]` array. Never throws except on unrecoverable IO errors. Mirrors `project-state-reader` and `task-frontmatter-reader` patterns.

**`analysis-agent` extension** — new signal code `scope_contract_recommended` in `references/analysis-agent-schema.md`. Fires when the task would benefit from an up-front P7 scope contract:
- (a) description has ≥2 distinct outcome dimensions
- (b) description contains conjunctive phrasing (`and also`, `plus`, `as well as`, `in addition to`)
- (c) (folder mode only) ≥3 acceptance criteria already in task.md AND description word count > 60

Orthogonal to `epic_candidate` — a task may fire both, one, or neither. Decide step split into epic-decomposition signals (drive the `decision` branch) vs orthogonal signals (recorded in `signals_used[]` but do not force `epic_candidate`). Schema stays `"1.0"` (additive per v1.x extensibility policy).

**Phase-alignment sub-steps in `/research`, `/design`, `/implement`** — each command offers to author the corresponding phase section as its first sub-step (after Phase Transition Check). Decision tree reads `alignment-reader` JSON: if section already present → reuse; else if task-level present → offer `[y/n/skip]`; else proceed silently. Never blocks. `/research` also has a "re-offer for lighter-touch" branch after the pre-analysis hook — `/design` and `/implement` intentionally do NOT (that decline is considered final post-creation).

**`/research` pre-analysis hook extended** — step 5 inspects `signals_used[]` for `scope_contract_recommended` and soft-nudges the user to author a task-level scope contract before research begins. Default answer: `[later]` / `[n]` proceeds without writing.

**`/next` retrofit suggestion** — when selected task has no `alignment.md`, prints a one-line nudge pointing at `/scope <task>`. One-time nudge, never blocks.

### Validated

- Grammar spec written before parser (Step 1 of 14)
- Parser smoke-tested on 5 fixtures (missing / minimal / prose-criteria / unknown sections / full with hyphen+em-dash variants) before wiring into commands
- Structured 3-phase paper test found 1 BLOCKER (research.md missing `Skill` + sibling-command invocation pattern), 2 MAJOR (parser `fields_missing` conflation; schema consumer guidance stale), 4 MINOR (folder-mode clarification, insertion order precision, overwrite-guard warning surface, `/next` retrofit promise)
- All 7 findings applied; parser fix re-smoke-tested on 3 new fixtures (prose / empty / truly-missing) — all 3 warning states now distinct
- 3-validator gate: skill-quality-reviewer A, plugin-structure-auditor 44/50 (consumer guidance gap fixed), metadata pre-check 10/10 PASS

## [3.11.0] - 2026-04-23

### Added — Project codePath + Analysis Agent (sub-task 3.2 of dev-framework improvements epic)

Two coupled additions: project-level `codePath` metadata infrastructure, and a read-only analysis agent that proposes epic decompositions for flat tasks. All additive; flat tasks and existing commands behave unchanged when these features aren't used.

**Project `codePath` metadata** — projects can now declare where their code lives (distinct from the memory folder). Supports three states: **unknown** (never set — triggers detect+confirm on first use), **docs-only** (intentionally no code — null at runtime, no warnings), **set** (`/abs/path` — validated).

- **`project-state-reader` skill v1.0.0** (haiku, user-invocable: false) — defensive reader for `project_state.md`'s `**Code path:**` line. Emits structured JSON `{project_name, codePath, folder, warnings[]}`. Thin wrapper around `scripts/project-state-read.sh`. Five warning codes: `folder_missing`, `project_state_md_missing`, `code_path_unknown`, `code_path_missing`, `malformed_header`.
- **`scripts/project-state-read.sh`** — portable bash. `realpath -m` normalization, `(docs-only)` sentinel handling. Never throws.
- **New command `/drupal-dev-framework:set-code-path [<path>|--docs-only]`** — three invocation modes: explicit path, `--docs-only` sentinel, or interactive detect+confirm. Writes `project_state.md` as source of truth and syncs `active_projects.json` cache. Path-safety filter hard-rejects system roots (`/`, `/etc`, `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/boot`, `/sys`, `/proc`, `/dev`, `/var`, `/opt`, `/root`, `$HOME` ancestors) and warns-but-allows paths outside `$HOME`.
- **`/new` updated** — new Step 3 captures codePath at project creation time with 4 user options (Y/path/d/s). Detection strategies in `references/code-path-detection.md`.
- **`project-initializer` v1.4.0** (sonnet) — accepts `code_path` arg; `project_state.md` template emits `**Code path:**` line (or omits if not provided).

**`analysis-agent` v1.0.0** (sonnet, read-only) — assesses whether a flat task is epic-sized and proposes 3-5 children. Tools: `Read`, `Grep`, `Glob`, `Bash` (read-only with mutation-subcommand denylist: `rm`, `mv`, `cp`, `sed`, `tee`, `dd`, `chmod`, `chown`). Never mutates state; never emits user-facing chat. Two input modes:

- **Folder mode** — `task_folder` input; reads task.md / research.md / architecture.md / implementation.md via `task-frontmatter-reader` + Read; full 7-signal evaluation. Used by `/propose-epics`.
- **Description mode** — `task_description_text` input (folder doesn't exist yet); restricted 3-signal evaluation (`description_length_and_conjunction`, `bullet_count_clustering`, `multiple_code_areas` if code_read). Used by `/research` pre-analysis hook.

Emits structured JSON per `references/analysis-agent-schema.md` v1.0. Seven invariants enforced before emit (proposed_children iff epic_candidate; `confidence: low` REQUIRED when `code_read: false`; signals non-empty on epic_candidate; `schema_version` is a JSON string; child names match `^[A-Za-z0-9_][A-Za-z0-9._-]*$`; rationale ≤400 chars; no literal newlines in string fields).

**New command `/drupal-dev-framework:propose-epics`** — bulk-reviews all flat in-progress tasks. Spawns `analysis-agent` subagents in parallel (one per candidate) via the Task tool. Presents per-task decisions (epic_candidate / keep_flat / insufficient_info) with accept / edit / reject / skip options. Accepted proposals invoke `/migrate-to-epic` under the hood. Summary reports counts including partial failures (invalid JSON, subagent crash, schema mismatch) — no silent drops.

**`/research` pre-analysis hook** — on new-task creation, evaluates three strong signals in the task name + description: length > 500 chars, ≥3 bullets, explicit conjunctions (`and also`, `plus`, `as well as`, `in addition to`). If any fires, invokes `analysis-agent` in description mode BEFORE creating the task directory. On `epic_candidate`, prompts user to create as epic / flat / standard. Conservative — default answer is flat; never creates an epic without explicit confirmation.

**New references:**
- `references/analysis-agent-schema.md` — canonical JSON Schema v1.0, 7 field contracts, 7 invariants, 7 signal codes, 3 example outputs, versioning policy, input-modes contract.
- `references/code-path-detection.md` — 2 shipped strategies (`$PWD` markers, sibling-of-memory-folder), priority order, confirm-prompt UI, fallback cold prompt, three-null-states table, safety filter (shared with `/set-code-path`).

## [3.10.0] - 2026-04-22

### Added — Task Hierarchy Foundation (sub-task 3.1 of dev-framework improvements epic)

Ships the structural foundation for epic/sub-task hierarchy. Flat tasks remain a first-class, permanent option; hierarchy is additive and opt-in per task.

**Frontmatter schema on `task.md`** — new optional YAML block with `id` (URI-style, e.g. `local:<folder>`), `kind` (`flat` | `epic` | `sub_epic` | `subtask`), `parent`, `children[]`, `blocks[]`, `blocked_by[]`, `external_ids` (reserved for future tracker integration), and a derived `status` field. Missing frontmatter defaults to `kind: flat` with zero behavior change.

**Folder nesting with per-epic `in_progress/` and `completed/`** — up to 2 epic levels. Each epic folder contains:
- `task.md` — the epic's own tracker
- `shared/` — cross-cutting artifacts (decision logs, planning matrices, mechanisms maps — each epic decides its own)
- `in_progress/` — subtask folders currently being worked on
- `completed/` — subtask folders that finished (they STAY inside the epic; spatial association preserved)

This mirrors the project-level `in_progress/`/`completed/` convention — same rule at a different scope. When `/complete` runs on a subtask, it moves from `<epic>/in_progress/<child>/` to `<epic>/completed/<child>/` without leaving the epic. When the epic itself completes, the whole folder (with its internal in_progress-empty and completed-full) moves to project-level `completed/<epic>/` as one unit. History stays intact.

**New command `/drupal-dev-framework:migrate-to-epic <task>`** — converts a single flat task into an epic folder with children. Supports `--dry-run` and `--children "a,b,c"`. Transactional via a temp directory + atomic swap; the filesystem is either fully pre-migration or fully post-migration state, never partial. 24h rollback window at `.migration-tmp/.old-<task>/`.

**New skills:**
- **`task-frontmatter-reader` v2.0.0** (haiku, user-invocable: false) — defensive YAML frontmatter parser. Never throws; always emits structured JSON with a `warnings[]` array. Thin wrapper around `scripts/fm-read.sh`.
- **`epic-migrator` v2.0.0** (sonnet, user-invocable: false) — runs the 8-step transactional migration. Thin wrapper around `scripts/migrate-to-epic.sh`.

**New scripts** (real executables, not embedded instructions):
- `scripts/fm-helpers.sh` — sourced helpers (fm_read, write_epic_frontmatter, write_subtask_frontmatter, apply_frontmatter, write_stub_task_md). Portable bash 4+ / zsh 5+.
- `scripts/fm-read.sh` — entry point for the reader skill.
- `scripts/migrate-to-epic.sh` — entry point for the migrator skill. Emits session-context case analysis (A / B / C) on stderr as `KEY=VALUE` lines.

**Hierarchy-aware updates (minor) to existing commands:**
- `/status` — tree rendering for epics with completed-child resolution across `in_progress/` and `completed/`, dangling-reference markers.
- `/next` — biases suggestions toward sibling subtasks within the active epic; surfaces `/migrate-to-epic` when current task looks epic-sized.
- `/complete` — subtask completion moves the child out of the epic folder (to `completed/<name>/`); epic completion gated on ALL children being completed.

**`session-context-writer` v1.4.0** — added `currentEpic` field with placeholder-sentinel preserve semantics. Caller passes the literal string `{CURRENT_EPIC_OR_NULL}` to preserve, `"null"` to clear, or an epic folder name to set. Backwards-compatible for pre-v1.4.0 callers.

### Security hardened (from paper-test rounds)

- **Name validation** — task and child names rejected if they contain `/`, `\`, `..`, `.`, or non-`[A-Za-z0-9._-]` characters. Prevents path traversal via child name (CRITICAL finding).
- **Symlink rejection** — migration refuses to proceed if the task folder or its `task.md` is a symlink. Prevents information disclosure via symlink-target copying.
- **Atomic swap recovery** — swap-failure branch now also cleans up the partial temp directory (not just restoring the original).
- **Concurrent migration lock** — atomic `mkdir` on the task-specific temp dir fails fast if another migration is in flight.
- **Completed-children classification** — `already_completed` is a distinct classification; completed children get their id added to the epic's `children[]` but are NOT copied or stubbed (stays in `completed/`). Integration-bug fix caught by paper-test before dog-food.
- **Cross-cutting artifact preservation** — top-level files in the original task folder (other than `task.md` and phase artifacts) are relocated to the new epic's `shared/` folder during migration.

### Dog-food validation

v3.10.0 was validated by migrating `dev_framework_improvements_epic` itself using the shipped command. 10 children classified correctly (7 move_existing + 2 already_completed + 1 create_stub). `mechanisms-map.md` relocated to `shared/`. Completed children preserved in `completed/` without duplicates. Session context correctly updated via Case C (active subtask's path followed into the new nested location). The framework now operates on its own hierarchy — proof by dog-food.

### Notes

- **`/migrate-to-epic` is the atomic primitive only.** Automated epic detection (`/propose-epics`), guided granularity via an analysis agent, P7 alignment step, phase-sub-granularity, and graph-aware `/next` are all deferred to sub-tasks 3.2 and 3.3.
- **Rollback auto-cleanup not implemented.** `.migration-tmp/.old-<task>/` persists until manual `rm -rf`. Tracked as a future enhancement.
- Shell portability verified on zsh (the user's shell); earlier drafts hit a zsh-specific parameter-modifier bug with `$var:c` unbraced, fixed via parallel arrays.

## [3.9.1] - 2026-04-21

### Changed — Task Process Adherence (sub-task 2 of dev-framework improvements epic)

- **Context-reminder wording tuned toward role-identity framing.** The `UserPromptSubmit` reminder now opens with a directive statement ("**drupal-dev-framework protocol is active on this task.** You are on `<task>` — <phase>. Phase sequencing applies… Apply SOLID, TDD, and DRY… Keep `task.md` `## Phase Status` checkboxes current as each phase progresses") instead of a passive title ("Active Task Context"). The structured file-listing, loaded-guides line, next-command line, and monolith-prevention reminder below the opening are unchanged.

### Fixed

- **Workspace-hash consistency across hooks.** `context-reminder.sh` (new in v3.9.0) used `printf %s "$PWD"` for its workspace-hash computation, while the four pre-existing hooks (`session-start.sh`, `pre-compact.sh`, `post-compact.sh`, `stop-failure.sh`) used `echo -n "$PWD"`. For typical paths the two forms produce identical hashes, but `echo -n` has portability edge cases with backslashes and certain special characters. Aligned all five hooks to `printf %s` so the writer and reader of `sessions/<hash>.json` are guaranteed to use identical input across any shell/path combination. Caught by the `plugin-structure-auditor` agent's post-fix re-run.

### Why this is a patch, not a minor

No mechanism changes — same hook event, same JSON envelope shape, same data flow, same session-file gating. The revision is wording inside `additionalContext` plus the hash-consistency alignment. Payload size grows ~80 chars; still far below the 9500-char truncation guard.

### Fixed — auditor fallout (batched in-band)

The `plugin-structure-auditor` gate (newly required by the epic AC) surfaced five pre-existing issues. All are non-breaking and orthogonal to the wording tune, so batched into this patch rather than backlogged:

- **Agents route guide-loading through `guide-integrator` instead of direct `WebFetch`.** `architecture-drafter` and `architecture-validator` previously instructed Claude to `WebFetch https://camoa.github.io/dev-guides/drupal/{topic}/` directly, bypassing the navigator's caching, disambiguation, and the `loadedGuides[]` tracking the v3.9.0 substrate depends on. Both agents now delegate to `guide-integrator`, which invokes `dev-guides-navigator` and records each loaded guide into `session_context.json`.
- **`task-completer` migrated to v3.0.0 folder structure.** Step 4 previously did `mv` on a `{task}.md` file path and Step 6's glob scanned `*.md` files — both broken on v3 installs (tasks are folders, not single files). Step 4 now moves the task directory; Step 6 lists in-progress task folders via `ls -d`.
- **`task-completer` now enforces all 5 quality gates.** The table previously listed 4 gates; Gate 5 (task-artifact completeness — acceptance criteria `[x]`, `## Phase Status` 1–3 all `[x]`, all three phase `.md` files present) is now explicit.
- **`task-completer` Gate 4 security guidance routed through `guide-integrator`.** Was `WebFetch dev-guides/drupal/security/` directly; now delegates to the integrator.
- **`model:` frontmatter declared across 6 skills.** `session-resume` (sonnet), `memory-manager` (sonnet), `task-completer` (sonnet), `implementation-task-creator` (sonnet), `component-designer` (sonnet), `diagram-generator` (haiku). Previously these skills inherited the invoking context's model, which could be under- or over-powered for their workload.
- **Skill descriptions re-anchored.** `guide-loader` description rephrased from gerund ("Use when needing…") to condition-clause form ("Use when a framework task requires…") per the plugin's own convention.
- **`guide-integrator` description tightened** (v4.1.1) — from ~480 chars to ~380 chars by moving trigger phrases and "Use proactively" guidance to the body's Activation section per skill-quality-reviewer feedback.

### Still tracked for follow-up (not in this patch)

- **WARN-1: `/next` command and `project-orchestrator` agent duplicate routing logic.** Fix requires a design decision (which is source of truth) plus an integration test — `/next` is the primary entry point and regression is high-impact. Tracked for a separate future release.

### Dismissed (auditor false positive)

- **WARN-5: README `@camoa-skills` install syntax.** Verified: `/plugin install <name>@<marketplace>` is the documented Claude Code install syntax, used consistently across every plugin in this marketplace. Not a deficiency.

### Research-backed scope (from `dev_framework_task_process_adherence` research v3)

Sub-task 2 originally contemplated a 5-layer enforcement scaffolding. That research was flagged as having unverified assumptions and rewritten from scratch. The fresh research (v3) rejected most speculative directions — cross-workspace lookup (parallel-work pattern confirmed functional today), skill-scoped identity hooks (speculative without observed drift), FileChanged/PermissionDenied enforcement (intentionally soft-nudge posture from v3.9.0 preserved) — and narrowed ship-now scope to H1 (wording tune). Checkbox-upkeep language added to the reminder probes the drift hypothesis without building a mechanism for it.

## [3.9.0] - 2026-04-20

### Added — Task Phase Guidance (sub-task 1 of dev-framework improvements epic)

- **`context-reminder` UserPromptSubmit hook** (`hooks/context-reminder.sh`) — injects a compact task-context block into Claude's context on every user prompt when a framework task is active in the current workspace. Emits structured `additionalContext` JSON per the `UserPromptSubmit` spec. Surfaces:
  - Active task name and current phase
  - Task folder path and the v3.0.0 file convention (`task.md` / `research.md` / `architecture.md` / `implementation.md`) with a `◀ current` marker on the active-phase line
  - Session-loaded dev-guides (capped at 20 with "+N more" suffix)
  - Next recommended command
  - Directly addresses: (a) Claude drifting back to monolithic task docs instead of the folder convention, (b) loaded dev-guides being ignored as context decays, (c) users losing track of which phase command comes next.
- **`loadedGuides[]` and `lastPhase`** fields added to per-workspace `session_context.json`. Managed by `guide-integrator` (append on load, idempotent) and read by the `context-reminder` hook. Never clobbered by `session-context-writer` on subsequent writes (jq-based merge preserves existing values).
- **Phase-transition soft nudge** in `/design` and `/implement` commands — on command entry, reads `## Phase Status` in `task.md`; if the prior phase isn't `[x]`, prints a one-line warning that points the user at the missing command, then proceeds. Never blocks — users remain in control.
- **Plugin Dependency on `dev-guides-navigator`** declared in `.claude-plugin/plugin.json` (`dependencies: ["dev-guides-navigator"]`). Missing-dependency failures now surface at install time instead of silently at runtime. **Requires Claude Code v2.1.110 or later.**

### Changed

- **`session-context-writer` skill v1.3.0** — now uses `jq`-based merge to preserve `loadedGuides[]` and `lastPhase` across writes. Seeds both fields on first-write.
- **`guide-integrator` skill v4.1.0** — records each loaded guide into `loadedGuides[]` using stable IDs (`plugin:<basename>` for methodology refs, topic paths for dev-guides). Checks `loadedGuides[]` before fetching — skips re-loads. This is the source-of-truth for "already loaded," replacing conversation-context heuristics.

### Removed

- **SessionStart soft dependency check** in `hooks/session-start.sh` — removed the 21-line runtime check that warned when `dev-guides-navigator` wasn't installed. Superseded by install-time enforcement via the new `dependencies` field.

### Hardening (post-paper-test)

- **10K-char truncation guard** added in `context-reminder.sh` before emit — Claude Code caps `additionalContext` at 10,000 chars and replaces overflow with a file-preview pointer; the guard ensures the reminder text always reaches the model.
- **Phase-matching regex hardened** in `context-reminder.sh` — anchored to list-item lines (`^- [x] Phase N`) and requires `Phase N[^0-9]` so `n=1` no longer spuriously matches "Phase 10"/"Phase 11". Also accepts uppercase `[X]` checkboxes (normalized to `[x]` internally) and rejects prose lines that happen to contain `[x]` near the word "Phase".
- **Corrupt-session self-heal** in `session-context-writer` — if the existing `session_context.json` fails `jq -e .` validation, the skill now reseeds from scratch instead of failing silently every subsequent write.
- **Empty-guide-ID guard** in `guide-integrator` — an empty `{GUIDE_ID}` now exits early instead of polluting `loadedGuides[]` with `""`.
- **Phase-nudge clarification** in `/design` and `/implement` — `{task_name}` placeholder explicitly marked as a substitution target (was "print exactly as shown", which conflicted with interpolation intent). `/implement` now evaluates Phase 1 and Phase 2 independently so a user who somehow has Phase 2 done but Phase 1 skipped still gets the Phase 1 warning.

### Notes

- Hook performance measured in-workspace: ~3ms for the no-session gate, ~17ms for the no-task gate, ~43ms for a full active-task render. Payload target ≤500 tokens.
- `UserPromptSubmit` does not support `matcher` or the `if` pre-spawn filter (non-tool event). Workspace-level gating lives inside the script, using the per-workspace `session_context.json` hash (`md5("$PWD")`) as the implicit scope marker.
- **Concurrent-write safety** (deferred): `session-context-writer` and `guide-integrator` both follow the `jq FILE > FILE.tmp && mv FILE.tmp FILE` pattern. In a two-window-same-workspace scenario, a race could drop one update. `flock` would eliminate it; not added since (a) session files are keyed per-workspace (different windows typically → different workspaces → different files) and (b) within a single Claude Code turn the skills run sequentially. Flag for follow-up if observed.

## [3.8.0] - 2026-04-08

### Fixed
- **Compaction hooks leaking stale project context** — `session_context.json` persisted across sessions, injecting wrong project context (e.g., `camoa_skills`) regardless of actual project. Registry fallback also guessed incorrectly.

### Added
- **`session-context-writer` skill** (internal) — Writes per-workspace session context keyed by `$PWD` hash. Multiple Claude windows working on different projects no longer conflict.
- All project-aware commands (`/next`, `/new`, `/research`, `/research-team`, `/design`, `/implement`, `/complete`, `/status`) now invoke `session-context-writer` after resolving project/task.

### Changed
- **Session-start hook** — Clears stale session context for the current workspace on every new session.
- **Pre/PostCompact hooks** — No longer dump cached content. Now output instructions for Claude to read live `project_state.md` and `task.md` on demand.
- **StopFailure hook** — Reads per-workspace session file instead of global `session_context.json`.
- Session context stored under `~/.claude/drupal-dev-framework/sessions/<workspace-hash>.json` (was single global file).

## [3.7.0] - 2026-03-20

### Added
- **`/visual-check` command** — Compare rendered Drupal page against Figma design comp using Chrome + optional Figma MCP. Opens DDEV site in Chrome, extracts computed CSS, compares against Figma specs or reference screenshot. Reports discrepancies by severity (Critical/Major/Minor) with CSS-level fixes. Multi-breakpoint (1280px, 768px, 375px). Can integrate as optional Gate 6 in `/complete` for front-end tasks.
- **`/loop` patterns** documented in CLAUDE.md — Deploy polling (`/loop 5m check drush cr`), config import monitoring, status dashboard refresh.
- **Sandbox + DDEV configuration** documented in CLAUDE.md — `ddev` must be in `excludedCommands`, Docker socket access requires exclusion from sandbox.
- **Path-specific rules guidance** documented in CLAUDE.md — Recommended `.claude/rules/` scoped to `*.php`, `*.twig`, `*.scss` for Drupal conventions.

## [3.6.3] - 2026-03-20

### Added
- **PostCompact hook** (`hooks/post-compact.sh`): Re-injects active project/task context after compaction — reads `session_context.json` and outputs project state + task details so Claude can continue without manual re-orientation
- **StopFailure hook** (`hooks/stop-failure.sh`): Logs task failures caused by API errors to `~/.claude/drupal-dev-framework/logs/failures.log`, with project/task name from session context, so the next session can detect unclean exits
- **`hooks.json`**: Added `PostCompact` and `StopFailure` event registrations for the two new hook scripts

### Changed
- **agent-conventions.md**: Added "Agent Frontmatter Limitations" section — documents that `hooks`, `mcpServers`, and `permissionMode` in agent frontmatter are ignored when agents run as sub-agents via the Agent SDK. Notes that `architecture-validator`'s PreToolUse hook frontmatter is interactive-only; `disallowedTools` remains the reliable write-block

## [3.6.1] - 2026-03-15

### Fixed
- **architecture-validator**: Removed `isolation: worktree` — caused failures in Drupal projects without git repos (DDEV containers, nested repos). Agent is already read-only via `disallowedTools` + PreToolUse hook guard

## [3.6.0] - 2026-03-13

### Added
- **Agent cost control**: `maxTurns` on all 5 agents — prevents runaway loops (architecture-drafter: 30, project-orchestrator: 25, architecture-validator: 20, contrib-researcher: 15, pattern-recommender: 15)
- **Agent isolation**: `isolation: worktree` on architecture-validator — runs in isolated worktree for defense in depth
- **Tool restrictions**: `allowed-tools` on 3 skills — phase-detector (Read, Glob), session-resume (Read, Glob, Bash), requirements-gatherer (Read, Write, Glob)
- **Context forking**: `context: fork` on validate and status commands — preserves main context window from heavy output
- **Proactive dev-guides integration**: guide-integrator now activates at the START of every phase, not just when explicitly requested. Research, design, and implement commands all load relevant dev-guides before proceeding (skips if already loaded in session)
- **Dependency check**: SessionStart hook now warns if `dev-guides-navigator` plugin is not installed, with install instructions

### Changed
- **WORKFLOW.md**: Full rewrite — v3.0.0 folder structure, 5 quality gates (was 4), proactive dev-guides per phase, agent maxTurns/isolation details, research-team in flow diagrams, SessionStart dependency check in session flow
- **README.md**: `dev-guides-navigator` listed as required (not just recommended), agents table with maxTurns column, dev-guides section shows per-phase loading table
- **marketplace.json**: Version bumped, description notes `dev-guides-navigator` requirement
- **Agent descriptions**: All 5 agents now include trigger phrases and enforcement reminders — Claude auto-delegates more reliably and respects quality gates mid-conversation
- **Command descriptions**: All 11 commands now include trigger phrases and workflow enforcement language
- **Skill descriptions**: 6 key skills updated with trigger phrases and enforcement (code-pattern-checker, tdd-companion, session-resume, diagram-generator, task-completer, guide-integrator)
- **Agent body reinforcement**: project-orchestrator, architecture-validator, and architecture-drafter bodies now include bold quality gate reminders that persist through long conversations
- **research-team**: Removed experimental agent teams flag (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`), added `teammateMode: split-panes` option
- **CLAUDE.md**: Strengthened dev-guides section — now says "ALWAYS consult dev-guides before making Drupal development decisions" with per-phase loading guidance

## [3.5.1] - 2026-02-18

### Fixed
- **Session context survives compaction**: Commands now write `session_context.json` with active project/task so pre-compact hook can inject accurate context instead of guessing from `lastAccessed`
- **pre-compact.sh**: Reads session context first, outputs task.md content for active task; falls back to registry-based guess only when no session context exists
- **next.md, status.md**: Added `Write` and `Bash` to allowed-tools so they can write session context
- **command-conventions.md**: Added session context tracking convention — all commands that resolve a project/task must write the context file

## [3.5.0] - 2026-02-16

### Changed
- **Dev-guides integration v2**: Replaced keyword→URL mapping table in guide-integrator with lightweight `llms.txt` discovery + topic hints
- **guide-integrator workflow**: Now fetches `llms.txt` index to discover topics instead of matching against a static table
- **CLAUDE.md**: Added Online Dev-Guides section with `llms.txt` index URL and topic hints for session-wide awareness

## [3.4.0] - 2026-02-14

### Added
- **Online dev-guides integration**: Skills and agents now WebFetch decision guides from https://camoa.github.io/dev-guides/ for Drupal domain knowledge (forms, entities, plugins, routing, services, caching, security, SDC, JS, and 20+ more topics)
- **guide-integrator v3.0.0**: Three-source model — plugin methodology refs, online dev-guides, user's custom guides
- **guide-loader v2.0.0**: Falls back to online dev-guides when no local guides configured
- **architecture-drafter**: Consults dev-guides for Drupal-specific architecture decisions
- **architecture-validator**: Uses online dev-guides for security and frontend validation

### Removed
- **references/security-checklist.md**: Replaced by dev-guides `drupal/security/` (22 online guides)
- **references/frontend-standards.md**: Replaced by dev-guides `drupal/sdc/` + `drupal/js-development/` (38 online guides)

### Changed
- **code-pattern-checker**: References online dev-guides for security and frontend checks
- **task-completer**: Gate 4 security references online dev-guides
- **quality-gates.md**: Updated security and frontend references to point to online guides
- **WORKFLOW.md**: Updated reference table

## [3.3.0] - 2026-02-10

### Added
- **NEW: `/research-team` command** — Phase 1 research using agent teams with 3 competing perspectives
  - **Feature mode**: Contrib Scout (haiku) + Core Pattern Finder (haiku) + Devil's Advocate (sonnet) debate Build vs Use vs Extend
  - **Bug mode**: 3 Hypothesis Investigators (sonnet) with competing theories challenge each other to find root cause
  - Auto-detects task type from goal keywords; user can override
  - Each teammate writes own findings file (persists for future reference and session recovery)
  - Lead synthesizes final `research.md` (feature) or `investigation.md` (bug)
  - Falls back to standard `/research` when agent teams not available
  - Requires experimental flag: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

## [3.2.0] - 2026-02-10

### Changed
- **Project storage**: Registry now stores `projectsBase` — user's preferred base path for all projects, asked once on first run
- **Default path**: Removed hardcoded `../claude_projects/` default; new projects use saved `projectsBase/{name}/`
- **Registry schema v1.1**: Removed `phase` field (phase is per-task, not per-project). Added `projectsBase` field
- **project-initializer** v1.3.0: Reads `projectsBase` from registry, asks user on first run instead of assuming a path
- **memory-manager**: No longer writes `phase` to registry

## [3.1.0] - 2026-02-07

### Added
- **Agent memory** on 3 agents: project-orchestrator, architecture-validator, architecture-drafter (`memory: project`)
- **Model routing** on 5 agents: opus (drafter), sonnet (orchestrator, validator, recommender), haiku (researcher)
- **Model routing** on 5 skills: opus (component-designer), sonnet (diagram-generator), haiku (guide-loader, core-pattern-finder, phase-detector)
- **Tool restrictions** on 3 agents: contrib-researcher and pattern-recommender (`disallowedTools: Edit, Write, Bash`), architecture-validator (`disallowedTools: Edit, Write`)
- **Invocation control** on 6 skills: guide-loader, core-pattern-finder, phase-detector, task-context-loader, memory-manager, guide-integrator (`user-invocable: false`)
- **Dynamic context injection** on 3 files: project-orchestrator (project state), session-resume (git branch), task-context-loader (active tasks)
- **Agent-scoped hooks**: architecture-validator PreToolUse prompt hook to block write attempts
- **Skills preloading**: architecture-drafter preloads guide-integrator
- **PreCompact hook** (`hooks/pre-compact.sh`) to preserve project context before compaction
- **CLAUDE.md** at plugin root with project conventions
- **`.claude/rules/`** with 3 path-scoped rule files: agent-conventions, skill-conventions, command-conventions

### Changed
- Exited beta — version 3.0.0-beta.1 → 3.1.0
- **Lean documentation**: pruned v2.x migration content and redundant output examples from project-orchestrator (~25% reduction)
- **Lean documentation**: condensed architecture-drafter output template (70 → 10 lines)
- Added missing `version` field to pattern-recommender and contrib-researcher

## [3.0.0-beta.1] - 2026-01-14

### Added
- **NEW: task-folder-migrator skill (v3.0.0)** - Migrate v2.x single-file tasks to v3.0.0 folder structure
  - Scans for old `.md` files
  - Creates folder structure with separate phase files
  - Preserves all content with automatic backups
  - Idempotent and safe to run multiple times
  - **Automatic mode** - No confirmation when invoked by `/next`
  - **Manual mode** - Shows plan and waits for confirmation when invoked by `/migrate-tasks`
- **NEW: /migrate-tasks command** - Manual migration command
  - Shows full migration plan
  - Waits for user confirmation
  - Full control over migration process
- **NEW: Folder-based task structure** - Each task gets own folder with organized files:
  - `task.md` - Lightweight tracker with links, status, acceptance criteria
  - `research.md` - Phase 1 research findings
  - `architecture.md` - Phase 2 architecture design
  - `implementation.md` - Phase 3 implementation notes
- **NEW: MIGRATION.md guide** - Complete migration guide for v2.x → v3.0.0
  - Step-by-step migration instructions
  - Troubleshooting section
  - Rollback procedures
  - FAQ for common questions

### Changed
- **BREAKING**: Task structure changed from single file to folder-based organization
- **memory-manager (v3.0.0)** - Updated to scan directories instead of files
  - Detects old v2.x format and warns users
  - Supports both v2.x (backward compat) and v3.0.0 structures
- **phase-detector (v3.0.0)** - Updated to read from folder structure
  - Checks for phase files (research.md, architecture.md, implementation.md)
  - Backward compatible with v2.x single files
- **task-context-loader (v3.0.0)** - Updated to load phase files separately
  - Loads task.md for main info
  - Loads research.md, architecture.md, implementation.md as needed
  - Full context loading from all phase files
- **task-completer (v1.1.0)** - Updated to move entire directory instead of single file
- **project-orchestrator (v3.0.0)** - Updated to scan directories and auto-migrate old format
  - Scans for task directories (v3.0.0)
  - Detects old `.md` files (v2.x)
  - **Automatically migrates** old format when detected via `/next` command
  - Updated task phase detection for folder structure
  - Seamless upgrade experience - one command does everything
- **/research command** - Now writes to `research.md` instead of section in single file
  - Creates task folder structure
  - Updates task.md with phase status
- **/design command** - Now writes to `architecture.md` instead of section
  - Updates task.md to mark Phase 2 in progress
- **/implement command** - Now writes to `implementation.md` instead of section
  - Updates task.md to mark Phase 3 in progress
- **/complete command** - Now moves entire task directory to completed/
- **README.md** - Updated with v3.0.0 structure, migration instructions, benefits

### Migration Path

Upgrading from v2.x:
1. Backup projects before upgrading
2. Install v3.0.0-beta.1
3. Run `/drupal-dev-framework:next` - **automatically migrates old tasks**
4. Or run `/drupal-dev-framework:migrate-tasks` manually if preferred
5. Verify migration results
6. Delete `.bak` files when confident

**Note:** The `/next` command automatically detects old v2.x format and migrates tasks before continuing. No manual intervention needed!

See [MIGRATION.md](./MIGRATION.md) for detailed guide.

### Benefits

**Why This Change:**
- ✅ Separates content by phase
- ✅ Keeps files small and focused (no more huge single files)
- ✅ Easy to navigate (max 4 files per task)
- ✅ Simple flat structure (no nested folders)
- ✅ Better organization and maintainability

**What Stays The Same:**
- All 16 skills available (1 new: task-folder-migrator, 4 updated)
- All 10 commands work (1 new: /migrate-tasks, 4 updated for new structure)
- 5 agents (1 updated: project-orchestrator)
- All 8 reference documents preserved
- Same 3-phase workflow (Research → Architecture → Implementation)

### Breaking Changes

- v2.x single-file tasks (`task.md`) must be migrated to folder structure (`task/`)
- Migration tool provided: `/drupal-dev-framework:migrate-tasks`
- Backward compatibility: Updated skills detect old format and warn users
- v2.x support: Security fixes only after v3.0.0 stable release

## [2.1.0] - 2025-12-18

### Added
- **Gate 5: Code Purposefulness** - New reference document `purposeful-code.md` with:
  - Every-Line-Has-a-Purpose principle
  - Intentional complexity vs accidental complexity
  - Code archaeology and dead code detection
  - Redundancy elimination patterns
  - Real-world examples of purposeless code
- **Expanded Security Checklist** - Enhanced `security-checklist.md` with:
  - Detailed input validation patterns
  - Output escaping context-specific examples
  - Access control implementation strategies
  - CSRF protection guidelines
  - File upload security
  - SQL injection prevention
- **Quality Gates Update** - `quality-gates.md` now includes Gate 5 as 5th enforcement checkpoint
- **Architecture Validator Enhancement** - Updated to check for purposeful code patterns
- **Restored `/new` command** - Dedicated command for starting new projects (removed in 2.0.0)
  - Clearer separation: `/new` for new projects, `/next` for continuing work
  - Interactive mode (no arguments) or direct mode (with project name)
  - Automatically registers project and gathers requirements

### Changed
- Quality gate count increased from 4 to 5
- Security checks now more comprehensive with real-world attack vectors
- `/next` command now focused on continuing existing projects/tasks

## [2.0.0] - 2025-12-12

### Added
- **Built-in Reference Documents** - 7 self-contained reference files in `references/`:
  - `tdd-workflow.md` - TDD with Red-Green-Refactor cycle, Drupal test types
  - `solid-drupal.md` - SOLID principles with Drupal-specific examples
  - `dry-patterns.md` - DRY extraction patterns (Service, Trait, Component)
  - `library-first.md` - Library-First and CLI-First development patterns
  - `quality-gates.md` - 4 quality gates enforced at completion
  - `security-checklist.md` - Input validation, output escaping, access control
  - `frontend-standards.md` - BEM, mobile-first, Drupal behaviors, SDC

### Changed
- **BREAKING**: Plugin is now fully self-contained - no hardcoded external guide paths
- **architecture-drafter** (v2.0.0): Now enforces SOLID, Library-First, CLI-First with mandatory checklist
- **architecture-validator** (v2.0.0): Added security checks, blocking vs warning distinction
- **tdd-companion** (v2.0.0): References internal TDD workflow, enforces Gate 2
- **code-pattern-checker** (v2.0.0): References internal docs for SOLID, DRY, Security, Frontend
- **task-completer** (v2.0.0): Runs all 4 quality gates before allowing completion
- **guide-integrator** (v2.0.0): Removed hardcoded guide filenames, uses built-in references first
- **WORKFLOW.md**: Added Enforced Principles section

### Removed
- **`/new` command** - consolidated into `/next` (single entry point)
- Hardcoded guide filenames (eca_development_guide.md, drupal_configuration_forms_guide.md, etc.)
- Dependency on user having specific external guide files

### Philosophy
- Principles are now **enforced**, not just documented
- Each phase has blocking checks that prevent progression if not met
- Plugin works out-of-box without external configuration

## [1.3.1] - 2025-12-10

### Fixed
- requirements-gatherer now has Step 7 to handle task creation after user provides task name
- Previously, after requirements gathering, the flow could skip straight to research without creating a task
- Now explicitly: validates task name → asks for description → waits for confirmation → invokes `/research`

### Changed
- SessionStart hook now runs `session-start.sh` script that:
  - Checks registry for existing projects
  - Shows project count and directs user to run `/next`
  - Provides clear entry point for new sessions

## [1.3.0] - 2025-12-06

### Added
- WORKFLOW.md with complete workflow documentation
- Step 0 (Project Selection) - lists projects from registry when `/next` called without argument
- Step 2 (Task Selection) - lists existing tasks and offers to create new (follows `/start` pattern)
- Components by Phase documentation showing all 15 skills and 5 agents
- Component activation flow diagram

### Changed
- `/next` command now follows original guide's `/start` pattern:
  1. Lists projects if none specified
  2. Lists tasks in `in_progress/` after project selected
  3. User picks existing task OR enters new name
- project-orchestrator updated with Step 0 (project selection) and Step 2 (task selection)

## [1.2.0] - 2025-12-06

### Changed
- **BREAKING**: Phases now apply to TASKS, not projects (aligns with drupal_development_guide.md)
- Projects contain requirements (gathered once) + multiple tasks
- Each task independently goes through Research → Architecture → Implementation
- Multiple tasks can be in `in_progress/` simultaneously

### Updated
- project-orchestrator: Now manages tasks, asks "What task do you want to work on?" after requirements
- phase-detector: Detects phase per task file, not per project
- requirements-gatherer: Transitions to task definition after requirements complete
- project_state.md template: Uses "Current Implementation Task" / "Up Next" / "Completed" format
- /next command: Task-aware decision logic

### Added
- Project registry system at `~/.claude/drupal-dev-framework/active_projects.json`
- project-initializer now registers projects on creation
- session-resume lists registered projects for easy selection
- memory-manager maintains registry

## [1.1.4] - 2025-12-06

### Added
- Project type question in requirements-gatherer (new module vs existing vs core issue)
- Auto-trigger rules in guide-integrator for automatic guide loading based on keywords
- Architecture principles validation (Library-First, CLI-First, SOLID) in architecture-validator
- Step 10 in project-initializer to direct users to `/next` command

### Fixed
- `/new` command now directs to `/next` instead of listing manual commands
- Aligned plugin with drupal_development_guide.md requirements

## [1.1.3] - 2025-12-06

### Fixed
- Removed assumption that projects are always modules
- Removed redundant component arrays, rely on auto-discovery
- Added skills arrays to marketplace.json and plugin.json for discovery
- Aligned manifests with official plugin schema

## [1.1.2] - 2025-12-06

### Fixed
- Added skills/agents/commands arrays for plugin discovery

## [1.1.1] - 2025-12-06

### Fixed
- Aligned manifests with official plugin schema

## [1.1.0] - 2025-12-06

### Added
- Version numbers to all SKILL.md frontmatter
- Enhanced skill descriptions

## [1.0.0] - 2025-12-06

### Added
- Initial release of drupal-dev-framework plugin
- 15 skills for 3-phase development workflow
- 9 slash commands for project management
- 5 agents for specialized tasks
- Memory management system with project_state.md
- TDD companion and code pattern checker
- Integration with superpowers and drupal-dev-tools
