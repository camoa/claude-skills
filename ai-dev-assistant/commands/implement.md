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

0. **Declare the active phase (v5.29.0+).** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase-active-write.sh" implement "<task_folder>"` (Bash) **before writing anything**. The phase-command-bypass guardrail compares the artifact being written against the phase that declared itself; with nothing declared it can only report `undetermined`, which is what it did on every task until this call existed. Run it at entry, not at the end — an artifact written before the declaration is indistinguishable from one written outside the phase command. **Pass the task folder.** The session file the declaration also lands in is deleted by the SessionStart hook, so a resume or a compact mid-phase wipes it; the task-folder copy is what survives.

1. **Phase Transition Check.** Read `task.md` Phase Status. Evaluate Phases 1 and 2 independently:
   - Phase 2 not `[x]` → print one-line soft-nudge ("Phase 2 not complete; consider `/ai-dev-assistant:design <task>` first.").
   - Phase 1 not `[x]` → print one-line soft-nudge ("Phase 1 not complete; running `/implement` without research is unusual.").
   - Both `[x]` → silent.
   Never block.
   - **Coverage read (v5.44.0+).** Read `<task>/_coverage.json` (`gate_specific.status`), the design-close coverage gate's record. `fail` → HALT before the first component opens: `[o]verride <reason>` records the reason as `bypass_reason` on that record and proceeds; nothing else does. `not_run` → print its `reason` (`no_ids`: run `/scope`; forward-only on a task designed before ids) and proceed. `pass` / `not_applicable` → silent. Absent → the design never closed through the gate; print that and proceed, it is not a pass. **Record the read on every path**, so a build can show the check happened: set `gate_specific.coverage_read` to `{status: "<what you read>|absent", at: "<iso>"}` on `_coverage.json` (whole record back through `gate-audit-write.sh`, every other key preserved; write it to `<task>/_coverage.json` yourself when the record is absent, with `status: "not_run"`, `reason: "no_design_gate"`). Without it a pass and a preflight that never ran leave the task folder identical, and the override is the only auditable path.

2. **Worktree signals (v3.16.0+).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-signals.sh "<project_folder>" "<task_name>"` (Bash). **Both arguments are required** — `<project_folder>` is the task's project folder, not the code repository, and a one-argument call fails. On HIGH-strength signal (`another_task_active`, `dirty_tree`, `--worktree` flag, or `worktreeByDefault: true`), print soft-nudge offering `/worktree <task>`. `dirty_tree` counts uncommitted changes to **tracked** files only; untracked files are reported in `signal_details` and never fire it. Suppress when already inside a worktree. Never block.

2b. **Work-order build-path offer (v4.19.0+, conditional).** Check whether `<task>/work-orders/wo-*.md` exist (Bash glob). **SILENT when absent — do not print anything if no work-orders are found.** When files are found, print ONE soft-nudge:

> 💡 Work-orders found for this task. Build via independent agents? `/ai-dev-assistant:run-work-orders <task>` (requires a worktree) runs each WO in isolation, with an adversarial critique per work-order. `[y]` → hand off to `/run-work-orders`; `[n]` (default) — continue in-session, where the build-critique rung critiques per architecture component instead. Either way the build is challenged. See `references/work-order-lifecycle.md` and `references/build-critique.md`.

Default `[n]` — continue to step 3 (dev-guides preflight) and the Interactive Development Loop unchanged. The in-session default behavior is not altered by this check.

**Say what each path includes, and do not sell isolation alone.** Before v5.33.0 this nudge offered the upside of the work-order path and never mentioned that `[n]` also declined `wo-critic`, the only adversarial review that existed before Phase 4. A task took the default for good reasons and its whole build went unchallenged, which nobody chose and nothing recorded. The in-session path now carries its own critique rung, so the choice is about isolation and parallelism rather than about whether the work gets reviewed.

3. **Dev-guides preflight (two-stage + component-aware, v4.10.0+).** Stage 1 deterministic; Stage 2 in two agent passes (prose + component file-path). See `/research` step 3 for the shared two-stage description.
   - **Stage 1 (deterministic).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh <task_folder> --phase implement` → `{ methodology_floor[], catalog_candidates[], scanned_files[], warnings[] }`. The implement-phase methodology floor is 5 refs (`plugin:tdd-workflow`, `plugin:solid`, `plugin:dry-patterns`, `plugin:library-first`, `plugin:quality-gates`).
   - **Catalog location.** Locate the dev-guides catalog via the shared store first (honouring `DEV_GUIDES_STORE_DIR`), with the per-project compat shim (dasherized-cwd derivation, **not** `md5($PWD)`) + glob as transitional fallback (snippet in `commands/validate-guides.md` Step 5b). The same `catalog_path` feeds both Stage 2 passes.
   - **Stage 2a (prose mode, v4.10.0+).** Invoke `ai-dev-assistant:guides-matcher` in `mode: "prose"` (schema v1.1), handing it `<task_folder>/_guides-match-<mode>.json` as its output path and reading the match set off that file on this and every pass below; an absent file is `no_return` in `prose_match`, never an empty match set. With `artifact_excerpts[]` from `task.md` + `alignment.md` + `research.md` + `architecture.md` and `candidate_slugs[]` = Stage 1's `catalog_candidates[].slug`.
   - **Stage 2b (plan mode, component match — kept from v4.3.0).** If `architecture.md` exists, parse its `## Components`, `## Files Created/Modified`, and `## Files to Create` sections for planned file paths; invoke `ai-dev-assistant:guides-matcher` in `mode: "plan"` against the same catalog. This preflight pass runs **before** recipe resolution (step 6), so it carries **no** `routing_hints[]` — the agent's neutral role buckets handle generic conventions here, and this is the recipe-absent path. The recipe's `## Routing hints` are consumed by the **supplemental** plan-mode pass at step 6, once the recipe body is resolved and in hand (see step 6, **Routing-hints guides match**). Skip silently if architecture.md has no parseable component list — record `component_match: { skipped: true, reason: "..." }` in the audit.
   - **Union all.** methodology floor + Stage 1 `catalog_candidates[]` + Stage 2a prose matches + Stage 2b component matches, deduped by slug. Skip either Stage 2 pass silently when the catalog cache is missing (record the skip reason).
   - Render the preflight prompt with `${CLAUDE_PLUGIN_ROOT}/scripts/prompt-render.sh dev-guides-preflight task_name=… methodology_floor=… matched_domain_guides=…` (Bash) and show exactly what it printed — no retyping, no relabelled groups, no heading above it; block on `[c]/[a]/[n]` (default `[c]`; semantics unchanged).
   - Write `_dev-guides-load.json` audit (per `references/gate-audit-schema.md`) with `phase: "implement"`, `methodology_floor[]`, `catalog_candidates[]`, `matched_domain_guides[]` (union of both agent passes), `guides_actually_loaded[]`, and both agents' full output for replay. **`phase` is a required key of this payload** — `_dev-guides-load.json` is attributed to the phase that wrote it, and a payload without it both warns at the write and reads as unattributed at the end-of-phase records check.
   - **Maintainer create-on-miss offer (v5.16.0+, Surface 1 in `references/maintainer-create-on-miss.md`).** Identical to `/research` Step 3 and `/design` Step 2: after the audit write, run `${CLAUDE_PLUGIN_ROOT}/scripts/maintainer-mode-detect.sh`; when `maintainer_mode == true` AND **the Surface 1 trigger in `references/maintainer-create-on-miss.md` holds** — a load-bearing aspect in `coverage-map.json` `uncovered_aspects[]` that no guide covers, falling back to the whole-task union test only when no coverage map is readable AND the durable `<task>/_create-on-miss.json` records no `decision` for the same `<topic>` (so a `/research` or `/design` decline is honored here), surface the assertive one-time offer (`[y]` author via `/create-guide <topic>` in `dg_src` / `[n]` skip, default / `[d]` don't ask again), **record the decision durably** in `<task>/_create-on-miss.json` (read-merge-write, keyed by `topic`; mirror to `_dev-guides-load.json` for observability only), and hand off — never author here. Non-blocking; consumers never see it. (Covers entering directly at `/implement`; normally already settled upstream.)

4. **Playbook load.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh <project_folder>` (Bash). **The script prints the `gate_specific` object on stdout; it does not write the audit** — it is handed a project folder and has no way to know which task is active. Capture that stdout and write the record yourself: `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh "<task_folder>" playbook-load "<the payload, with `phase: "implement"` added>"`. **`phase` is not optional here** — `_playbook-load.json` is attributed to the phase that wrote it, so a payload without it reads as unattributed at the end-of-phase records check, a long way from the cause. Leaving the output on stdout leaves no record at all, and the phase fails its own records check. Surface conflicts once-per-session per topic. If a project-level `glossary.md` exists, read it for naming consistency (soft — never blocks; absent is fine).

5. **Alignment retrofit + phase-level offer.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh "<task_folder>"` (Bash) and parse its JSON. If `.sections.task_level.present == false`: offer task-level retrofit (4 questions, default `[n]`). **Render it:** `${CLAUDE_PLUGIN_ROOT}/scripts/prompt-render.sh scope-contract-offer task_name="<task_name>" level="this task"` (Bash), and show exactly what it printed. Never substitute your own wording, and never name an internal file or a phase number to the person. On `[y]` execute task-level scope flow inline. Then offer the implementation-phase scope (default `[n]`, same script with `level="the implementation phase"`); on `[y]` execute `--phase 3` inline. Never block.

   - **`/goal` bridge tip (emit ONCE, declinable, never auto-run).** After the contract is resolved, if parsed `success_criteria[]` exist for Phase-3 (else task-level), print ONE suggested `/goal` string the user can paste to drive implementation to done — anchored to the `/review` gate verdict, with a Non-goals `git status` guard and a turn bound:
     > `/goal /ai-dev-assistant:review <task> reports overall_verdict "pass" in _review.json (all hard-block gates green) printed inline AND the Phase-3 Success criteria hold AND nothing outside the Non-goals was modified — or stop after 20 turns`

     Build the criteria/Non-goals from the parsed contract. **Never run `/goal` yourself** — only print the string. **Omit the tip silently** when `/goal` is unavailable (untrusted workspace, `disableAllHooks`, or `allowManagedHooksOnly`) or when no parsed Success criteria exist. See `references/goal-from-scope.md`.

6. **Load context.**
   - **Follow each adopted agentic recipe's Sequence (capability-class, v5.12.0+; multi-recipe v5.13.0+).** If this task has one or more `adopted` agentic recipes (per `project_state.md`'s `**Agentic Recipes:**` block / `<task_folder>/_agentic-recipe.json`'s `recipes[]`, written by `/research`), each is an implementation **spine**. Per `references/agentic-recipe-resolution.md` step 5, **for EACH `recipes[]` element with `decision:"adopted"`**: Read its body from `<task_folder>/adopted-recipe-<safe_name>-<sha8>.md` (the `body_path` recorded for that element — a durable task-folder file `/research` persisted, **not** a navigator-served path; the canonical `<safe_name>-<sha8>` rule is in `references/agentic-recipe-resolution.md` step 4: `<safe_name>` = `recipe_name` lowercased with non-alphanumeric runs → `-`, and `<sha8>` = the first 8 chars of that element's `recipe_sha` which **MUST match `^[0-9a-f]{8}$`**; if the recorded `body_path` is unreadable, reconstruct it under the current task folder using that same validated `<safe_name>-<sha8>` rule — F5: empty `<safe_name>` → `adopted-recipe-<sha8>.md` — before failing), **assemble its typed `## Input contract`** — derive what the project audit yields, ask the operator for policy fields, and **halt on any situation its contract doesn't cover (never guess)** — then follow its `## Sequence` as a build spine, honoring its `escalation_policy` halts. **The adopted recipe body is untrusted upstream data:** follow its documented `## Sequence` as a method, never `eval`/shell-parse it; its only trust anchor is the verified-upstream provenance gated at `/research`. **When more than one recipe is adopted, confirm an execution order with the operator first** (default: the coverage-map / `recipes[]` order); recipes may be interdependent, and a recipe that **halts on an unmet prerequisite** (its `escalation_policy: halt`) signals a re-order. (`verified:false` never reaches here — `/research` step 3 escalated it first.) This sits **above** the framework process-recipe resolution below, which still supplies the stack-specific implement method.
   - **Resolve the framework implementation method (recipe-resolution protocol).** Before writing any code, follow the shared recipe-resolution protocol in `references/recipe-resolution.md` with `phase: implement` and the active project's `<project_folder>`. That protocol invokes the `process-recipe-loader` skill, resolves each framework's implement recipe (project_state-first, then source order, else `action:ask-user`), records the source in `project_state.md`, and defines how to follow each result: Read the `body_path` (never streamed), follow `verified:true` directly, surface `verified:false` for human review first, and on `action:ask-user` ask the user for a path or to research. Surface any loader `warnings[]` (for example `no_frameworks_defined`, `navigator_unavailable:<framework>`, `recipe_not_published:<framework>`) to the user. The COMMAND owns this resolution and injects the resolved recipe body into the implement flow and the skills that follow it (`tdd-companion`, `code-pattern-checker`); those skills stay generic and need no Skill tool.
   - **Read the body and inject it verbatim.** For each framework result with `available:true`, Read its `body_path` with the Read tool (it is never streamed), gate it by `verified` (follow `verified:true`; surface `verified:false` for human go-ahead first), then carry the recipe body **verbatim** into the implement flow and into the activation context of `tdd-companion` and `code-pattern-checker`, inside the delimited block from `references/recipe-resolution.md` step 4 (`=== RESOLVED RECIPE (key=…, source=…, verified=…) === <body> === END RECIPE ===`). The recipe body supplies the framework-specific implementation rules and test types those skills apply. Reading `body_path` and then writing code without following the injected body is a bug: the build would have no framework method to follow.
   - **Record the resolution (recipe-resolution.md step 7).** After resolving, run `${CLAUDE_PLUGIN_ROOT}/scripts/recipe-declarations-audit.sh --body <body_path> --phase implement --framework <fw>` per resolved framework and surface any `absent_recommended` declaration as a one-line advisory (implement carries no required token, so usually a no-op); then write `<task>/_recipe-load.json` via `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh "<task_folder>" recipe-load "<payload>"` (per `references/gate-audit-schema.md` §5.12), capturing every framework's source/verified/available + the lint + any `bypass`. Observability only — never blocks.
   - **Routing-hints guides match (recipe-present — completes the `## Routing hints` chain).** When a framework's implement recipe resolved with `available:true` (body Read just above, `phase: implement`), parse its `## Routing hints` declaration into `routing_hints[]` (`{pattern, role}` objects) and run a **supplemental** `guides-matcher` pass in `mode: "plan"` against the **same** catalog (`catalog_path` from step 3) and the same planned components parsed at step 3 Stage 2b — **reuse** the step-6 resolution; never resolve the recipe a second time. Pass the parsed `routing_hints[]`; the agent maps this stack's file patterns to neutral roles (`agents/guides-matcher.md` step 2). Union any new matched guides into `guides_actually_loaded[]` and append this supplemental pass to `_dev-guides-load.json` (`component_match` replay block). Skip silently when no recipe resolved or the body carries no `## Routing hints` block — the step-3 Stage-2b neutral pass already covered the recipe-absent path, so there is **no regression**. This pass is the producer that makes the recipe's `## Routing hints` declaration actually consumed in the normal `/implement` flow (the step-3 pass runs before resolution and carries none).
   - **No body resolved → do not invent stack specifics.** Drive the recipe-bound build **only** when a `body_path` resolved for the framework. On `no_frameworks_defined`, read `codePath` via `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh` first (the loader result carries no codePath), then follow the framework-resolution branch in `references/recipe-resolution.md` step 6, which runs the cascade in `references/framework-resolution.md` (identify the framework by reading the repository → check what the catalogs carry for it → ask the user → research → record `_framework.json` and write `**Frameworks:**` → re-resolve once → proceed; unattended: record gap + skip); on `action:ask-user` ask the user for a path or to research and proceed per the answer; on a framework that resolved nothing skip it with a clear note. Per `references/recipe-resolution.md` step 6, following an injected method requires a `body_path` to inject.
   - **Load the rest of context.** Read `architecture.md` (required), `research.md` (context), referenced patterns from the framework or third-party libraries, methodology refs (via `guide-integrator`). Activate `tdd-companion` skill (with the injected recipe body). **Mid-phase guide checks apply:** before writing code that uses a framework API, third-party library, or pattern not already in `loadedGuides[]`, do a `dev-guides-navigator` catalog lookup (see `guide-integrator` SKILL.md the "Mid-phase guide checks" section).
   - **Design-drives-build nudge (v4.14.0+).** If `project_state.md` carries `**Visual Review:** enabled` AND the surface registry holds at least one surface whose `parity_reference.type` is `react-template` or `html-template`, print ONE soft-nudge line: *"A buildable design reference is registered for surface `<id>` — if this task implements that surface, load the reference as a build input, not only a `/validate:visual-parity` check."* Silent when there is no registry, no enabled visual review, or no buildable parity reference. Never blocks — a strong nudge, not enforcement.
   - **Mechanism-challenge backstop (v5.17.0+, GAP G — `references/mechanism-challenge.md`). The unskippable catch for an externally-seeded task.** Before writing any code, ensure the challenge has run for THIS task's current mechanisms: read `<task>/_mechanism-challenge.json` and recompute `mechanisms_hash` via `${CLAUDE_PLUGIN_ROOT}/scripts/mechanisms-hash.sh` over the task's current stated-mechanism set (`mechanism_hints` frontmatter if present, else the prose floor — which recognizes the converter body tags `mechanism: suggested` / `adopt_recipe: <name>`; `mechanisms_hash` is engine-owned, never converter-supplied). If the record is **absent** OR the hash **differs** (a later-edited mechanism, or a task that skipped research/design), run the **full** challenge now — same cascade (tier-1 `coverage-map.json` recipe matches → tier-2 navigator → tier-3 `prior-art-researcher` web ≤1yr). **This backstop is where a tier is most likely to genuinely not have run:** a task that skipped research/design has no `coverage-map.json` to seed tier-1, and the navigator or recipe index may be unavailable here too. Pass `--grounding not_searched` for any tier that did not run (missing `coverage-map.json`, index or navigator unavailable, `prior-art-researcher` returning `no_return`), never `--grounding none`: `none` is only for a cascade that ran to the end and found no superseding pattern. Route the result through `${CLAUDE_PLUGIN_ROOT}/scripts/mechanism-disposition.sh` and (re)write the record. **A `surface` action (a verified or unverified supersede, `blocks:true`) HALTS the build** until the operator resolves it `[a]dopt native / [k]eep stated (reason)`; `auto_adopt` (unattended, verified, not `required`) builds the native pattern and flags it; `defer` records without swapping. This is the structural guarantee that "pre-scoped" never means "mechanism-approved." `/review` re-asserts it.

6b. **Preconditions gate (v5.31.0+, fail-closed — `references/recipe-interface.md` §6).** Before writing any code, for each framework whose implement recipe resolved with `available:true` at step 6, run `${CLAUDE_PLUGIN_ROOT}/scripts/preconditions-check.sh --body <body_path> --phase implement --framework <fw> --cwd <codePath>` (Bash) and write the result via `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh "<task_folder>" preconditions "<the payload, with `phase: "implement"` added>"`.
   - **`unmet` HALTS the build.** Print each unmet entry's `what` and its `owner`, and hand off to that owner rather than satisfying it by hand. `[f]ix via the named owner` / `[o]verride (reason, recorded in `bypass_reason`)`. Building on top of an unmet precondition is what the gate exists to stop: a project with no test runner cannot observe a RED step fail, so test-first becomes unfalsifiable.
   - **`unknown` is not `met`, and neither is `undeclared`.** `unknown` (a check that could not run) prints one advisory line naming the entry and its reason and does not block. `undeclared` (the recipe carries no `## Preconditions` block) is recorded as such and never reported as "preconditions met" — the recipe declared nothing, so nothing was checked.
   - **Never satisfy a precondition by improvising.** When an unmet entry names no `owner`, or no recipe resolved at all, use the default owner table in `references/implement-walkthrough.md` ("Who owns the tooling"). Installing a linter, a test runner, or a dependency-advisory scan by hand duplicates a plugin that already owns it, and was observed doing exactly that on a live run.
   - Skip silently when no framework recipe resolved (nothing declares preconditions); record `verdict: "undeclared"` when a recipe resolved but carries no block.

7. **Author/update implementation.md.** Standard sections: Step Plan (numbered), Files Created/Modified, Progress (`[ ]`/`[x]` per step), TDD Log, Notes, Blockers. Update `task.md` Phase 3 in-progress.

8. **Post-plan epic check (v3.13.5+, BEFORE any code is written).** Re-invoke `ai-dev-assistant:analysis-agent` in folder mode (sees task+alignment+research+architecture+implementation), handing it `<task_folder>/_analysis-folder.json` as its output path and reading its verdict off that file. An absent or unreadable file is `no_return`: record it and treat the decision as `insufficient_info`, never `keep_flat`, because an agent that said nothing and an agent that judged the task flat are not the same answer (`references/gate-audit-schema.md`). **Normalize the returned JSON** through `printf '%s' "<the agent's JSON>" | ${CLAUDE_PLUGIN_ROOT}/scripts/analysis-agent-normalize.sh -` (a file path works in place of `-`; the argument is **required** — called bare it prints its usage and normalizes nothing) before branching, and **read its exit code**: `2` means the agent delivered nothing, so record `no_return` and take `insufficient_info` (`references/analysis-agent-schema.md`). Branch on `decision`:
   - `keep_flat` / `insufficient_info` → silent, proceed.
   - `epic_candidate` → display "last chance before coding" offer (note: mid-implementation migration is expensive; step plan is discarded if migrating). Default `[n]`. `[y]` → `/migrate-to-epic`, stop. `[d]` → show rationale, re-ask.

9. **Traceability walkthrough (opt-in).** One-line `[y]/[n]` (default `[n]`). On `[y]`: pull AC; map each to implementation.md Progress entries OR architecture.md sections OR research.md decisions; status-annotate (`[complete]`, `[in-progress]`, `(planned)`, `— NOT YET ADDRESSED —`); print table; `[c]/[r]/[d]` (default `[c]`). Re-invokable mid-flight.

10. **Run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task>" "<task_path>"`** (Bash) with resolved project + task.

11. **Open the phase boundary, then hand off to interactive development.** First run
    `${CLAUDE_PLUGIN_ROOT}/scripts/build-checkpoint.sh capture --repo <codePath> --label phase.before`
    (Bash) and keep the `.sha` — Runtime Step 12's alignment axis diffs against it, and a
    boundary captured after the code exists measures nothing. Then run
    `${CLAUDE_PLUGIN_ROOT}/scripts/contract-baseline.sh capture "<task_folder>"`, which freezes
    `alignment.md` and `architecture/` as they stand before any code is written. The task folder
    is not a git repository, so the checkpoint above cannot cover it, and without this the
    critics judging scope read whatever the design says at critique time — including text the
    builder wrote to describe code it had already written. Re-capture is refused by design.
    Then hand off: developer guides
    each step, Claude proposes (test-first), developer approves, Claude writes test then
    implementation, developer runs tests (Claude does NOT auto-run unless explicitly asked).

    **The Interactive Development Loop below is part of this step**, including its build-critique
    rung at loop step 8. The loop exits into Runtime Step 12, which closes the phase. A build that
    reaches the end of the loop and stops has not finished the phase.

12. **Close the phase.** The alignment axis, the record, the records check, and clearing the
    checkpoints. Defined in full under "Runtime Step 12" below, after the loop it follows.

## Interactive Development Loop

The unit of BUILDING is an acceptance criterion. The unit of CRITIQUE is an architecture
component (`/design` writes one `architecture/<component>.md` per component, each carrying
its own acceptance criteria). Those are different units on purpose, and step 0 below is what
joins them: a component is critiqued when its criteria are all built, not once per criterion.

0. **Open the component.** Before writing the first line of a component's code:
   `${CLAUDE_PLUGIN_ROOT}/scripts/build-checkpoint.sh capture --repo <codePath> --label <component>.before`
   Keep the `.sha`. A flat `architecture.md` with no component files is one component named `main`.
1. Developer requests piece to implement.
2. Claude proposes approach (test first, per TDD discipline from `references/tdd-workflow.md`).
3. Developer approves or adjusts.
4. Claude writes the test. **Then the test is run and the failure is watched, before any
   implementation exists.** Who runs it follows `run_mode` (`references/tdd-workflow.md`, "Who
   runs the tests"): attended, Claude gives the exact command and the developer reports back;
   autonomous, the agent runs it, because there is nobody else to. Record the outcome for this
   criterion as `observed`, `passed_first_run` (the test is wrong; fix it before writing code)
   or `unobserved` with a reason. Then write the implementation.
5. Developer runs tests (GREEN).
6. Update `implementation.md` Progress + `task.md` AC checkboxes.
7. Repeat 1-6 until this component's acceptance criteria are built.
8. **Close the component: run the build-critique rung below.** It is not optional and not a
   nudge. A `critical` stops this component here.
9. Repeat 0-8 for the next component. When the last one closes, go to Runtime Step 12.

### The build-critique rung (v5.33.0+) — full contract `references/build-critique.md`

Runs at loop step 8, once per component. Every command below is a real invocation; the
scripts are the existing work-order critique kernels and their flags are not optional.

```
CD=<task_folder>/build-critique
mkdir -p "$CD/<component>.critics"

# 1. the boundary
AFTER=$(${CLAUDE_PLUGIN_ROOT}/scripts/build-checkpoint.sh capture --repo <codePath> \
          --label <component>.after | jq -r .sha)

# 2. the realized file list, which is what the classifier takes (it has no rev-range input)
# ROUND 1 diffs from <component>.before. EVERY LATER ROUND diffs from the PREVIOUS ROUND's
# .after, not from the component base. A repair round that re-diffs the whole component hands
# three critics ~670 lines they already reviewed, and they find new things in old code every
# time — findings accumulate instead of converging. Measured live: five rounds re-diffed from
# base and none was clean; the sixth scoped to the delta and was the first non-blocking round
# of the six. Keep each round's .after sha; the next round's base is that sha.
git -C <codePath> diff --name-only <base-sha-for-this-round>..$AFTER > "$CD/<component>.files.txt"

# 2c. test motion, on EVERY build, not only on repairs. The kernel is general and had one caller,
# the repair path, so a test modified during the initial build was classified only if the component
# later entered a repair round. Globs come from the recipe's `## Oracle files` row, else the project
# convention, and the origin is recorded; --suite is the result you hold for this component's own spec.
git -C <codePath> diff --name-status <base-sha-for-this-round>..$AFTER > "$CD/<component>.motion.txt"
G=$(${CLAUDE_PLUGIN_ROOT}/scripts/oracle-globs.sh --body <body_path> --fallback-globs '<convention, JSON array>') || exit 2   # no body_path: skip this call, pass --test-globs-source undetermined below
case "$(jq -r .origin <<<"$G")" in recipe|convention) GF=--test-globs-origin; GV=$(jq -r .origin <<<"$G") ;; *) GF=--test-globs-source; GV=undetermined ;; esac
${CLAUDE_PLUGIN_ROOT}/scripts/repair-accept-check.sh --suite <green|red|not_run> --test-motion-from "$CD/<component>.motion.txt" \
  --test-globs "$(jq -c .globs <<<"$G")" "$GF" "$GV" [--modification-reason "<why a test changed>"] > "$CD/<component>.motion.json" || exit 2
jq -r '"motion: \(.action) (\(.decided_by)): \(.reasons|join("; "))"' "$CD/<component>.motion.json"   # SAY IT, and record it on the component row as `motion`
# A modification with no reason SURFACES here as not_accepted (blocks:false), before any repair; adds and deletes alone do not.

# 3. the tier. --gate-floor is REQUIRED here: there is no work-order file to read it from,
#    and the classifier tiers everything high when both are missing.
${CLAUDE_PLUGIN_ROOT}/scripts/wo-risk-classify.sh \
  --files-from "$CD/<component>.files.txt" \
  --gate-floor "tdd,solid,dry,security,guides"        # the base_gate_floor from risk-tiering-rules.json
# → .risk_tier ∈ low | medium | high
```

**4. Lenses** from `references/risk-tiering-rules.json` `tier_lenses`: `low` → `correctness`;
`medium` → `security`, `correctness`; `high` → `security`, `correctness`, `meets-ac`. A
security lens is guaranteed at `medium` and above, so executable code always gets one.

**5. Critics.** For each lens dispatch ONE `ai-dev-assistant:wo-critic` via the Task tool,
**fresh and independent, never a fork** — a forked critic inherits the reasoning it exists to
challenge. **Render the dispatch:** write the component's `## Acceptance criteria` to `$CD/<component>.ac.txt` and the delimited recipe block (empty for `meets-ac`) to `$CD/<component>.recipe.txt` the way `<component>.files.txt` is written, then `${CLAUDE_PLUGIN_ROOT}/scripts/prompt-render.sh critic-dispatch lens=<lens> worktree=<codePath> range=<base-sha-for-this-round>..$AFTER files@="$CD/<component>.files.txt" component=<component> acceptance_criteria@="$CD/<component>.ac.txt" recipe_block@="$CD/<component>.recipe.txt" output_path="$CD/<component>.critics/<component>.critic-<lens>.json"` (Bash). The three `@=` values are repo text and never pass through a shell argument: inline, every backtick and `$(...)` in them ran and the code vanished while the render exited 0.
Hand the Task tool exactly what it printed: nothing above it, nothing below it, no wording of your
own. The template carries `review_ref: null` and says so, because there is no per-component `/review`
and a critic must not read an absent record as a clean one; it also tells the critic to run the
component's own spec and never the suite. A render that exits 2 is `--not-dispatched <lens>:render_failed` at step 6, never a smaller `--expected`; the kernel still counts a withheld `security` as missing, so the lens is lost loudly.

**`security` and `correctness` receive the resolved implement recipe** (the body Read at step 6),
verbatim, inside the delimited block `references/recipe-resolution.md` step 4 defines; for
`correctness`, inject it or do not dispatch, the posture `/review` step 5 holds for its validator. `meets-ac` compares
the build against acceptance items and does not receive it. When no `body_path` resolved for a
framework (step 6's no-body rule), `security` is still dispatched, without the block, and
`correctness` is not: pass `--not-dispatched correctness:no_body_path` to the aggregator so the
envelope records why. The kernel counts any other withheld lens as a missing critic. **That is the
whole dispatch:** criteria, recipe block, range, lens, output path. A probe list, a posture ("treat as
hostile"), or a checklist in the prompt is the deleted lens by another name, and it was
measured to buy a repair round per component.

**Read each verdict from the file the critic wrote, never from its Task return.** An agent
that died mid-response returns text that reads like an answer.

```
# 6. the verdict. --required is what makes an `unresolved` critic blocking; without it an
#    undetermined critic aggregates to a non-blocking `concern` below high tier.
#    --diff-empty when <component>.files.txt is empty: a component declared done that changed
#    nothing is `critical`, not `skipped`. That is a do-nothing build, and catching it is the
#    `meets-ac` lens's whole job.
${CLAUDE_PLUGIN_ROOT}/scripts/wo-critique-aggregate.sh \
  --wo "<component>" --tier "<risk_tier>" --mode fanout \
  --expected <number of lenses dispatched> \
  --critics-dir "$CD/<component>.critics" \
  --evaluated true --required [--diff-empty] \
  > "$CD/<component>.critique.json"
```

The kernel always exits 0 and always emits an envelope; **the verdict is in `blocking`**, not
in the exit code. On `blocking: true` the component stops: `[a]ddress` (fix, then re-run this
rung for this component) or `[o]verride (reason)`, recorded in the envelope's `bypass_reason`.

- **A `critical` halts that component.** The build does not move to the next one.
- **`unresolved` is not a pass.** A critic that could not determine has cleared nothing, and
  `--required` above is what makes the kernel treat it as blocking rather than folding it into
  a non-blocking `concern` at low and medium tier.
- `overall: "concern"` is surfaced and does not block.

**Every `[a]ddress` begins by re-Reading each framework's `body_path` from `_recipe-load.json`,**
before the fix is authored, gated by `verified` exactly as step 6 (the body is the method, never a
command), and only when that record's `phase` is `implement`: any other phase, or no file, is
`no_body_path` with the reason naming what was found. Record `frameworks[].fix_recipe_read`
(`{verdict: read | no_body_path | unreadable, body_path, round, reason}`; `round` is the `rounds[]`
entry the re-run will write, so the first `[a]ddress` is 2) by writing the whole `gate_specific` back
through `gate-audit-write.sh <task_folder> recipe-load`, every other framework entry and every key on
this one preserved (§5.12). The body was Read at step 6; by round three, or past a compaction, it is
not in context, and a fixer without the stack's test strategy adds a test because that is what
discipline sounds like. `no_body_path` or `unreadable` means the fix proceeds under step 6's no-body
rule, inventing no stack specifics, with `reason` saying why.

**Every `[a]ddress` ends with an accept verdict on the repair, before the rung re-runs.**

```
# The REPAIR's range, not the build's. Step 2's `--name-only` diff covers the code the critics
# read; this covers what the repair itself changed, and the kernel needs A/M/D, not names.
# BOTH ENDS ARE SHAS. $AFTER from step 1, never the literal `<component>.after`: that label
# lives under refs/worktree/aida/build-checkpoints/, off git's rev-parse path, so git exits 128
# and the redirect leaves a 0-byte file the kernel answers cannot_judge.
REP=$(${CLAUDE_PLUGIN_ROOT}/scripts/build-checkpoint.sh capture --repo <codePath> \
        --label <component>.repaired | jq -r .sha)
git -C <codePath> diff --name-status $AFTER..$REP > "$CD/<component>.repair.txt"
${CLAUDE_PLUGIN_ROOT}/scripts/repair-accept-check.sh --suite <green|red|not_run> \
  --test-motion-from "$CD/<component>.repair.txt" --test-globs '<test paths, JSON array>' \
  [--test-globs-source undetermined] [--modification-reason "<why a test file changed>"]
```

`--suite` is a RESULT you hand in; the kernel runs nothing. Who runs it is settled by `run_mode`
(`references/tdd-workflow.md:85-88`): the person interactive, you autonomous. Per repair the suite is
the specs that read the files in `<component>.files.txt`, named in the record; `make` targets run once,
when the PR is final, never per repair. With no suite over the repaired tree, `not_run` is the honest
value and returns `cannot_judge`, not a pass. `--test-globs` is where this project's tests live; when that
cannot be established pass `--test-globs-source undetermined`, never `[]`, the claim that no test path was touched.

**Both ends of that diff are shas**, the same way the phase range at Step 12 is. A checkpoint
label is not a revision, so handing one to `git diff` leaves an empty file rather than an error
the rung would notice, and an empty file is `cannot_judge` at the kernel. **Every `rounds[]`
entry carries a numeric `round`**: the gate reads the repair state from it and hard-fails an
entry that has none, at `/review`, on an otherwise clean build.

**Record `accept {action, suite, decided_by, reason}` on that component's row**, the first
three from the kernel and `reason` from its `reasons[]`. Required on every repaired component:
one with no `accept` is `unresolved` at `/review`, and any action other than `accepted` needs
the decision to ship it recorded in `escalation.reason` or the round's `resolution`.

Do not skip the rung because the component looks small. Whether it is small is a judgment by
the same context that built it, which is the judgment being checked.

**Carry a `rounds` count on each component row and a `rounds[]` history of what each round
found.** The deferred-findings check below reads `.rounds[]`, and an absent key yields an empty
list, which passes silently — so a build that defers a finding and writes no `rounds[]` records
the deferral nowhere the gate can see it.

**A finding you cannot answer yet is deferred, not fixed speculatively.** When a critic reports
something whose resolution lives in a component later in the build order, carry it in the round's
`deferred[]` as `{finding, blocked_on, why_now_is_wrong}` rather than inventing a fix for absent
code. In the same live build, answering one such finding produced the next round's critical and
that answer produced the round after. Deferred findings do not block; they are re-checked when
`blocked_on` is built.

### Runtime Step 12 — close the phase

Reached when the last component closes. All four parts are required.

0. **The contract diff.** `${CLAUDE_PLUGIN_ROOT}/scripts/contract-baseline.sh diff
   "<task_folder>"`. Carry it into part 2's payload, and read it before writing that payload:
   a `changed[]` entry is a design document this build edited, and the reason belongs in the
   record rather than only in the file's own prose.

1. **The alignment axis.** Capture `--label phase.after`, then hand
   `ai-dev-assistant:spec-axis-reviewer` the file list from
   `git -C <codePath> diff --name-only <phase.before-sha>..<phase.after-sha>` together with
   `alignment.md`'s Task-Level `### Success criteria` and `architecture.md`.

   **Use the checkpoint range, not `review-change-set.sh`.** That resolver deliberately
   excludes untracked files, and a new module is entirely untracked until someone stages it —
   the exact case this phase exists to build. Handed a change set with the new code missing,
   the reviewer finds every criterion unimplemented and hard-fails complete work.

   Verdict rule unchanged from Phase 4: `missing_requirements[]` non-empty is a hard fail,
   `scope_creep[]` alone is advisory. It does **not** write `_spec.json` here. `/review` runs
   its own Spec pass later regardless, and that is the point rather than a duplication: a
   criterion found unimplemented while the build is open is a task, and found at the gate it
   is a reopening.

2. **The record.** ONE envelope. **Write the payload to a file and pass it as `@<path>`** —
   `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh "<task_folder>" build-critique
   "@/tmp/build-critique-payload.json"` (schema 1.9, shape in
   `references/gate-audit-schema.md`). Not a style preference: this record grows per component
   per round, a command-line argument is capped at 128 KB by the kernel, and past that the write
   dies with "argument list too long" before the script starts — taking the key-loss guard with
   it and leaving a hand edit as the only way to update the file, which is the exact rewrite that
   guard refuses. Measured live at 136 KB on a nine-component build.

   **`build_identity` is required and says which build the critics saw.** Three fields:
   `head` (`git -C <codePath> rev-parse HEAD` at the close of the rung), `files` (the sorted file
   list handed to the critics), and `files_digest` (`printf '%s' "$(printf '%s\n' <sorted files>)"
   | sha256sum`, the same digest `/review` recomputes). Without it the review gate cannot tell
   whether this record describes the code under review, which is `unresolved` and fail-closed —
   not a pass. It exists because `[r]` at the review prompt means exit, fix, re-run: every
   remediation produces a build the record predates, and the gate that asks whether the build was
   challenged would otherwise answer yes about the previous one.

   **`components_declared`, `components_critiqued` and
   `uncritiqued[]` are all required and must be honest.** A rung that critiqued three of seven
   components and recorded only its three green rows is a record that cannot say what it did
   not look at. Every gap gets a `{component, reason}` row.

   `verdict: "skipped"` is legitimate for exactly two cases, each carrying its reason: the
   phase-level range is empty, or the task has no architecture file at all. It is never the
   answer to "the critics did not run" — that is `unresolved`, with the components named.

   **The payload also carries `contract` (v5.34.0+)** — `{baseline, changed[], reason}` from
   `${CLAUDE_PLUGIN_ROOT}/scripts/contract-baseline.sh diff "<task_folder>"`. Amending
   `alignment.md` or `architecture/` mid-build is legitimate and sometimes forced, but it must
   be visible: `meets-ac` and the alignment axis both judge the change against those files, so
   an unrecorded edit lets a build authorise itself. A `changed[]` with no `reason` fails, and
   so does a phase that never captured a baseline at Step 11.

   **The payload also carries `tdd` (v5.34.0+):** `{red_observed, passed_first_run, unobserved[], reason}` aggregated over every
   criterion built this phase, from the loop step 4 outcomes. `unobserved[]` is legal and needs
   a `reason`; without one it is indistinguishable from nobody having thought about it. Any
   `passed_first_run` is a blocking violation. This is the only place the RED observation is
   written down, and `/review` step 5.0f is what reads it back.

   **The payload carries `closing_fixes` (v5.35.3+):** `{applied, verified_by, reason}` — what
   changed after the last critique pass. Anything repaired after the critics returned is code no
   critic read, so name who checked it. `applied: 0` is an answer. When the fix's own author is
   the only reader, say so and say why.

   **Every `components[]` row carries `runtime` (v5.35.2+):** `executed`, `static_only`, or
   `not_run`, and the last two need a `runtime_reason`. Every gate this rung fires can pass over
   code that was never executed, so a green phpcs / phpstan / unit run says nothing about whether
   the component was ever exercised. Static-only is a legitimate answer and sometimes the only
   safe one; what fails is a row that cannot say which it was.

   **When the alignment axis runs, the payload carries `criteria_unverifiable[]` (v5.35.2+):**
   `{criterion, reason, what_would_verify}` for each success criterion that no test at the levels
   this design chose can verify at all. That is a different fact from `criteria_not_implemented`,
   which means the code is not written yet, and the two have opposite remedies. An empty array is
   required and asserts that every criterion has something shipped that could prove it.

3. **The records check.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/phase-records-check.sh
   "<task_folder>" --phase implement` and surface its verdict. A missing `_build-critique.json`
   makes the verdict `incomplete` and lifts `missing_required` — the row is
   `required-unless-work-orders`, resolved against disk, so it is required here and downgraded
   only when `work-orders/wo-NN._critique.json` files show the build went through
   `/run-work-orders` instead. It was `conditional` until v5.33.0, and conditional rows are
   never counted against the verdict, so a phase that skipped the rung entirely still reported
   `complete` with `missing_required: 0` and this sentence described an enforcement that did
   not exist. `/review` step 5.0f re-asserts the same record as a hard block; failing here is
   cheaper, because the context that could fix it is still loaded.

4. **Clear the checkpoints.** `${CLAUDE_PLUGIN_ROOT}/scripts/build-checkpoint.sh clear --repo
   <codePath>`, so the phase leaves no refs behind in the code repository.

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
- Audit shape: `references/gate-audit-schema.md` v1.9
- Worktree conventions: `references/worktree-conventions.md`
- Build-critique rung: `references/build-critique.md` (v5.33.0+)

## Related

- `/ai-dev-assistant:research <task>` — Phase 1
- `/ai-dev-assistant:design <task>` — Phase 2
- `/ai-dev-assistant:complete <task>` — mark task done
- `/ai-dev-assistant:validate <task>` — validate against architecture
- `/ai-dev-assistant:worktree <task>` — isolate in `.worktrees/<task>/`

## Output

Writes the code plus `implementation.md`, and one `_<gate>.json` per gate that fired, including `_preconditions.json` when a framework implement recipe resolved (v5.31.0+), `_framework.json` when the project had no recorded frameworks and the framework-resolution cascade ran to name one, and `_build-critique.json` for the build-critique rung (v5.33.0+). The rung also writes one verdict file per critic under `<task_folder>/build-critique/`, plus the two diff listings it hands the kernels there, `<component>.files.txt` (the build under critique) and `<component>.repair.txt` (the repair's own name-status range), and freezes the contract at `<task_folder>/build-critique/_contract-baseline/` (v5.34.0+) — copies of `alignment.md`, `architecture.md` and `architecture/*.md` as they stood before any code was written, so the critics judging scope can tell a design that authorised the work from one amended to describe it. Written once at Runtime Step 11 and never overwritten; it stays with the task folder rather than being cleared at end of phase, because it is the evidence for what the phase was judged against.

**In the code repository (v5.33.0+):** the rung anchors its build checkpoints as refs under `refs/worktree/aida/build-checkpoints/` in the repository at `codePath`, plus a shared keep-ref per object at `refs/aida/build-checkpoints-keep/<sha>`. These are commit objects on no branch — HEAD, the index, the working tree, `git branch`, `git status` and `git stash` are all untouched, and a plain `git log` does not show them, though `git log --all` does. The rung removes them at end of phase with `build-checkpoint.sh clear`; `build-checkpoint.sh list --repo <codePath>` shows any left behind by an interrupted run. It is the only thing this command writes into the code repository other than the code itself.

The pair is deliberate and load-bearing. `refs/worktree/` rather than a plain `refs/` path: everything else under `refs/` is shared by every checkout of a repository, while `refs/worktree/` is per-checkout. Two agents building different tasks in two worktrees of one repository is the ordinary case here, not an edge case, and step 2 of this command actively nudges toward a worktree. In a shared namespace they would write the same default label, silently overwrite each other's boundary, and one of them clearing at end of phase would delete the other's, handing a critic a range belonging to a different task. The shared keep-ref then buys back what per-checkout refs give up: they are not reachability roots for a `git gc` run from another checkout, so without it a `gc --prune=now` next door collects the object and leaves the ref. It is named by the object's own sha, which is why sharing it cannot collide. `clear` removes both, and `list` says whether each object still resolves.

Prints progress and test results.
