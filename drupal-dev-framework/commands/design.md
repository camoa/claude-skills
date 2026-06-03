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
/drupal-dev-framework:design <task-name>
```

## Runtime Steps

1. **Phase Transition Check.** Read `task.md` Phase Status. If Phase 1 not `[x]`, print one-line soft-nudge ("Phase 1 not complete; continuing anyway. Consider `/drupal-dev-framework:research <task>` first."). Never block.

2. **Dev-guides preflight (two-stage, v4.10.0+).** Same hybrid detection as `/research` step 3 (see that command for the full description).
   - **Stage 1.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh <task_folder> --phase design`. The design-phase methodology floor adds `plugin:library-first` to the research trio (`tdd-workflow`, `solid-drupal`, `dry-patterns`) — 4 refs.
   - **Stage 2.** Invoke `guides-matcher` in `mode: "prose"` (schema v1.1) with `artifact_excerpts[]` from `task.md` + `alignment.md` + `research.md` and `candidate_slugs[]` = Stage 1's `catalog_candidates[].slug`. Skip silently when the catalog cache is missing.
   - Display the two-group preflight prompt (`Methodology (always):` / `Domain guides matched:`). Block on `[c]/[a]/[n]` (default `[c]`; semantics unchanged). Write `_dev-guides-load.json` audit with `methodology_floor[]`, `catalog_candidates[]`, `matched_domain_guides[]`, `guides_actually_loaded[]`.

3. **Playbook load.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh <project_folder>`. Surface conflicts once-per-session per topic. Write `_playbook-load.json` audit.

4. **Alignment retrofit + phase-level offer.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh "<task_folder>"` (Bash) and parse its JSON. If `.sections.task_level.present == false`: offer task-level retrofit (4 questions, default `[n]`). On `[y]` execute task-level scope flow inline. Then offer phase-2 scope (default `[n]`); on `[y]` execute `--phase 2` inline. Never block.

5. **Author architecture.md.** Invoke `architecture-drafter` agent + `guide-integrator` for methodology refs. Write standard sections: Approach, Components, Dependencies, Pattern Reference, Interface, Data Flow, SOLID Principles Applied, Security Considerations, Acceptance Criteria. For complex tasks, optionally write `architecture/<component>.md` per component. Update `task.md` Phase 2 in-progress. **Mid-phase guide checks apply:** before designing against a Drupal API, contrib module, or pattern not already in `loadedGuides[]`, do a `dev-guides-navigator` catalog lookup (see `guide-integrator` SKILL.md §"Mid-phase guide checks").

6. **Post-design epic check (v3.13.5+).** Re-invoke `analysis-agent` in folder mode (now sees task+alignment+research+architecture). **Normalize the returned JSON** through `${CLAUDE_PLUGIN_ROOT}/scripts/analysis-agent-normalize.sh` before branching (deterministic `confidence` clamp, schema invariant 2). Branch on `decision`:
   - `keep_flat` / `insufficient_info` → silent, proceed.
   - `epic_candidate` → display offer (architecture.md not auto-partitioned across children — user rebuilds per child), default `[n]`. `[y]` → `/migrate-to-epic`, stop. `[d]` → show rationale, re-ask.

7. **Traceability walkthrough (opt-in).** One-line `[y]/[n]` (default `[n]`). On `[y]`: pull AC from alignment task-level OR `task.md`; map each to architecture.md sections; mark "NOT YET ADDRESSED" honestly; print table; `[c]/[r]/[d]` (default `[c]`).

8. **Mark Phase 2 `[x]`** in `task.md`.

9. **Run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task>" "<task_path>"`** (Bash) with resolved project + task.

## Pointers

- Full walkthrough: `references/design-walkthrough.md`
- Mandated wording: `references/gate-hardening-prompts.md`
- Audit shape: `references/gate-audit-schema.md` v1.0
- Alignment grammar: `references/alignment-contract.md`

## Related

- `/drupal-dev-framework:research <task>` — Phase 1
- `/drupal-dev-framework:implement <task>` — Phase 3
- `/drupal-dev-framework:pattern <use-case>` — pattern recommendations
- `/drupal-dev-framework:validate <task>` — validate design
