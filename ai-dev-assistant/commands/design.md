---
description: "Design architecture for a specific task. Trigger: 'architecture', 'design task', 'plan component', 'Phase 2'. REQUIRES completed research. Enforces Library-First, CLI-First, SOLID, DRY."
allowed-tools: Read, Write, Glob, Grep, Bash, Skill, Task
argument-hint: <task-name>
---

# Design

Phase 2 of a task. Behavior current as of v4.0.2; full prose / examples / version history in `references/design-walkthrough.md`.

> **Reading strategy:** Phase 2 is **Type B** work — read full architecture refs, service definitions, and pattern docs; do NOT grep-first. See `https://camoa.github.io/dev-guides/development/reading-strategy/`.

## Usage

```
/ai-dev-assistant:design <task-name>
```

## Runtime Steps

1. **Phase Transition Check.** Read `task.md` Phase Status. If Phase 1 not `[x]`, print one-line soft-nudge ("Phase 1 not complete; continuing anyway. Consider `/ai-dev-assistant:research <task>` first."). Never block.

2. **Dev-guides preflight (two-stage, v4.10.0+).** Same hybrid detection as `/research` step 3 (see that command for the full description).
   - **Stage 1.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh <task_folder> --phase design`. The design-phase methodology floor adds `plugin:library-first` to the research trio (`tdd-workflow`, `solid`, `dry-patterns`) — 4 refs.
   - **Stage 2.** Invoke `guides-matcher` in `mode: "prose"` (schema v1.1) with `artifact_excerpts[]` from `task.md` + `alignment.md` + `research.md` and `candidate_slugs[]` = Stage 1's `catalog_candidates[].slug`. Skip silently when the catalog cache is missing.
   - Display the two-group preflight prompt (`Methodology (always):` / `Domain guides matched:`). Block on `[c]/[a]/[n]` (default `[c]`; semantics unchanged). Write `_dev-guides-load.json` audit with `methodology_floor[]`, `catalog_candidates[]`, `matched_domain_guides[]`, `guides_actually_loaded[]`.

3. **Playbook load.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh <project_folder>`. Surface conflicts once-per-session per topic. Write `_playbook-load.json` audit.

4. **Alignment retrofit + phase-level offer.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh "<task_folder>"` (Bash) and parse its JSON. If `.sections.task_level.present == false`: offer task-level retrofit (4 questions, default `[n]`). On `[y]` execute task-level scope flow inline. Then offer phase-2 scope (default `[n]`); on `[y]` execute `--phase 2` inline. Never block.

5. **Author architecture.md.**
   - **Resolve the framework design method (recipe-resolution protocol).** Before invoking the design agents, follow the shared recipe-resolution protocol in `references/recipe-resolution.md` with `phase: design` and the active project's `<project_folder>`. That protocol invokes the `process-recipe-loader` skill, resolves each framework's design recipe (project_state-first, then source order, else `action:ask-user`), records the source in `project_state.md`, and defines how to follow each result: Read the `body_path` (never streamed), follow `verified:true` directly, surface `verified:false` for human review first, and on `action:ask-user` ask the user for a path or to research. Surface any loader `warnings[]` (for example `no_frameworks_defined`, `navigator_unavailable:<framework>`, `recipe_not_published:<framework>`) to the user. The COMMAND owns this resolution and injects the resolved recipe body into the agent's context; the design agents (`architecture-drafter`, `pattern-recommender`, `core-pattern-finder`) stay generic and need no Skill tool.
   - **Read the body and inject it verbatim.** For each framework result with `available:true`, Read its `body_path` with the Read tool (it is never streamed), gate it by `verified` (follow `verified:true`; surface `verified:false` for human go-ahead first), then dispatch `architecture-drafter` with the Task tool and include the recipe body **verbatim** in the agent's prompt, inside the delimited block from `references/recipe-resolution.md` step 4 (`=== RESOLVED RECIPE (key=…, source=…, verified=…) === <body> === END RECIPE ===`). Inject the same recipe body into `pattern-recommender` and `core-pattern-finder` whenever they run for this design. Reading `body_path` and dispatching an agent without including the body is a bug: the agent would have no design method to follow.
   - **Record the resolution (recipe-resolution.md step 7).** After resolving, write `<task>/_recipe-load.json` via `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh "<task_folder>" recipe-load "<payload>"` (payload per `references/gate-audit-schema.md` §5.12): every framework considered with its `source`/`verified`/`available`/`body_path`, plus a `bypass` object for any no-recipe outcome. Run the step-7 lint too; design carries no *required* declaration, so it is a clean no-op — record `declarations_audit` as `null`. Observability only — never blocks.
   - **No body resolved → do not dispatch a method-less agent.** Dispatch the design agents **only** when a `body_path` resolved for the framework. On `no_frameworks_defined`, read `codePath` via `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh` first (the loader result carries no codePath), then follow the framework detect-or-ask sub-protocol in `references/recipe-resolution.md` step 6 (detect → offer/ask → write `**Frameworks:**` → re-resolve once → proceed; unattended: record gap + skip); on `action:ask-user` ask the user for a path or to research and proceed per the answer; on a framework that resolved nothing skip it with a clear note. Per `references/recipe-resolution.md` step 6, the generic-agent dispatch needs a `body_path` to inject.
   - **Author against the injected recipe.** Run `architecture-drafter` (with the injected recipe body) to author the architecture; invoke `pattern-recommender` / `core-pattern-finder` (also with the injected body) as needed for pattern choices and canonical examples. Also invoke `guide-integrator` for methodology refs. Write standard sections: Approach, Components, Dependencies, Pattern Reference, Interface, Data Flow, SOLID Principles Applied, Security Considerations, Acceptance Criteria. For complex tasks, optionally write `architecture/<component>.md` per component. Update `task.md` Phase 2 in-progress.
   - **Mid-phase guide checks apply:** before designing against a framework API, third-party library, or pattern not already in `loadedGuides[]`, do a `dev-guides-navigator` catalog lookup (see `guide-integrator` SKILL.md the "Mid-phase guide checks" section).

6. **Post-design epic check (v3.13.5+).** Re-invoke `analysis-agent` in folder mode (now sees task+alignment+research+architecture). **Normalize the returned JSON** through `${CLAUDE_PLUGIN_ROOT}/scripts/analysis-agent-normalize.sh` before branching (deterministic `confidence` clamp, schema invariant 2). Branch on `decision`:
   - `keep_flat` / `insufficient_info` → silent, proceed.
   - `epic_candidate` → display offer (architecture.md not auto-partitioned across children — user rebuilds per child), default `[n]`. `[y]` → `/migrate-to-epic`, stop. `[d]` → show rationale, re-ask.

7. **Traceability walkthrough (opt-in).** One-line `[y]/[n]` (default `[n]`). On `[y]`: pull AC from alignment task-level OR `task.md`; map each to architecture.md sections; mark "NOT YET ADDRESSED" honestly; print table; `[c]/[r]/[d]` (default `[c]`).

8. **Mark Phase 2 `[x]`** in `task.md`.

9. **Run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task>" "<task_path>"`** (Bash) with resolved project + task.

10. **Work-order compile offer (v4.19.0+).** After writing session context, offer to decompose this architecture into self-contained work-orders for independent-agent build:

> 💡 Phase 2 complete. Decompose this task into self-contained work-orders for independent-agent build? `/ai-dev-assistant:compile-work-orders <task>` produces `work-orders/wo-NN-*.md` (see `references/work-order-lifecycle.md`). `[y]` runs it now; `[n]` (default) — proceed to `/implement`.

Default `[n]` — proceed to `/ai-dev-assistant:implement` as usual. Never blocks.

## Pointers

- Full walkthrough: `references/design-walkthrough.md`
- Mandated wording: `references/gate-hardening-prompts.md`
- Audit shape: `references/gate-audit-schema.md` v1.0
- Alignment grammar: `references/alignment-contract.md`

## Related

- `/ai-dev-assistant:research <task>` — Phase 1
- `/ai-dev-assistant:implement <task>` — Phase 3
- `/ai-dev-assistant:pattern <use-case>` — pattern recommendations
- `/ai-dev-assistant:validate <task>` — validate design
- `/ai-dev-assistant:compile-work-orders <task>` — decompose architecture into work-orders for independent-agent build (see `references/work-order-lifecycle.md`)
