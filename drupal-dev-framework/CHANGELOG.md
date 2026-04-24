# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
