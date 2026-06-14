# Research — Full Walkthrough

Tutorial-depth reference for the `/ai-dev-assistant:research` command. The runtime command body (see `commands/research.md`) is a terse imperative summary; this file documents every sub-step, rationale, version history, and worked example in full.

**Loaded only when explicitly read.** No hook or skill auto-loads this file.

> **Note:** The orchestration engine is stack-agnostic. The concrete examples below (drupal.org / contrib search, `core-pattern-finder`, the Drupal worked examples) reflect the **Drupal-flavored components** the framework ships with today; stack-neutral versions are in progress.

---



Research existing solutions for a specific task (Phase 1 of a task).

## Usage

```
/ai-dev-assistant:research <task-name>
```

## What This Does (v3.0.0, with v3.11.0 pre-analysis hook, v4.0.0 always-on validation gate + coverage-mapping requirement)

1. **Pre-analysis validation gate** (v4.0.0+, always-on, non-bypassable) — `analysis-agent` is invoked unconditionally on every new-task `/research`; strong signals are informational only and recorded in `signals_used[]`. See "Pre-analysis validation gate" section below.
2. Creates task directory: `implementation_process/in_progress/{task_name}/`
3. Creates `task.md` (tracker with links and acceptance criteria)
4. **(v3.13.4+)** Dev-guides pre-flight — explicit `guide-integrator` invocation + always-prompt the user to continue / add / decline (see "Dev-guides pre-flight" section below)
5. Invokes `contrib-researcher` agent for drupal.org/contrib search
6. Invokes `core-pattern-finder` skill for core examples
7. Stores findings in `research.md` file
8. Updates `task.md` to mark Phase 1 as in progress
8. Updates `project_state.md` with current task
9. **(v3.13.5+)** Post-research epic check (see "Post-phase epic check" below) — re-runs `analysis-agent` in folder mode with the now-complete task context and surfaces `epic_candidate` if the research revealed epic-shaped work that pre-analysis couldn't see at task-creation time
10. **(v3.13.4+)** Offers an opt-in traceability walkthrough (see "Traceability walkthrough sub-step" below) mapping `research.md` sections to the task's research questions + acceptance criteria
11. **Invokes `session-context-writer` skill with the resolved project and task**

## Post-phase epic check (v3.13.5+)

**Run after `research.md` has been authored and `task.md` / `project_state.md` updated, before the traceability walkthrough.**

Purpose: pre-analysis at task-creation time has very thin signal (just the task name, sometimes a short description). The real scope-shape only emerges during research — `alignment.md` pins down what the task is about, and `research.md` surfaces sub-problems, dependencies, and natural decomposition seams. **Research is the moment epic-vs-flat is actually decidable.**

This step catches the "task started flat, research revealed it's actually an epic" case that the v3.11.0 pre-analysis hook + v3.12.2 alignment retrofit both miss.

### Step 1 — Re-invoke analysis-agent in folder mode

Invoke `analysis-agent` via Task tool with:

- `task_folder` = absolute path to the task folder (the folder now contains `task.md` + `alignment.md` + `research.md` — maximum context the agent has ever had for this task)
- `codePath` = resolved via `project-state-reader` on the active project
- `schema_version: "1.0"`

### Step 2 — Branch on `decision`

- `epic_candidate` → continue to Step 3 (surface offer)
- `keep_flat` → proceed silently to traceability walkthrough. Agent saw full context and decided this task is correctly flat. Trust it.
- `insufficient_info` → proceed silently. Unusual at this stage (research.md exists) but possible if artifacts are very thin. No nag.

### Step 3 — Surface epic offer (only if `epic_candidate`)

Print:

> **Before locking in research:** based on what research found, this task looks like it'd be cleaner as an epic with sub-tasks. Pre-analysis at task-creation couldn't see this shape — research is where it became clear.
>
> Proposed children (from `analysis-agent.proposed_decomposition`):
>   • `<child_1>` — <short rationale>
>   • `<child_2>` — <short rationale>
>   • …
>
> **[y]es** — convert to epic now via `/migrate-to-epic <task> --children "<list>"`. `research.md` stays on the parent epic; children inherit no research yet and will each get their own `/research` pass.
> **[n]o** — keep flat; proceed to traceability walkthrough (can always migrate later via `/propose-epics` or `/migrate-to-epic`)
> **[d]iscuss** — show agent's full `rationale` + `signals_used[]` before deciding

Default: `[n]`.

### Step 4 — Act on the answer

- `[y]` → invoke `/ai-dev-assistant:migrate-to-epic <task> --children "<comma-separated proposed names>"`. After successful migration, **stop** — the flat-task lifecycle ends here. User re-invokes `/research <child_name>` on each child when ready.
- `[n]` → proceed to traceability walkthrough.
- `[d]` → print agent's rationale + signals_used. Re-ask Step 3.

### Notes

- **Never blocks.** `[n]` (default) always proceeds to traceability walkthrough.
- **Authoritative over pre-analysis.** If pre-analysis said "keep flat" and end-of-research says "epic_candidate," trust the later call — it has strictly more context.
- **Migration is transactional.** `/migrate-to-epic` is atomic with 24h rollback; safe to opt into.

## Coverage-mapping validation gate (v4.0.0+)

**This gate is non-bypassable.** Same anti-bypass clause as pre-analysis.

**Run after `research.md` has been authored, before the post-research epic check + traceability walkthrough.** Verifies `research.md` contains the required `## Coverage Mapping` H2 section that maps each Research Question from `task.md` to the section(s) of research.md that address it.

### Step 1 — Run the deterministic check

```bash
RESULT=$("${CLAUDE_PLUGIN_ROOT}/scripts/coverage-mapping-check.sh" "<task_folder>")
```

Output per `references/gate-audit-schema.md`: `verdict: pass | fail`, `research_questions_found`, `research_questions_addressed`, `missing_questions[]`, `warnings[]`.

### Step 2 — Branch on verdict

- `pass` → write audit with `user_choice: "phase_marked_complete"`; proceed to post-phase epic check.
- `fail` → display literal `prompts:coverage-mapping-fail` template from `references/gate-hardening-prompts.md`. Substitutions: `{{missing_questions}}` from script output. Block on user response:
  - `[a]bort` → write audit with `user_choice: "phase_left_incomplete"`; refuse to mark Phase 1 `[x]` in task.md; print actionable instructions; exit 1.
  - `[s]kip` → prompt user for bypass reason (free-text); write audit with `user_choice: "bypassed"` and `bypass_reason: <reason>`; allow Phase 1 `[x]` to be marked but with bypass visible in `/audit-status`.

### Step 3 — Audit always written

Whether pass, fail, or bypassed, write `<task>/_coverage-mapping.json` via `gate-audit-write.sh`. Absence of audit file = bypass-by-declaration (visible in `/audit-status` Unaudited gates).

### Skip flag

`/research <task> --skip-coverage-check <reason>` skips the gate entirely; writes audit with `user_choice: "bypassed"` and the supplied reason. Recorded but not blocked.

## Traceability walkthrough sub-step (v3.13.4+)

**Run after `research.md` has been authored and `task.md` / `project_state.md` updated, before `session-context-writer` is invoked.**

Purpose: let the user see, at a glance, how each research question (and each task-level acceptance criterion, if one exists) is addressed by the freshly-authored research — without having to read the whole artifact and cross-reference by hand.

### Step 1 — Ask (opt-in)

Print the one-line prompt:

> **Walk through how this research answers the task's questions and acceptance criteria?** [y]es / [n]o

Default: `[n]`.

If `[n]` → skip the walkthrough; proceed to session-context-writer.

### Step 2 — Build the mapping

On `[y]`:

1. **Pull the traceability sources** using this priority:
   - `task.md` → Research Questions list (extract the list items under that heading — ordered `1.`/`2.` items OR `-`/`*`/`+` bullets, with the marker prefix stripped; the canonical authored style is numbered)
   - `alignment-reader` → `sections.task_level.success_criteria[]` (each carries `{text, checked}`)
   - If both sources are empty → "This task has no research questions or acceptance criteria declared. Walkthrough can't map without them; consider `/scope <task>` to add task-level criteria."
2. **For each item (question or criterion)**, scan `research.md` — and any `research/<subject>.md` files when the research was split — and identify the section(s)/file(s) that address it. Look for:
   - the `## Coverage Mapping` rows in the `research.md` hub (the authoritative question → research map)
   - Q-headings that match (e.g., `### Q1 — Playwright MCP concurrency` ↔ a Research Question about MCP concurrency)
   - Decision-log entries
   - a `research/<subject>.md` file whose subject answers the item
   - Cross-cutting pattern numbers / evidence references
3. **Honest mapping.** If a question or criterion has no clear section in `research.md`, mark it **"NOT YET ADDRESSED"** — do not invent a reference. Flag it for the discussion step.

### Step 3 — Print the table

Format:

```
Research addresses these questions and criteria:

  Q1 "<first 60 chars>…"  →  research.md Q1 + decision log #1
  Q2 "<first 60 chars>…"  →  research.md Q2 + pattern 1
  AC #1 "<first 60 chars>…"  →  research.md decision #7
  AC #2 "<first 60 chars>…"  →  — NOT YET ADDRESSED — raise in Phase 2?
  …
```

Separate Q-rows from AC-rows. Section references are lightweight — just enough to jump to the right place.

### Step 4 — Three-way prompt

After the table, ask:

> **[c]ontinue** — looks right, proceed to session-context-writer
> **[r]evise** — something's wrong or missing; let's edit `research.md` before continuing
> **[d]iscuss** — not sure, let's talk through one or more rows before deciding

Default: `[c]`.

- `[c]` → proceed.
- `[r]` → ask the user which row(s) need revision. Make the edit to `research.md` inline. Re-print the table, re-ask Step 4.
- `[d]` → talk through selected rows one at a time; re-ask Step 4 after discussion.

### Notes

- **Never blocks.** `[n]` in Step 1 or `[c]` in Step 4 always proceeds.
- **No schema writes.** Print-and-optionally-edit flow. Only persists edits the user approves under `[r]`.
- **Opt-in by design.** Skip for routine work; use for complex tasks or sanity-checks before locking Phase 1.

## Task-Based Workflow

**This command operates on a TASK, not the project.**

Each task goes through:
1. **Research** (this command) → Find patterns, existing solutions
2. **Architecture** (`/design`) → Design the approach
3. **Implementation** (`/implement`) → Build with TDD

## Examples

```
/ai-dev-assistant:research settings_form
/ai-dev-assistant:research content_entity
/ai-dev-assistant:research field_formatter
```

## Output (v3.0.0)

Creates folder structure:
```
implementation_process/in_progress/{task_name}/
├── task.md         # Tracker
└── research.md     # Phase 1 findings
```

**Per-subject research files (v4.10.0+).** Each distinct subject the research
investigates gets **its own file** under `research/` — one file per subject,
named after that subject. `research.md` is the **index/hub**: it does not
restate the detail, it synthesizes and links. This keeps each `/design` or
`/implement` read targeted (load only the subjects that phase needs) instead of
pulling one monolithic file:
```
implementation_process/in_progress/{task_name}/
├── task.md
├── research.md            # Index/hub: Problem Statement, the index table,
│                          #   Recommendation, Decision Log, Coverage Mapping
└── research/
    ├── <subject-a>.md      # full findings for one researched subject
    ├── <subject-b>.md      # full findings for another
    └── <subject-c>.md
```
A `<subject>` is whatever was investigated as a unit — an existing third-party
library, an integration approach, a framework (first-party) subsystem, a
competing option. Each subject file
holds that subject's complete findings (what it is, how it would apply, fit
assessment, evidence). When research genuinely covered a single subject, a
flat single-file `research.md` is still fine — the split exists to stop
unrelated subjects from sharing one token-heavy file.

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
- [ ] Phase 4: Review (_review.json) → run `/ai-dev-assistant:review <task>` (v4.1.0+)

## Acceptance Criteria
- [ ] {criterion 1}
- [ ] {criterion 2}

## Research Questions
1. {first question research must answer}
2. {second question research must answer}

## Related Tasks
None

## Notes
{Any additional notes}
```

**Research Questions list style (strict writer).** Always emit the `## Research
Questions` section as a **numbered list** — one question per `N.` item (`1.`,
`2.`, …). Do not use bullets and do not mix styles. Numbered is canonical
because it is coherent with the `Q1`/`Q2` references and the `### Q1 —`
research.md headings used elsewhere in this walkthrough, and it is the form the
coverage-mapping gate's question count depends on being authored consistently.
(The coverage-mapping reader is tolerant of any list marker — see the
"Coverage-mapping validation gate" section — but the writer commits to one.)

**research.md** — the index/hub. It synthesizes; it does not restate each
subject's detail. The per-subject findings live in `research/<subject>.md`.

```markdown
# Research: {task_name}

## Problem Statement
What we're trying to solve.

## Research Index
| Subject | File | One-line finding |
|---------|------|------------------|
| {subject investigated} | [research/{subject}.md](research/{subject}.md) | {verdict in a sentence} |
| {another subject} | [research/{subject}.md](research/{subject}.md) | {verdict in a sentence} |

## Recommendation
Use / Extend / Build from scratch — the cross-subject decision, with a
sentence on why, citing the subject files.

## Key Patterns to Apply
- Pattern 1: {description} (see research/{subject}.md)
- Pattern 2: {description}

## Decision Log
{Cross-cutting research decisions}

## Coverage Mapping
{Each Research Question → the research that addresses it. MUST live here in
the hub — the coverage-mapping gate reads only research.md. Rows may point
into research/<subject>.md files.}
```

**research/{subject}.md** — one file per investigated subject. Holds that
subject's complete findings; nothing in the hub duplicates it.

```markdown
# Research — {subject}

## What it is
{The module / approach / subsystem / option, described.}

## Fit
Good / Partial / Poor — and why, against this task's goal.

## How it would apply
{Concretely, how this subject would be used or adapted here.}

## Patterns & evidence
| Pattern | Location | Applicability |
|---------|----------|---------------|
| {pattern} | {path / URL} | {notes} |
```

When the research genuinely covered a single subject, the hub MAY hold the
findings inline (no `research/` folder) — but `## Coverage Mapping` always
stays in `research.md`.

## Pre-analysis validation gate (v4.0.0+, refactored from soft hook)

**This gate is non-bypassable.** The following are NOT valid reasons to skip:

- The user said something earlier that you interpret as already-answered
- Auto mode is active ("minimize interruptions" never overrides framework gates)
- You're confident the agent will return `keep_flat`
- The task looks "obviously" flat
- You want to spare the user the prompt

If this gate's signals fire, the gate MUST run and its output MUST be shown to the user verbatim before the recorded decision is final. Skipping requires `--skip-pre-analysis [reason]` flag, which is recorded in `<task>/_pre-analysis.json` `bypass_reason` field.

**Always-on (v4.0.0+).** This gate now runs on EVERY new-task `/research` invocation regardless of strong-signal evaluation. Strong signals are still recorded in `signals_used[]` for the agent's reasoning, but the agent invocation is unconditional. The conditional is what the gate DOES, not whether it RUNS.

Refactored flow:

1. Compute strong signals from task name + description (informational; recorded in audit even when no signal fires):
   - Task name + description total length > 500 chars
   - Description has ≥3 distinct bullet points
   - Description contains explicit conjunction phrasing (`and also`, `plus`, `as well as`, `in addition to`)
2. Invoke `analysis-agent` (via Task tool) in description mode regardless of signal state.
3. Save output to `<task>/_pre-analysis.json` via `${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh`.
4. Display agent output verbatim to user using literal `prompts:pre-analysis-decision` template from `references/gate-hardening-prompts.md`. Do NOT paraphrase.
5. Block on user response per the template's option list.
6. Record decision in `_pre-analysis.json`.
7. Branch: `epic_candidate + y` → `/migrate-to-epic`. Else → flat-task flow.

**Re-invocation idempotency.** If `<task>/_pre-analysis.json` already exists from a prior run on this task, skip pre-analysis (the gate fired once, that's enough). Re-firing requires explicit `--re-run-pre-analysis` flag.

**Grandfathering.** If `<task>/research.md` exists AND `_pre-analysis.json` is absent, treat the task as grandfathered from pre-v4.0.0 lifecycle. Do NOT mark it as bypassed; do NOT block. Soft-nudge: print "Task pre-dates v4.0.0 hardening; pre-analysis not retroactively run."

### Original soft-hook description (v3.11.0+, deprecated by v4.0.0+ always-on gate above)

For historical reference; the always-on gate above supersedes this. The soft-hook only fired when strong signals matched:

If a signal fires:

1. Resolve `codePath` via `project-state-reader` on the active project. If unknown, skip detect+confirm here (too intrusive at task-creation time); agent runs with `code_read: false` / `confidence: low`.
2. Invoke `analysis-agent` (via Task tool) in **description mode** — pass `task_description_text` (the task name + full description as typed by the user), the codePath (or null), and `schema_version: "1.0"`. **Do NOT pass a task_folder** — the folder does not exist yet at pre-analysis time. See `references/analysis-agent-schema.md` the "Input modes" section.
3. Parse the agent's JSON output per `references/analysis-agent-schema.md` v1.0. Expect `task_folder: "(pre-creation)"` in the output.
4. Branch on `decision`:
   - `epic_candidate` → ask the user: *"This task's scope looks like it might warrant being an epic. Agent proposed N children: [list]. Create as epic with these children? [y/n/standard flat task]"*. On `y`, invoke `/ai-dev-assistant:migrate-to-epic <task_name> --children "<proposed names>"` (which will create the epic directly — no flat task created first). On `n` or `standard`, proceed with flat-task research.
   - `keep_flat` → proceed silently with flat-task research.
   - `insufficient_info` → proceed with flat-task research; the task description alone wasn't sufficient for decomposition judgment (makes sense at creation time — usually the description IS minimal here).

5. **(v3.12.0+)** After the `decision` branch completes (regardless of outcome unless the task became an epic), inspect `signals_used[]` for `scope_contract_recommended`. If present, print soft-nudge in plain language — explain WHY before asking:
   > **Before I dig into research:** this task looks scope-heavy (multiple deliverables, or details that can be read several ways). Want to pin down what it's really trying to deliver first?
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
   > **[n]o** — research as-is (we can always add this later)
   > **[later]** — skip for now; `/scope <task>` anytime

   On `[y]` → execute the alignment conversation + write flow as documented in `commands/scope.md` (context-aware task-level conversation + "Writing alignment.md") within this command's context. Do NOT try to shell out to a sibling slash command. After the write completes, continue with the standard research flow.
   On `[n]` → proceed without writing `alignment.md`. No nag.
   On `[later]` → same as `[n]` for this run; user can run `/scope <task>` anytime.

Conservative by design: pre-analysis only fires on strong signals, and even then the default choice presented to the user is to proceed as a flat task. Never creates an epic without explicit confirmation. The alignment nudge is soft; `[n]` is always respected.

## Dev-guides pre-flight (v3.13.4+)

**Run after the Pre-analysis hook, before the Phase 1 alignment sub-step.** The goal: every phase command either loads dev-guides or has the user explicitly say "no guides" — never a silent skip. Dev-guides cover Drupal, Next.js, design systems (Bootstrap, Radix, Tailwind, DaisyUI), CSS, and cross-cutting methodology (TDD, SOLID, DRY, security, quality gates) — relevant across Drupal AND non-Drupal (plugin framework, docs-only, Claude Code) tasks.

### Step 1 — Invoke guide-integrator explicitly

**(v4.0.0+: deterministic detection.)** Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh <task_folder>` BEFORE prompting the user. The script emits `keywords_matched[]` + `guides_to_load[]` from a deterministic grep of task content against `guide-integrator` Auto-Load Rules. The agent does NOT decide whether keywords matched — the script does. This eliminates bypass-by-declaration (agent claiming "none matched" without running detection).

After detection, populate Step 2's prompt's "Auto-loaded based on task keywords:" line with `guides_to_load[]` from the script output. After the user's `[c]/[a]/[n]` choice, write a `dev-guides-load` audit:

```bash
# Build audit JSON; user_choice is c|a|n; guides_actually_loaded reflects [n]'s clearing
"${CLAUDE_PLUGIN_ROOT}/scripts/gate-audit-write.sh" "<task_folder>" "dev-guides-load" "$AUDIT_JSON"
```

**(v3.15.0+, refactored v4.0.0+)** `guide-integrator` v5.1.0+ ALSO loads the project's active playbook sets (per `Playbook Sets` in `project_state.md`) and the local user playbook (per `User Playbook`) — but this load is now **deterministic** via `${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh <project_folder>`. The script emits `playbook_sets_loaded[]`, `user_playbook_loaded`, `plays_by_section{}`, written as `<task>/_playbook-load.json` audit. Surface conflicts once-per-session per topic (precedence: local > active set > generic dev-guide); persist to `<project>/.claude/playbook-conflicts.log` via `scripts/playbook-conflicts-write.sh`. See `references/playbook-schema.md`, `references/playbook-conflict-schema.md`, and `references/gate-audit-schema.md` v1.0.

### Step 2 — ALWAYS prompt the user (never silent-skip)

Regardless of whether guide-integrator auto-loaded 0, 1, or N guides, print:

> **Dev-guides pre-flight for `<task_name>` (Phase 1 — Research):**
>
> Auto-loaded based on task keywords:
>   <bulleted list of loaded guides, OR "  — none auto-matched —">
>
> Dev-guides cover Drupal (forms, entities, plugins, services, caching, views, JSON:API, etc.), Next.js, design systems (Bootstrap, Radix, Tailwind, DaisyUI), CSS, and methodology (TDD, SOLID, DRY, security, quality gates). Loading relevant guides before research keeps findings grounded in existing knowledge and prevents re-research of known patterns.
>
> **[c]ontinue** — auto-loaded set is fine, start research
> **[a]dd** — scan the `dev-guides-navigator` catalog for more topics before I research
> **[n]one** — skip dev-guides entirely (override any auto-loaded); I'll rely on you

Default: `[c]`.

### Step 3 — Act on the answer

- `[c]` → proceed to the alignment sub-step with the auto-loaded guides (possibly empty).
- `[a]` → invoke `dev-guides-navigator` interactively with task keywords the user supplies. Let the user select 0 or more additional guides. Load them via `guide-integrator`. After the user says "done," proceed to alignment.
- `[n]` → clear any auto-loaded guides from the session context (do NOT persist them to `loadedGuides[]`). Note "dev-guides declined" in session. Proceed to alignment.

### Notes

- **Never blocks.** `[c]` (default) always proceeds.
- **Discoverability > compliance.** `[n]` is a first-class choice.
- **Works for non-Drupal tasks.** Plugin/framework/docs tasks can still find applicable methodology or design-system guides via `[a]`.

## Phase 1 alignment sub-step (v3.12.0+, retrofit-aware in v3.12.2+)

**First action of Phase 1 proper** (after the task directory is created and the pre-analysis hook has settled):

1. Invoke `alignment-reader` skill against the task folder.

2. **Task-level retrofit check (v3.12.2+)** — if the task folder ALREADY existed before this `/research` invocation (i.e., the user is running `/research` on a pre-existing flat task created outside the hook flow, NOT a fresh task just created by this command) AND `sections.task_level.present: false` AND the pre-analysis hook did NOT run this session → invoke `analysis-agent` in **folder mode** (`task_folder` set to the task directory, `codePath` resolved via `project-state-reader`, `schema_version: "1.0"`). Inspect the returned `signals_used[]` for `scope_contract_recommended`.

   - If present → print soft-nudge in plain language:
     > **Before I dig into research:** this task has no task-level scope recorded yet, and I'm seeing signals that scope could drift (multiple distinct deliverables, or a description that reads several ways). Want to pin down what it's really trying to deliver first?
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
     > **[n]o** — research as-is (we can always add this later)
     > **[skip]** — same as no, but quieter about it
     Default: `[skip]`.
     - On `[y]` → execute the task-level flow from `commands/scope.md` (context-aware task-level conversation + "Writing alignment.md" for the `## Task-Level` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, refresh `alignment-reader` output so subsequent steps see the new section.
     - On `[n]` / `[skip]` → proceed; record "task-level retrofit declined" for this run.
   - If absent → proceed silently (no warrant — task is self-contained).
   - If analysis-agent fails or times out → proceed silently; do NOT nag the user.

   Skip this check entirely on fresh tasks where the pre-analysis hook fired (redundant) or where `task_level.present` is already `true` (already authored).

3. Decide whether to offer a research-specific scope. All prompts use plain language that explains WHAT the choice means:
   - If `sections.phase_1.present: true` → print: `"You already scoped this phase earlier. Using that scope."` and proceed.
   - Else if `sections.task_level.present: true` (including freshly authored in step 2) → ask:
     > **Before I start research:** you've already scoped the task. Want to also scope *just this research pass* — what it's trying to answer vs what it's leaving for later?
     >
     > Useful when research has many threads; often not needed. Shape of the result:
     >
     > ```
     > Phase 1 — Research
     > Goal: <what this research pass is answering>
     > Expected result: <e.g., "a research.md recommending one option with citations">
     > Done when: <observable signal, e.g., "≥2 concrete code references">
     > Won't decide here: <pushed to Phase 2, e.g., "which option to actually build">
     > ```
     >
     > **[y]es** — 4 questions now
     > **[n]o** — start research (can always add this later)
     Default: `[n]` (most tasks don't need a separate research sub-scope).
   - Else if pre-analysis hook emitted `scope_contract_recommended` and user declined task-level scope earlier → re-offer lighter-touch:
     > **Before I start research:** you skipped the full task-level scope earlier. Want to scope *just this research pass* instead? (Lighter — only what research is trying to answer.)
     >
     > Shape of the result:
     >
     > ```
     > Phase 1 — Research
     > Goal: <what this research pass is answering>
     > Expected result: <e.g., "a research.md recommending one option with citations">
     > Done when: <observable signal>
     > Won't decide here: <pushed to Phase 2>
     > ```
     >
     > **[y]es** — 4 questions now
     > **[n]o** — start research as-is
     Default: `[n]`.
   - Otherwise → proceed silently (no nag).

4. If user says `[y]`, execute the `--phase 1` flow from `commands/scope.md` (context-aware phase-level conversation + "Writing alignment.md" for the `## Phase 1 — Research` section) within this command's context. Do NOT shell out to the sibling slash command. After the write, continue with research.

5. If user says `[n]` / `[skip]`, proceed with research. Never block.

## Next Steps

After research is complete for this task:
1. Review findings
2. Move to Phase 2: `/ai-dev-assistant:design {task_name}`

## Related Commands

- `/ai-dev-assistant:design <task>` - Design architecture (Phase 2)
- `/ai-dev-assistant:next` - See recommended next action
- `/ai-dev-assistant:propose-epics` - (v3.11.0+) Bulk-review existing tasks for epic-ification candidates; counterpart to this command's inline pre-analysis
