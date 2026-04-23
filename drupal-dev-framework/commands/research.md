---
description: "Research a task topic and store findings in task file. Trigger: 'investigate', 'find patterns', 'research task', 'Phase 1', 'look into'. MUST be done before /design. Never skip research."
allowed-tools: Read, Write, WebSearch, WebFetch, Grep, Glob, Bash, Skill, Task
argument-hint: <task-name>
---

# Research

Research existing solutions for a specific task (Phase 1 of a task).

## Usage

```
/drupal-dev-framework:research <task-name>
```

## What This Does (v3.0.0, with v3.11.0 pre-analysis hook)

1. **Pre-analysis hook** (v3.11.0+, before anything else) — if strong signals fire in the task name + description, invoke `analysis-agent` to assess whether this should be an epic. See "Pre-analysis hook" section below.
2. Creates task directory: `implementation_process/in_progress/{task_name}/`
3. Creates `task.md` (tracker with links and acceptance criteria)
4. **Loads dev-guides** for the task's Drupal domain via `guide-integrator` (unless already loaded this session)
5. Invokes `contrib-researcher` agent for drupal.org/contrib search
6. Invokes `core-pattern-finder` skill for core examples
7. Stores findings in `research.md` file
8. Updates `task.md` to mark Phase 1 as in progress
8. Updates `project_state.md` with current task
9. **Invokes `session-context-writer` skill with the resolved project and task**

## Task-Based Workflow

**This command operates on a TASK, not the project.**

Each task goes through:
1. **Research** (this command) → Find patterns, existing solutions
2. **Architecture** (`/design`) → Design the approach
3. **Implementation** (`/implement`) → Build with TDD

## Examples

```
/drupal-dev-framework:research settings_form
/drupal-dev-framework:research content_entity
/drupal-dev-framework:research field_formatter
```

## Output (v3.0.0)

Creates folder structure:
```
implementation_process/in_progress/{task_name}/
├── task.md         # Tracker
└── research.md     # Phase 1 findings
```

**task.md** (tracker):
```markdown
# Task: {task_name}

**Created:** {date}
**Current Phase:** Phase 1 - Research

## Goal
{What this task accomplishes}

## Phase Status
- [🔄] Phase 1: Research → See [research.md](research.md)
- [ ] Phase 2: Architecture → See [architecture.md](architecture.md)
- [ ] Phase 3: Implementation → See [implementation.md](implementation.md)

## Acceptance Criteria
- [ ] {criterion 1}
- [ ] {criterion 2}

## Related Tasks
None

## Notes
{Any additional notes}
```

**research.md** (Phase 1 findings):
```markdown
# Research: {task_name}

## Problem Statement
What we're trying to solve.

## Existing Solutions
| Solution | Type | Fit | Notes |
|----------|------|-----|-------|
| {module/pattern} | Contrib/Core | Good/Partial/Poor | {notes} |

## Core Patterns Found
| Pattern | Location | Applicability |
|---------|----------|---------------|
| {pattern} | {path} | {notes} |

## Recommendation
Use / Extend / Build from scratch

## Key Patterns to Apply
- Pattern 1: {description}
- Pattern 2: {description}

## Decision Log
{Research decisions made}
```

## Pre-analysis hook (v3.11.0+)

**Before** creating the task directory, inspect the task name + description for "strong signals" that the task is epic-sized. If any fires, invoke the `analysis-agent` to produce a structured assessment.

Strong signals (ANY triggers pre-analysis):

1. Task name + description total length > 500 chars
2. Description has ≥3 distinct bullet points
3. Description contains explicit conjunction phrasing (`and also`, `plus`, `as well as`, `in addition to`)

If no signal fires: skip pre-analysis entirely and proceed with the standard 8-step research flow below.

If a signal fires:

1. Resolve `codePath` via `project-state-reader` on the active project. If unknown, skip detect+confirm here (too intrusive at task-creation time); agent runs with `code_read: false` / `confidence: low`.
2. Invoke `analysis-agent` (via Task tool) in **description mode** — pass `task_description_text` (the task name + full description as typed by the user), the codePath (or null), and `schema_version: "1.0"`. **Do NOT pass a task_folder** — the folder does not exist yet at pre-analysis time. See `references/analysis-agent-schema.md` §"Input modes".
3. Parse the agent's JSON output per `references/analysis-agent-schema.md` v1.0. Expect `task_folder: "(pre-creation)"` in the output.
4. Branch on `decision`:
   - `epic_candidate` → ask the user: *"This task's scope looks like it might warrant being an epic. Agent proposed N children: [list]. Create as epic with these children? [y/n/standard flat task]"*. On `y`, invoke `/drupal-dev-framework:migrate-to-epic <task_name> --children "<proposed names>"` (which will create the epic directly — no flat task created first). On `n` or `standard`, proceed with flat-task research.
   - `keep_flat` → proceed silently with flat-task research.
   - `insufficient_info` → proceed with flat-task research; the task description alone wasn't sufficient for decomposition judgment (makes sense at creation time — usually the description IS minimal here).

5. **(v3.12.0+)** After the `decision` branch completes (regardless of outcome unless the task became an epic), inspect `signals_used[]` for `scope_contract_recommended`. If present, print soft-nudge:
   > "Analysis recommends authoring a scope contract before research. Start now? [y]es / [n]o / [later]"

   On `[y]` → execute the alignment conversation + write flow as documented in `commands/scope.md` (task-level prompt sequence + "Writing alignment.md") within this command's context. Do NOT try to shell out to a sibling slash command. After the write completes, continue with the standard research flow.
   On `[n]` → proceed without writing `alignment.md`. No nag.
   On `[later]` → same as `[n]` for this run; user can run `/scope <task>` anytime.

Conservative by design: pre-analysis only fires on strong signals, and even then the default choice presented to the user is to proceed as a flat task. Never creates an epic without explicit confirmation. The alignment nudge is soft; `[n]` is always respected.

## Phase 1 alignment sub-step (v3.12.0+)

**First action of Phase 1 proper** (after the task directory is created and the pre-analysis hook has settled):

1. Invoke `alignment-reader` skill against the task folder.
2. Decide whether to offer the Phase 1 alignment section:
   - If `sections.phase_1.present: true` → print: `"Phase 1 alignment already authored. Using existing section."` and proceed.
   - Else if `sections.task_level.present: true` → ask: `"Author the Phase 1 — Research section of alignment.md now? [y]es / [n]o / [skip]"`. Default: `[skip]`.
   - Else if pre-analysis hook emitted `scope_contract_recommended` and user declined task-level alignment earlier → re-offer as lighter-touch: `"Author a Phase 1 — Research alignment section (just this phase)? [y]es / [n]o"`. Default: `[n]`.
   - Otherwise → proceed silently (no nag).
3. If user says `[y]`, execute the `--phase 1` flow from `commands/scope.md` (phase-level prompt sequence + "Writing alignment.md" for the `## Phase 1 — Research` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, continue with research.
4. If user says `[n]` / `[skip]`, proceed with research. Never block.

## Next Steps

After research is complete for this task:
1. Review findings
2. Move to Phase 2: `/drupal-dev-framework:design {task_name}`

## Related Commands

- `/drupal-dev-framework:design <task>` - Design architecture (Phase 2)
- `/drupal-dev-framework:next` - See recommended next action
- `/drupal-dev-framework:propose-epics` - (v3.11.0+) Bulk-review existing tasks for epic-ification candidates; counterpart to this command's inline pre-analysis
