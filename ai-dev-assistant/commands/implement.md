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
   - **Stage 1 (deterministic).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh <task_folder> --phase implement` → `{ methodology_floor[], catalog_candidates[], scanned_files[], warnings[] }`. The implement-phase methodology floor is 5 refs (`plugin:tdd-workflow`, `plugin:solid-drupal`, `plugin:dry-patterns`, `plugin:library-first`, `plugin:quality-gates`).
   - **Cache location.** Locate the dev-guides catalog cache via the dasherized-cwd derivation + glob fallback (snippet in `commands/validate-guides.md` Step 5b — **not** `md5($PWD)`). The same `catalog_path` feeds both Stage 2 passes.
   - **Stage 2a (prose mode, v4.10.0+).** Invoke `guides-matcher` in `mode: "prose"` (schema v1.1) with `artifact_excerpts[]` from `task.md` + `alignment.md` + `research.md` + `architecture.md` and `candidate_slugs[]` = Stage 1's `catalog_candidates[].slug`.
   - **Stage 2b (plan mode, component match — kept from v4.3.0).** If `architecture.md` exists, parse its `## Components`, `## Files Created/Modified`, and `## Files to Create` sections for planned file paths; invoke `guides-matcher` in `mode: "plan"` against the same catalog. Skip silently if architecture.md has no parseable component list — record `component_match: { skipped: true, reason: "..." }` in the audit.
   - **Union all.** methodology floor + Stage 1 `catalog_candidates[]` + Stage 2a prose matches + Stage 2b component matches, deduped by slug. Skip either Stage 2 pass silently when the catalog cache is missing (record the skip reason).
   - Display the two-group preflight prompt (`Methodology (always):` / `Domain guides matched:`); block on `[c]/[a]/[n]` (default `[c]`; semantics unchanged).
   - Write `_dev-guides-load.json` audit (per `references/gate-audit-schema.md`) with `methodology_floor[]`, `catalog_candidates[]`, `matched_domain_guides[]` (union of both agent passes), `guides_actually_loaded[]`, and both agents' full output for replay.

4. **Playbook load.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh <project_folder>`. Surface conflicts once-per-session per topic. Write `_playbook-load.json` audit.

5. **Alignment retrofit + phase-level offer.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh "<task_folder>"` (Bash) and parse its JSON. If `.sections.task_level.present == false`: offer task-level retrofit (4 questions, default `[n]`). On `[y]` execute task-level scope flow inline. Then offer phase-3 scope (default `[n]`); on `[y]` execute `--phase 3` inline. Never block.

   - **`/goal` bridge tip (emit ONCE, declinable, never auto-run).** After the contract is resolved, if parsed `success_criteria[]` exist for Phase-3 (else task-level), print ONE suggested `/goal` string the user can paste to drive implementation to done — anchored to the `/review` gate verdict, with a Non-goals `git status` guard and a turn bound:
     > `/goal /ai-dev-assistant:review <task> reports overall_verdict "pass" in _review.json (all hard-block gates green) printed inline AND the Phase-3 Success criteria hold AND nothing outside the Non-goals was modified — or stop after 20 turns`

     Build the criteria/Non-goals from the parsed contract. **Never run `/goal` yourself** — only print the string. **Omit the tip silently** when `/goal` is unavailable (untrusted workspace, `disableAllHooks`, or `allowManagedHooksOnly`) or when no parsed Success criteria exist. See `references/goal-from-scope.md`.

6. **Load context.** Read `architecture.md` (required), `research.md` (context), referenced patterns from the framework or third-party libraries *(Drupal: core/contrib)*, methodology refs (via `guide-integrator`). Activate `tdd-companion` skill. **Mid-phase guide checks apply:** before writing code that uses a framework API, third-party library, or pattern not already in `loadedGuides[]` (Drupal: a Drupal API or contrib module), do a `dev-guides-navigator` catalog lookup (see `guide-integrator` SKILL.md the "Mid-phase guide checks" section).
   - **Design-drives-build nudge (v4.14.0+).** If `project_state.md` carries `**Visual Review:** enabled` AND the surface registry holds at least one surface whose `parity_reference.type` is `react-template` or `html-template`, print ONE soft-nudge line: *"A buildable design reference is registered for surface `<id>` — if this task implements that surface, load the reference as a build input, not only a `/validate:visual-parity` check."* Silent when there is no registry, no enabled visual review, or no buildable parity reference. Never blocks — a strong nudge, not enforcement.

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
> confirm it actually works and renders as intended *(Drupal: the DDEV site, `drush`)*? And if the change is worth
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
