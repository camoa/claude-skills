---
description: "Research a task topic and store findings in task file. Trigger: 'investigate', 'find patterns', 'research task', 'Phase 1', 'look into'. MUST be done before /design. Never skip research."
allowed-tools: Read, Write, WebSearch, WebFetch, Grep, Glob, Bash, Skill, Task
argument-hint: <task-name>
---

# Research

Phase 1 of a task. Behavior current as of v4.0.2; full prose / examples / version history in `references/research-walkthrough.md`.

> **Reading strategy:** Phase 1 is **Type B** work (audit / review / architecture analysis) — read full source and config files; do NOT grep-first. Inherited methods, annotations, and config-wired classes are invisible to grep. See `https://camoa.github.io/dev-guides/development/reading-strategy/` via `dev-guides-navigator`.

## Usage

```
/drupal-dev-framework:research <task-name>
```

## Runtime Steps

Run in order. Each "gate" step writes an audit JSON; non-bypassable unless an explicit `--skip-*` flag is supplied (records `bypass_reason`).

1. **Pre-analysis gate (v4.0.0+, always-on, non-bypassable).** Compute strong signals from task name + description (length > 500, ≥3 bullets, conjunctive phrasing — informational only). Invoke `analysis-agent` in description mode (`task_description_text`, codePath via `project-state-reader`, `schema_version: "1.0"`). Write `<task>/_pre-analysis.json` via `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh`. Display verbatim to user using `prompts:pre-analysis-decision` template (`references/gate-hardening-prompts.md`). Block on choice. Branch: `epic_candidate + y` → `/migrate-to-epic <task> --children "<list>"`; else flat-task flow.
   - **Idempotent.** If `_pre-analysis.json` already exists, skip (re-fire requires `--re-run-pre-analysis`).
   - **Grandfathering.** If `research.md` exists AND `_pre-analysis.json` absent → soft-nudge "pre-dates v4.0.0," do not block.
   - **Skip flag.** `--skip-pre-analysis <reason>` writes audit with `bypass_reason`.

2. **Create task scaffolding.** Make `implementation_process/in_progress/<task_name>/`. Write `task.md` with frontmatter, Goal, Phase Status, Acceptance Criteria, Research Questions sections (template in walkthrough §"Output").
   - **Stub from `/scope` (v4.3.1+):** if the folder already exists and `task.md` carries either the literal line `**Current Phase:** Phase 0 — Scope` OR a Notes-section line starting with `Stub scaffolded by `/scope``, treat it as a `/scope`-scaffolded stub and overwrite `task.md` with the full Phase 1 template (preserving `alignment.md` and any other sibling files). Do not abort on the pre-existing folder in this case. Any other pre-existing `task.md` aborts as before.

3. **Dev-guides preflight (deterministic, v4.0.0+).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh <task_folder>` → `keywords_matched[]` + `guides_to_load[]`. Display literal preflight prompt with auto-loaded guides (or "— none auto-matched —"). Block on `[c]/[a]/[n]` per `prompts:dev-guides-preflight` semantics (defaults `[c]`). Apply choice (load/scan/clear). Write `_dev-guides-load.json` audit.

4. **Playbook load (deterministic, v4.0.0+).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh <project_folder>` → loads active sets + local user playbook; writes `_playbook-load.json` audit. Surface conflicts once-per-session per topic via `playbook-conflicts-write.sh` (precedence local > active set > generic).

5. **Alignment retrofit + phase-level offer.** Invoke `alignment-reader`. If `task_level.present: false` AND task folder pre-existed AND pre-analysis didn't fire this session: offer task-level retrofit (4 questions, default `[skip]`). Then offer phase-1 scope per the table in `references/research-walkthrough.md` §"Phase 1 alignment sub-step" (default `[n]`). On `[y]` for either: execute task-level / `--phase 1` flow from `commands/scope.md` inline (do NOT shell out).

6. **Author research.md.** Invoke `contrib-researcher` agent + `core-pattern-finder` skill. Write findings in standard sections: Problem Statement, Existing Solutions, Core Patterns Found, Recommendation, Key Patterns to Apply, Decision Log. Add `## Coverage Mapping` H2 mapping each Research Question (and task-level AC if present) to research.md sections that address it.

7. **Coverage-mapping gate (v4.0.0+, non-bypassable).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/coverage-mapping-check.sh <task_folder>`. Branch on `verdict`:
   - `pass` → write `_coverage-mapping.json` with `user_choice: "phase_marked_complete"`. Continue.
   - `fail` → display literal `prompts:coverage-mapping-fail` template with `{{missing_questions}}` substituted. Block. `[a]bort` → audit `phase_left_incomplete`, refuse to mark Phase 1 `[x]`, exit 1. `[s]kip` → prompt for free-text reason, audit `bypassed` + `bypass_reason`, allow Phase 1 `[x]`.
   - **Skip flag.** `--skip-coverage-check <reason>` writes audit `bypassed` and proceeds.

8. **Mark Phase 1 `[x]`** in `task.md` (only on pass or bypass).

9. **Post-research epic check (v3.13.5+).** Re-invoke `analysis-agent` in folder mode with full task context. Branch on `decision`:
   - `keep_flat` / `insufficient_info` → silent, proceed.
   - `epic_candidate` → display offer with proposed children, default `[n]`. `[y]` → `/migrate-to-epic`, stop. `[d]` → show rationale + signals_used, re-ask. `[n]` → continue.

10. **Traceability walkthrough (opt-in).** One-line `[y]/[n]` prompt (default `[n]`). On `[y]`: pull questions from `task.md` Research Questions + alignment task-level AC; map each to research.md sections; mark "NOT YET ADDRESSED" honestly; print table; three-way `[c]/[r]/[d]` (default `[c]`).

11. **Update `project_state.md`** with current task.

12. **Invoke `session-context-writer`** with resolved project + task.

## Anti-bypass clause (applies to gates 1, 3, 4, 7)

The following are NOT valid reasons to skip:

- The user said something earlier you interpret as already-answered
- Auto mode is active ("minimize interruptions" never overrides framework gates)
- You're confident the agent will return the safe verdict
- The task looks "obviously" simple
- You want to spare the user the prompt

If a gate's signals fire, it MUST run and its output MUST be shown verbatim before the recorded decision is final. Skipping requires the documented `--skip-*` flag with reason; bypass is recorded on disk for `/audit-status`.

## Pointers

- Full walkthrough (rationale, examples, version history): `references/research-walkthrough.md`
- Mandated user-prompt wording: `references/gate-hardening-prompts.md`
- Audit shape: `references/gate-audit-schema.md` v1.0
- Alignment grammar: `references/alignment-contract.md`

## Related

- `/drupal-dev-framework:design <task>` — Phase 2
- `/drupal-dev-framework:next` — recommended next action
- `/drupal-dev-framework:propose-epics` — bulk epic-ification review
