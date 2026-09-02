# Design — Full Walkthrough

Tutorial-depth reference for the `/ai-dev-assistant:design` command. The runtime command body (see `commands/design.md`) is a terse imperative summary; this file documents every sub-step, rationale, version history, and worked example in full.

**Loaded only when explicitly read.** No hook or skill auto-loads this file.

Design architecture for a specific task (Phase 2 of a task).

## Usage

```
/ai-dev-assistant:design <task-name>
```

## Phase Transition Check (run FIRST, before any other step)

Before doing anything else for this command, verify the prior phase is marked complete.

1. Read `implementation_process/in_progress/{task_name}/task.md`.
2. Locate the `## Phase Status` section.
3. If the **Phase 1: Research** checkbox is not `[x]`, print this soft-nudge line to the user with `{task_name}` replaced by the actual task name passed to this command:

   > ⚠ Phase 1 (Research) is not marked complete in `task.md`. Continuing with `/design` anyway. If research is incomplete, consider `/ai-dev-assistant:research {task_name}` first. (This is a nudge, not a block.)

4. If Phase 1 is `[x]`, proceed silently.

Never block the command on this check — the user is in control. The nudge exists so they notice out-of-order invocations without being fought by the tool.

## Dev-guides pre-flight (v3.13.4+)

**Run after the Phase Transition Check, before the alignment sub-step.** The goal: every phase command either loads dev-guides or has the user explicitly say "no guides" — never a silent skip. Dev-guides cover design systems (Bootstrap, Radix, Tailwind, DaisyUI), Next.js, CSS, and cross-cutting methodology (TDD, SOLID, DRY, security, quality gates) — relevant across all project types (plugin framework, docs-only, and tool-specific tasks).

### Step 1 — Invoke guide-integrator explicitly

**(v4.0.0+: deterministic detection.)** Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh <task_folder>` BEFORE prompting the user. Populate Step 2's prompt's "Auto-loaded based on task keywords:" line from `guides_to_load[]` script output. Write `<task>/_dev-guides-load.json` audit per `references/gate-audit-schema.md` after user picks `[c]/[a]/[n]`. Eliminates bypass-by-declaration.

**(v3.15.0+, refactored v4.0.0+)** `guide-integrator` v5.1.0+ delegates the playbook load to `${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh <project_folder>`; emits `<task>/_playbook-load.json` audit. Surface conflicts once-per-session per topic (precedence: local > active set > generic dev-guide); persist to `<project>/.claude/playbook-conflicts.log`.

### Step 2 — ALWAYS prompt the user (never silent-skip)

Regardless of whether guide-integrator auto-loaded 0, 1, or N guides, print:

> **Dev-guides pre-flight for `<task_name>` (Phase 2 — Architecture):**
>
> Auto-loaded based on task keywords:
>   <bulleted list of loaded guides, OR "  — none auto-matched —">
>
> Dev-guides cover design systems (Bootstrap, Radix, Tailwind, DaisyUI), Next.js, CSS, and methodology (TDD, SOLID, DRY, security, quality gates). Loading relevant guides before design keeps patterns grounded in proven approaches.
>
> **[c]ontinue** — auto-loaded set is fine, start design
> **[a]dd** — scan the `dev-guides-navigator` catalog for more topics before I design
> **[n]one** — skip dev-guides entirely (override any auto-loaded); I'll rely on you

Default: `[c]`.

### Step 3 — Act on the answer

- `[c]` → proceed to the alignment sub-step with the auto-loaded guides (possibly empty).
- `[a]` → invoke `dev-guides-navigator` interactively with task keywords the user supplies. Let the user select 0 or more additional guides. Load them via `guide-integrator`. After the user says "done," proceed to alignment.
- `[n]` → clear any auto-loaded guides from the session context (do NOT persist them to `loadedGuides[]`). Note "dev-guides declined" in session. Proceed to alignment.

### Notes

- **Never blocks.** `[c]` (default) always proceeds.
- **Discoverability > compliance.** The point is to surface available guides to users who don't know they exist — NOT to force guide consumption. `[n]` is a first-class choice.
- **Applicable to all task types.** Plugin-framework, docs-only, and tool-specific tasks can still find relevant methodology and design-system guides via `[a]`.

## Phase 2 alignment sub-step (v3.12.0+, task-level retrofit in v3.13.1+)

**Run after the Phase Transition Check, before any other Phase 2 work.** Same pattern as `/research`'s Phase 1 sub-step.

### Step 2a — Task-level retrofit (v3.13.1+)

1. Invoke `alignment-reader` skill against the task folder.
2. If `sections.task_level.present: false` → offer task-level retrofit with soft, phase-aware phrasing:
   > **Before I dive into design:** this task has no task-level scope recorded yet. Want to pin down what the whole task is trying to deliver first, so design doesn't wander?
   >
   > You'd answer 4 short questions, one at a time. Shape of the result:
   >
   > ```
   > Goal: <what this task is really about>
   > Expected result: <what exists when it's done>
   > Done when: <observable checks>
   > Won't do here: <related work we're skipping>
   > ```
   >
   > **[y]es** — 4 questions now
   > **[n]o** — start designing as-is (can always add this later)
3. On `[y]` → execute the **task-level** flow from `commands/scope.md` (context-aware task-level conversation + "Writing alignment.md" for the `## Task-Level` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, refresh `alignment-reader` output so Step 2b sees the new section.
4. On `[n]` / `[skip]` → proceed. Decision is final for this command invocation — no re-nag. Do NOT offer task-level retrofit again in the same `/design` run.
5. If `sections.task_level.present: true` → proceed silently to Step 2b (no prompt, no nag).

### Step 2b — Phase-level scope offer

1. Decide whether to offer an architecture-specific scope. Plain-language prompts:
   - If `sections.phase_2.present: true` → print: `"You already scoped this phase earlier. Using that scope."` and proceed.
   - Else if `sections.task_level.present: true` (either pre-existing, or just authored by Step 2a) → ask:
     > **Before I start designing:** you've already scoped the task. Want to also pin down what *just this design pass* is deciding (vs leaving for implementation)?
     >
     > Useful when architecture has many threads. Shape of the result:
     >
     > ```
     > Phase 2 — Architecture
     > Goal: <what this design pass is deciding>
     > Expected result: <e.g., "a doc naming the pieces and how they fit">
     > Done when: <observable signal, e.g., "someone else could hand this off to implementation">
     > Won't decide here: <pushed to Phase 3, e.g., "actual code / prose">
     > ```
     >
     > **[y]es** — 4 questions now
     > **[n]o** — start designing (can always add this later)
     Default: `[n]`.
   - Otherwise (user declined task-level retrofit in Step 2a) → proceed silently. No phase-level offer when there's no task-level foundation.
2. If user says `[y]`, execute the `--phase 2` flow from `commands/scope.md` (context-aware phase-level conversation + "Writing alignment.md" for the `## Phase 2 — Architecture` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, continue with architecture work.
3. If user says `[n]` / `[skip]`, proceed. Never block.

### Author marker on criteria written here

Both Step 2a's task-level flow and Step 2b's `--phase 2` flow are `commands/scope.md`'s own conversation and write step, executed inline rather than shelled out to — see `commands/scope.md`'s "Author marker" paragraph under "Writing `alignment.md`". The rule keys on the confirm, not the command: a criterion this inline flow shows the user and the user accepts via `[y]es`/`[e]dit` is `owner`, exactly as if `/scope` had been invoked directly. Everything else — most notably an unattended run reaching this flow with no interactive confirm available — is `designer`. `/design` never decides the author itself; it only inherits whatever `commands/scope.md`'s write step recorded.

**Why task-level retrofit lives here (v3.13.1 rationale):** Before v3.13.1, only `/research` offered task-level retrofit. Tasks that completed Phase 1 outside the `/research` command (plan-mode handoffs, manually-authored `research.md`, pre-v3.12.0 tasks) reached `/design` with no task-level scope and no chance to opt in. The v3.13.1 retrofit makes task-level alignment **discoverable** at every phase entry for users who don't know the feature exists — soft prompt, single-shot per invocation, fully skippable.

## What This Does (v3.0.0)

1. Loads task from `implementation_process/in_progress/{task_name}/`
2. Reviews research findings in `research.md`
3. **(v3.13.4+)** Dev-guides pre-flight — explicit `guide-integrator` invocation + always-prompt the user to continue / add / decline (see "Dev-guides pre-flight" section below)
4. Invokes `ai-dev-assistant:architecture-drafter` agent
5. Invokes `guide-integrator` for methodology refs
5. Creates/updates `architecture.md` with design
6. Updates `task.md` to mark Phase 2 as in progress
7. Optionally creates component file in `architecture/{component}.md`
8. **(v3.13.5+)** Post-design epic check (see "Post-phase epic check" below) — re-runs `analysis-agent` in folder mode with `task.md` + `alignment.md` + `research.md` + `architecture.md` and surfaces `epic_candidate` if architecture-level decomposition revealed epic-shaped work
9. **(v5.44.0+)** Runs the coverage gate (see "Coverage gate" below): every criterion covered, every acceptance item reaching a criterion, recorded as `_coverage.json`; then the design records check
10. **Invokes `session-context-writer` skill with the resolved project and task**

## Post-phase epic check (v3.13.5+)

**Run after `architecture.md` has been authored (and optional component file written), before the coverage gate.**

Purpose: epic-shape sometimes only becomes obvious at architecture time when you see the component breakdown. Research might have missed it; architecture might reveal that what looked like one task is actually 3 loosely-coupled components that belong as separate sub-tasks. This step catches that case.

### Step 1 — Re-invoke analysis-agent in folder mode

Invoke `ai-dev-assistant:analysis-agent` via Task tool with:

- `task_folder` = absolute path to the task folder (now contains `task.md` + `alignment.md` + `research.md` + `architecture.md` — strictly more context than at research time)
- `codePath` = resolved via `project-state-reader`
- `schema_version: "1.0"`

### Step 2 — Branch on `decision`

- `epic_candidate` → continue to Step 3
- `keep_flat` → proceed silently to the coverage gate
- `insufficient_info` → proceed silently

### Step 3 — Surface epic offer (only if `epic_candidate`)

Print:

> **Before locking in architecture:** looking at the design you just authored, this task might be cleaner as an epic. The architecture surfaced decomposition that pre-analysis + post-research checks hadn't caught.
>
> Proposed children (from `analysis-agent.proposed_decomposition`):
>   • `<child_1>` — <short rationale>
>   • `<child_2>` — <short rationale>
>   • …
>
> **[y]es** — convert to epic now via `/migrate-to-epic <task> --children "<list>"`. `research.md` + `architecture.md` stay on the parent epic; each child re-runs `/research` → `/design` on its slice.
> **[n]o** — keep flat; proceed to the coverage gate (can always migrate later)
> **[d]iscuss** — show agent's `rationale` + `signals_used[]` before deciding

Default: `[n]`.

### Step 4 — Act on the answer

- `[y]` → invoke `/ai-dev-assistant:migrate-to-epic <task> --children "<comma-separated proposed names>"`. Stop this `/design` invocation after migration.
- `[n]` → proceed to the coverage gate.
- `[d]` → print rationale + signals_used, re-ask Step 3.

### Notes

- **Never blocks.** `[n]` always proceeds.
- **Cumulative authority.** Post-design check has the MOST context of any epic check in the framework (task+alignment+research+architecture). If it fires `epic_candidate`, that's the strongest signal the framework can emit.
- **Mid-design migration is heavier than post-research migration** — architecture.md won't be automatically partitioned across children. User must rebuild design per child. Worth doing anyway if the signal is real.

## Coverage gate (v5.44.0+)

**Runs at design close, after the component files are written and after the epic check, before
`session-context-writer`.** It replaces the opt-in traceability walkthrough, which defaulted to not
running and was model-driven: this is deterministic, on by default, and recorded.

`scripts/coverage-check.sh "<task_folder>"` resolves the contract's criterion ids (`— id: c<n>` on a
Task-Level criterion in `alignment.md`, else on a criterion in `task.md`, through
`scripts/contract-resolve.sh`) and reads every `architecture/*.md`; the hub is never read for items.
Every unticked criterion must be served by an item, and every item must reach a criterion through its
one marker (`— serves: c<n>`, or `— supports: <component>` to a component that itself reaches one).
The command writes the printed JSON to a file and hands `@<path>` to `gate-audit-write.sh` as
`gate_type: coverage`, so item text lifted from the component files never becomes a shell argument.
The record's shape and every field's contract are in `references/gate-audit-schema.md` §5.19.

- `fail` halts: each `unreached` item is named with its component and `why`, each `uncovered`
  criterion by id. `[f]ix` re-runs after edits; `[o]verride <reason>` records the reason as
  `bypass_reason` on the record and proceeds. The fix for an unreached item is one line, a marker or
  a deletion, so clearing and flagging cost the same.
- `not_run` prints its reason and proceeds, and is not a pass: `no_ids` (no criterion carries an id;
  run `/scope`), or `no_components` (no `architecture/*.md`; a flat design is not checked).
- `not_applicable` (every criterion already ticked) and `pass` proceed silently.

The design records check, `scripts/phase-records-check.sh "<task_folder>" --phase design`, runs
next and names every missing required record with its producer. `_coverage.json` is one of them: a
`not_run` record satisfies the row, an absent one does not. `/implement`'s preflight reads the same
record before the first component opens and halts on `fail`.

## Task-Based Workflow

**This command operates on a TASK, not the project.**

Each task goes through:
1. **Research** (`/research`) → Find patterns, existing solutions
2. **Architecture** (this command) → Design the approach
3. **Implementation** (`/implement`) → Build with TDD

## Prerequisites

- Task must have completed Research phase
- Task file must exist in `implementation_process/in_progress/`

## Examples

```
/ai-dev-assistant:design config_manager
/ai-dev-assistant:design data_exporter
/ai-dev-assistant:design report_formatter
```

## Output (v3.0.0)

Creates/updates:
```
implementation_process/in_progress/{task_name}/
├── task.md           # Updated with Phase 2 status
├── research.md       # (existing)
└── architecture.md   # Phase 2 design (NEW)
```

**architecture.md** (Phase 2 design):
```markdown
# Architecture: {task_name}

## Approach
{High-level approach based on research}

## Components
| Component | Type | Purpose |
|-----------|------|---------|
| {name} | Service/Handler/Repository/etc | {purpose} |

## Dependencies
- {service}: {why needed}
- {dependency}: {why needed}

## Pattern Reference
Based on: `{library or framework path}`

## Interface
```
// Key methods and signatures
```

## Data Flow
{How data moves through the component}

## SOLID Principles Applied
- {principle}: {how applied}

## Security Considerations
- {consideration}: {mitigation}

## Acceptance criteria
{None in the hub: items live in architecture/{component}.md, where the coverage gate reads them}
```

## Component Architecture Files

For complex tasks, also creates `architecture/{component}.md`:

```markdown
# Component: {Name}

## Type
{Service / Handler / Repository / Controller / etc}

## Purpose
{What this component does}

## Interface
{Public methods and their signatures}

## Dependencies
{Packages and services required}

## Pattern Reference
{Library or framework example to follow}

## Acceptance criteria
- [ ] {item} — serves: c{n}
- [ ] {item} — supports: {component}
```
One marker per item, never both, never none: `serves:` names a criterion id from the resolved contract,
`supports:` names another component's basename. `scripts/coverage-check.sh` reads these at design close.

## Next Steps

After architecture is complete for this task:
1. Review the design
2. Validate with `/ai-dev-assistant:validate {task_name}`
3. Move to Phase 3: `/ai-dev-assistant:implement {task_name}`

## Related Commands

- `/ai-dev-assistant:research <task>` - Research (Phase 1)
- `/ai-dev-assistant:implement <task>` - Implementation (Phase 3)
- `/ai-dev-assistant:pattern <use-case>` - Get pattern recommendations
- `/ai-dev-assistant:validate <task>` - Validate design
