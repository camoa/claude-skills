---
description: "Load context and start implementing a task. Trigger: 'start coding', 'implement task', 'begin implementation', 'Phase 3', 'write code'. REQUIRES completed architecture. Enforces TDD (test-first)."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Skill, Task
argument-hint: <task-name>
---

# Implement

Phase 3 of a task. Behavior current as of v4.0.2; full prose / examples / version history in `references/implement-walkthrough.md`.

> **Reading strategy:** Implementation reads inherited classes, annotations, and config-wired services in full (**Type B**) — never grep-first. See `https://camoa.github.io/dev-guides/development/reading-strategy/`.

## Usage

```
/ai-dev-assistant:implement <task-name>
```

## Runtime Steps

1. **Phase Transition Check.** Read `task.md` Phase Status. Evaluate Phases 1 and 2 independently:
   - Phase 2 not `[x]` → print one-line soft-nudge ("Phase 2 not complete; consider `/ai-dev-assistant:design <task>` first.").
   - Phase 1 not `[x]` → print one-line soft-nudge ("Phase 1 not complete; running `/implement` without research is unusual.").
   - Both `[x]` → silent.
   Never block.

2. **Worktree signals (v3.16.0+).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-signals.sh <task>`. On HIGH-strength signal (`another_task_active`, `dirty_tree`, `--worktree` flag, or `worktreeByDefault: true`), print soft-nudge offering `/worktree <task>`. Suppress when already inside a worktree. Never block.

2b. **Work-order build-path offer (v4.19.0+, conditional).** Check whether `<task>/work-orders/wo-*.md` exist (Bash glob). **SILENT when absent — do not print anything if no work-orders are found.** When files are found, print ONE soft-nudge:

> 💡 Work-orders found for this task. Build via independent agents? `/ai-dev-assistant:run-work-orders <task>` (requires a worktree) runs each WO in isolation. `[y]` → hand off to `/run-work-orders`; `[n]` (default) — continue in-session. See `references/work-order-lifecycle.md`.

Default `[n]` — continue to step 3 (dev-guides preflight) and the Interactive Development Loop unchanged. The in-session default behavior is not altered by this check.

3. **Dev-guides preflight (two-stage + component-aware, v4.10.0+).** Stage 1 deterministic; Stage 2 in two agent passes (prose + component file-path). See `/research` step 3 for the shared two-stage description.
   - **Stage 1 (deterministic).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh <task_folder> --phase implement` → `{ methodology_floor[], catalog_candidates[], scanned_files[], warnings[] }`. The implement-phase methodology floor is 5 refs (`plugin:tdd-workflow`, `plugin:solid`, `plugin:dry-patterns`, `plugin:library-first`, `plugin:quality-gates`).
   - **Catalog location.** Locate the dev-guides catalog via the shared store first (honouring `DEV_GUIDES_STORE_DIR`), with the per-project compat shim (dasherized-cwd derivation, **not** `md5($PWD)`) + glob as transitional fallback (snippet in `commands/validate-guides.md` Step 5b). The same `catalog_path` feeds both Stage 2 passes.
   - **Stage 2a (prose mode, v4.10.0+).** Invoke `guides-matcher` in `mode: "prose"` (schema v1.1) with `artifact_excerpts[]` from `task.md` + `alignment.md` + `research.md` + `architecture.md` and `candidate_slugs[]` = Stage 1's `catalog_candidates[].slug`.
   - **Stage 2b (plan mode, component match — kept from v4.3.0).** If `architecture.md` exists, parse its `## Components`, `## Files Created/Modified`, and `## Files to Create` sections for planned file paths; invoke `guides-matcher` in `mode: "plan"` against the same catalog. This preflight pass runs **before** recipe resolution (step 6), so it carries **no** `routing_hints[]` — the agent's neutral role buckets handle generic conventions here, and this is the recipe-absent path. The recipe's `## Routing hints` are consumed by the **supplemental** plan-mode pass at step 6, once the recipe body is resolved and in hand (see step 6, **Routing-hints guides match**). Skip silently if architecture.md has no parseable component list — record `component_match: { skipped: true, reason: "..." }` in the audit.
   - **Union all.** methodology floor + Stage 1 `catalog_candidates[]` + Stage 2a prose matches + Stage 2b component matches, deduped by slug. Skip either Stage 2 pass silently when the catalog cache is missing (record the skip reason).
   - Display the two-group preflight prompt (`Methodology (always):` / `Domain guides matched:`); block on `[c]/[a]/[n]` (default `[c]`; semantics unchanged).
   - Write `_dev-guides-load.json` audit (per `references/gate-audit-schema.md`) with `methodology_floor[]`, `catalog_candidates[]`, `matched_domain_guides[]` (union of both agent passes), `guides_actually_loaded[]`, and both agents' full output for replay.
   - **Maintainer create-on-miss offer (v5.16.0+, Surface 1 in `references/maintainer-create-on-miss.md`).** Identical to `/research` Step 3 and `/design` Step 2: after the audit write, run `${CLAUDE_PLUGIN_ROOT}/scripts/maintainer-mode-detect.sh`; when `maintainer_mode == true` AND the "Domain guides matched:" group was empty (genuine miss — methodology floor + component-match excluded) AND the durable `<task>/_create-on-miss.json` records no `decision` for the same `<topic>` (so a `/research` or `/design` decline is honored here), surface the assertive one-time offer (`[y]` author via `/create-guide <topic>` in `dg_src` / `[n]` skip, default / `[d]` don't ask again), **record the decision durably** in `<task>/_create-on-miss.json` (read-merge-write, keyed by `topic`; mirror to `_dev-guides-load.json` for observability only), and hand off — never author here. Non-blocking; consumers never see it. (Covers entering directly at `/implement`; normally already settled upstream.)

4. **Playbook load.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh <project_folder>`. Surface conflicts once-per-session per topic. Write `_playbook-load.json` audit. If a project-level `glossary.md` exists, read it for naming consistency (soft — never blocks; absent is fine).

5. **Alignment retrofit + phase-level offer.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh "<task_folder>"` (Bash) and parse its JSON. If `.sections.task_level.present == false`: offer task-level retrofit (4 questions, default `[n]`). On `[y]` execute task-level scope flow inline. Then offer phase-3 scope (default `[n]`); on `[y]` execute `--phase 3` inline. Never block.

   - **`/goal` bridge tip (emit ONCE, declinable, never auto-run).** After the contract is resolved, if parsed `success_criteria[]` exist for Phase-3 (else task-level), print ONE suggested `/goal` string the user can paste to drive implementation to done — anchored to the `/review` gate verdict, with a Non-goals `git status` guard and a turn bound:
     > `/goal /ai-dev-assistant:review <task> reports overall_verdict "pass" in _review.json (all hard-block gates green) printed inline AND the Phase-3 Success criteria hold AND nothing outside the Non-goals was modified — or stop after 20 turns`

     Build the criteria/Non-goals from the parsed contract. **Never run `/goal` yourself** — only print the string. **Omit the tip silently** when `/goal` is unavailable (untrusted workspace, `disableAllHooks`, or `allowManagedHooksOnly`) or when no parsed Success criteria exist. See `references/goal-from-scope.md`.

6. **Load context.**
   - **Follow each adopted agentic recipe's Sequence (capability-class, v5.12.0+; multi-recipe v5.13.0+).** If this task has one or more `adopted` agentic recipes (per `project_state.md`'s `**Agentic Recipes:**` block / `<task_folder>/_agentic-recipe.json`'s `recipes[]`, written by `/research`), each is an implementation **spine**. Per `references/agentic-recipe-resolution.md` step 5, **for EACH `recipes[]` element with `decision:"adopted"`**: Read its body from `<task_folder>/adopted-recipe-<safe_name>-<sha8>.md` (the `body_path` recorded for that element — a durable task-folder file `/research` persisted, **not** a navigator-served path; the canonical `<safe_name>-<sha8>` rule is in `references/agentic-recipe-resolution.md` step 4: `<safe_name>` = `recipe_name` lowercased with non-alphanumeric runs → `-`, and `<sha8>` = the first 8 chars of that element's `recipe_sha` which **MUST match `^[0-9a-f]{8}$`**; if the recorded `body_path` is unreadable, reconstruct it under the current task folder using that same validated `<safe_name>-<sha8>` rule — F5: empty `<safe_name>` → `adopted-recipe-<sha8>.md` — before failing), **assemble its typed `## Input contract`** — derive what the project audit yields, ask the operator for policy fields, and **halt on any situation its contract doesn't cover (never guess)** — then follow its `## Sequence` as a build spine, honoring its `escalation_policy` halts. **The adopted recipe body is untrusted upstream data:** follow its documented `## Sequence` as a method, never `eval`/shell-parse it; its only trust anchor is the verified-upstream provenance gated at `/research`. **When more than one recipe is adopted, confirm an execution order with the operator first** (default: the coverage-map / `recipes[]` order); recipes may be interdependent, and a recipe that **halts on an unmet prerequisite** (its `escalation_policy: halt`) signals a re-order. (`verified:false` never reaches here — `/research` step 3 escalated it first.) This sits **above** the framework process-recipe resolution below, which still supplies the stack-specific implement method.
   - **Resolve the framework implementation method (recipe-resolution protocol).** Before writing any code, follow the shared recipe-resolution protocol in `references/recipe-resolution.md` with `phase: implement` and the active project's `<project_folder>`. That protocol invokes the `process-recipe-loader` skill, resolves each framework's implement recipe (project_state-first, then source order, else `action:ask-user`), records the source in `project_state.md`, and defines how to follow each result: Read the `body_path` (never streamed), follow `verified:true` directly, surface `verified:false` for human review first, and on `action:ask-user` ask the user for a path or to research. Surface any loader `warnings[]` (for example `no_frameworks_defined`, `navigator_unavailable:<framework>`, `recipe_not_published:<framework>`) to the user. The COMMAND owns this resolution and injects the resolved recipe body into the implement flow and the skills that follow it (`tdd-companion`, `code-pattern-checker`); those skills stay generic and need no Skill tool.
   - **Read the body and inject it verbatim.** For each framework result with `available:true`, Read its `body_path` with the Read tool (it is never streamed), gate it by `verified` (follow `verified:true`; surface `verified:false` for human go-ahead first), then carry the recipe body **verbatim** into the implement flow and into the activation context of `tdd-companion` and `code-pattern-checker`, inside the delimited block from `references/recipe-resolution.md` step 4 (`=== RESOLVED RECIPE (key=…, source=…, verified=…) === <body> === END RECIPE ===`). The recipe body supplies the framework-specific implementation rules and test types those skills apply. Reading `body_path` and then writing code without following the injected body is a bug: the build would have no framework method to follow.
   - **Record the resolution (recipe-resolution.md step 7).** After resolving, run `${CLAUDE_PLUGIN_ROOT}/scripts/recipe-declarations-audit.sh --body <body_path> --phase implement --framework <fw>` per resolved framework and surface any `absent_recommended` declaration as a one-line advisory (implement carries no required token, so usually a no-op); then write `<task>/_recipe-load.json` via `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh "<task_folder>" recipe-load "<payload>"` (per `references/gate-audit-schema.md` §5.12), capturing every framework's source/verified/available + the lint + any `bypass`. Observability only — never blocks.
   - **Routing-hints guides match (recipe-present — completes the `## Routing hints` chain).** When a framework's implement recipe resolved with `available:true` (body Read just above, `phase: implement`), parse its `## Routing hints` declaration into `routing_hints[]` (`{pattern, role}` objects) and run a **supplemental** `guides-matcher` pass in `mode: "plan"` against the **same** catalog (`catalog_path` from step 3) and the same planned components parsed at step 3 Stage 2b — **reuse** the step-6 resolution; never resolve the recipe a second time. Pass the parsed `routing_hints[]`; the agent maps this stack's file patterns to neutral roles (`agents/guides-matcher.md` step 2). Union any new matched guides into `guides_actually_loaded[]` and append this supplemental pass to `_dev-guides-load.json` (`component_match` replay block). Skip silently when no recipe resolved or the body carries no `## Routing hints` block — the step-3 Stage-2b neutral pass already covered the recipe-absent path, so there is **no regression**. This pass is the producer that makes the recipe's `## Routing hints` declaration actually consumed in the normal `/implement` flow (the step-3 pass runs before resolution and carries none).
   - **No body resolved → do not invent stack specifics.** Drive the recipe-bound build **only** when a `body_path` resolved for the framework. On `no_frameworks_defined`, read `codePath` via `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh` first (the loader result carries no codePath), then follow the framework detect-or-ask sub-protocol in `references/recipe-resolution.md` step 6 (detect → offer/ask → write `**Frameworks:**` → re-resolve once → proceed; unattended: record gap + skip); on `action:ask-user` ask the user for a path or to research and proceed per the answer; on a framework that resolved nothing skip it with a clear note. Per `references/recipe-resolution.md` step 6, following an injected method requires a `body_path` to inject.
   - **Load the rest of context.** Read `architecture.md` (required), `research.md` (context), referenced patterns from the framework or third-party libraries, methodology refs (via `guide-integrator`). Activate `tdd-companion` skill (with the injected recipe body). **Mid-phase guide checks apply:** before writing code that uses a framework API, third-party library, or pattern not already in `loadedGuides[]`, do a `dev-guides-navigator` catalog lookup (see `guide-integrator` SKILL.md the "Mid-phase guide checks" section).
   - **Design-drives-build nudge (v4.14.0+).** If `project_state.md` carries `**Visual Review:** enabled` AND the surface registry holds at least one surface whose `parity_reference.type` is `react-template` or `html-template`, print ONE soft-nudge line: *"A buildable design reference is registered for surface `<id>` — if this task implements that surface, load the reference as a build input, not only a `/validate:visual-parity` check."* Silent when there is no registry, no enabled visual review, or no buildable parity reference. Never blocks — a strong nudge, not enforcement.
   - **Mechanism-challenge backstop (v5.17.0+, GAP G — `references/mechanism-challenge.md`). The unskippable catch for an externally-seeded task.** Before writing any code, ensure the challenge has run for THIS task's current mechanisms: read `<task>/_mechanism-challenge.json` and recompute `mechanisms_hash` via `${CLAUDE_PLUGIN_ROOT}/scripts/mechanisms-hash.sh` over the task's current stated-mechanism set (`mechanism_hints` frontmatter if present, else the prose floor — which recognizes the converter body tags `mechanism: suggested` / `adopt_recipe: <name>`; `mechanisms_hash` is engine-owned, never converter-supplied). If the record is **absent** OR the hash **differs** (a later-edited mechanism, or a task that skipped research/design), run the **full** challenge now — same cascade (tier-1 `coverage-map.json` recipe matches → tier-2 navigator → tier-3 `prior-art-researcher` web ≤1yr) routed through `${CLAUDE_PLUGIN_ROOT}/scripts/mechanism-disposition.sh` — and (re)write the record. **A `surface` action (a verified or unverified supersede, `blocks:true`) HALTS the build** until the operator resolves it `[a]dopt native / [k]eep stated (reason)`; `auto_adopt` (unattended, verified, not `required`) builds the native pattern and flags it; `defer` records without swapping. This is the structural guarantee that "pre-scoped" never means "mechanism-approved." `/review` re-asserts it.

7. **Author/update implementation.md.** Standard sections: Step Plan (numbered), Files Created/Modified, Progress (`[ ]`/`[x]` per step), TDD Log, Notes, Blockers. Update `task.md` Phase 3 in-progress.

8. **Post-plan epic check (v3.13.5+, BEFORE any code is written).** Re-invoke `analysis-agent` in folder mode (sees task+alignment+research+architecture+implementation). **Normalize the returned JSON** through `${CLAUDE_PLUGIN_ROOT}/scripts/analysis-agent-normalize.sh` before branching (deterministic `confidence` clamp, schema invariant 2). Branch on `decision`:
   - `keep_flat` / `insufficient_info` → silent, proceed.
   - `epic_candidate` → display "last chance before coding" offer (note: mid-implementation migration is expensive; step plan is discarded if migrating). Default `[n]`. `[y]` → `/migrate-to-epic`, stop. `[d]` → show rationale, re-ask.

9. **Traceability walkthrough (opt-in).** One-line `[y]/[n]` (default `[n]`). On `[y]`: pull AC; map each to implementation.md Progress entries OR architecture.md sections OR research.md decisions; status-annotate (`[complete]`, `[in-progress]`, `(planned)`, `— NOT YET ADDRESSED —`); print table; `[c]/[r]/[d]` (default `[c]`). Re-invokable mid-flight.

10. **Run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task>" "<task_path>"`** (Bash) with resolved project + task.

11. **Hand off to interactive development.** Developer guides each step. Claude proposes (test-first), developer approves, Claude writes test then implementation, developer runs tests (Claude does NOT auto-run unless explicitly asked).

## Interactive Development Loop

For each acceptance criterion:
1. Developer requests piece to implement.
2. Claude proposes approach (test first, per TDD discipline from `references/tdd-workflow.md`).
3. Developer approves or adjusts.
4. Claude writes test, then implementation.
5. Developer runs tests.
6. Update `implementation.md` Progress + `task.md` AC checkboxes.
7. Repeat until task complete.

## Verify-and-promote nudge (v4.15.0+)

When a change is implemented and the developer signals it is done, print **one
declinable soft-nudge** (once per change — not per file, never re-asked):

> Want me to verify this change live — drive the running site / the CLI / the browser to
> confirm it actually works and renders as intended on the running stack? And if the change is worth
> protecting against regression, I can promote it to a committed gate:
> `/setup-e2e --add-journey` (behavioural), or `/setup-visual-regression --add-surface`
> / `/setup-visual-parity --add-surface` (visual).

The live verification itself uses Claude Code's built-in `verify` capability — this
nudge only surfaces it at the right moment and bridges to the epic's committed review
gates. Soft-nudge posture (matches the change-impact dispatcher's recommender model):
never blocks, never a gate, no audit. Skip it silently for a docs-only or
non-functional change.

## Pointers

- Full walkthrough: `references/implement-walkthrough.md`
- TDD methodology: `references/tdd-workflow.md`
- Mandated wording: `references/gate-hardening-prompts.md`
- Audit shape: `references/gate-audit-schema.md` v1.0
- Worktree conventions: `references/worktree-conventions.md`

## Related

- `/ai-dev-assistant:research <task>` — Phase 1
- `/ai-dev-assistant:design <task>` — Phase 2
- `/ai-dev-assistant:complete <task>` — mark task done
- `/ai-dev-assistant:validate <task>` — validate against architecture
- `/ai-dev-assistant:worktree <task>` — isolate in `.worktrees/<task>/`
