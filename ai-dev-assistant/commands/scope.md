---
description: "Author or retrofit a task's scope contract (alignment.md) through a structured 4-field conversation — Goal / Expected result / Success criteria / Non-goals. Runs before /research for new tasks, or on-demand for retrofitting existing tasks. Soft-nudge posture: never blocks the task lifecycle. Introduced v3.12.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: <task-name> [--phase 1|2|3]
---

# Scope

Author the alignment contract for a task. Produces `alignment.md` in the task folder per `references/alignment-contract.md` v1.0.

## Usage

```
/ai-dev-assistant:scope <task-name>              # author/retrofit task-level contract
/ai-dev-assistant:scope <task-name> --phase 1    # author phase-level contract (also callable inline from /research /design /implement)
/ai-dev-assistant:scope <task-name> --phase 2
/ai-dev-assistant:scope <task-name> --phase 3
```

Without `--phase`, authors the `## Task-Level` section. With `--phase N`, authors the corresponding `## Phase N — <Research|Architecture|Implementation>` section.

## What this does

1. Resolves `<task-name>` to a task folder using the usual resolver (in-progress folder, epic subfolder, etc.). If the folder does not exist, **scaffold a minimal task stub** (see "Task resolution" below) so brand-new tasks can author scope before `/research` runs.
2. Runs `${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh "<task_folder>"` (Bash) and parses its JSON to read the current state of `alignment.md` (if any).
3. **Overwrite guard** — if the target section already exists, asks before overwriting.
4. Runs the alignment conversation — **one question at a time**, author-authored, never auto-generated.
5. Writes the section to `alignment.md` (creates the file with H1 + metadata if absent).
6. Runs `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task>" "<task_path>"` (Bash) with resolved project + task.
7. Prints next-step hint.

## Task resolution

Accept task names in these forms:
- `<task_name>` — search under `implementation_process/in_progress/` for a folder matching exactly
- `<epic>/<subtask>` — explicit epic-subtask path (inside the epic's `in_progress/`)
- absolute or relative path to a task folder

**Resolution outcomes:**

| Outcome | Behavior |
|---|---|
| Folder exists with `task.md` | Proceed normally — the task is established |
| Folder absent, name validates (`^[A-Za-z0-9_][A-Za-z0-9._-]*$`, no path separators, not `.`/`..`) | **Scaffold a minimal task stub** at `implementation_process/in_progress/<task_name>/task.md` so the scope conversation has a home. See "Stub scaffolding" below. |
| Folder absent, name invalid | Report the validation error and abort. Do not scaffold. |
| Ambiguous match (e.g., same name in two epics) | Report candidate matches and abort. |

This scaffolding-on-miss is required so `/next`'s brand-new-task offer (`commands/next.md` v4.2.3+ "Scope offer for brand-new tasks") can hand off to `/scope` before `/research` creates the folder. Without scaffolding, `/scope` aborts and the user has to skip scope, then run `/research`, then accept the alignment retrofit prompt — which feels like the framework "forgot" the earlier scope offer.

### Stub scaffolding

When scaffolding a missing task folder, write exactly this minimal `task.md` (Phase 1 will replace it with the fuller template at `references/research-walkthrough.md` §"Output"):

```markdown
# Task: <task_name>

**Created:** <YYYY-MM-DD>
**Current Phase:** Phase 0 — Scope

## Goal
_To be authored via `/ai-dev-assistant:scope`. `/ai-dev-assistant:research` will replace this stub with the full Phase 1 tracker._

## Phase Status
- [ ] Phase 0: Scope → See [alignment.md](alignment.md)
- [ ] Phase 1: Research → See [research.md](research.md)
- [ ] Phase 2: Architecture → See [architecture.md](architecture.md)
- [ ] Phase 3: Implementation → See [implementation.md](implementation.md)
- [ ] Phase 4: Review (_review.json) → run `/ai-dev-assistant:review <task>`

## Acceptance Criteria
- [ ] _to be defined_

## Notes
Stub scaffolded by `/ai-dev-assistant:scope` on <YYYY-MM-DD>.
```

`/research` step 2 ("Create task scaffolding") MUST detect this stub (`Current Phase: Phase 0 — Scope` line or the explicit "Stub scaffolded by " note — the same marker family `/migrate-to-epic` stubs carry) and overwrite it with the full template rather than aborting on a pre-existing folder.

The stub intentionally omits a `## Research Questions` section — Phase 1 (`/research`) authors that section. When it does, it is authored as a **numbered list** (one question per `N.` item; never bullets, never mixed styles) so the coverage-mapping gate counts it reliably. Do not add a bulleted Research Questions section to this stub.

Skip stub scaffolding if invoked with `--phase N` — phase-level scope only makes sense on an established task; abort with a hint to run `/ai-dev-assistant:scope <task>` first (task-level) or `/ai-dev-assistant:research <task>` to begin Phase 1.

## Overwrite guard (retrofit case)

Run `${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh "<task_folder>"` (Bash) at start and parse its JSON. Behavior:

| Current state | Target | Behavior |
|---|---|---|
| File missing entirely | any section | Proceed to conversation; the write step creates the file |
| File exists, target section `present: false` | any section | Proceed to conversation; write appends the section |
| File exists, target section `present: true` | any section | **Prompt:** "`alignment.md` already has a `<Section>` section. [o]verwrite / [e]dit / [c]ancel?" |

- `[o]` — discard existing section, run full alignment conversation, overwrite
- `[e]` — show the existing section; loop user into per-field prompts; write back only the fields they touched
- `[c]` — exit without changes; report "No change."

Default answer: `[c]` (cancel). Never overwrite without explicit confirmation.

## alignment conversation — Task-Level

The conversation produces a 4-field contract (Goal / Expected result / Success criteria / Non-goals). It is author-driven — the user's words are the source of truth — but the agent starts from any existing content rather than asking from a blank slate.

**Follow brainstorming convention:** one real question at a time. Never force the user to restate something they've already written. Never silently accept the agent's own draft.

### Step 1 — Read existing context first

Before asking anything, read the task's current content:

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/fm-read.sh "<task_folder>"` (Bash) and parse `.kind`, `.status`, description, dependencies.
2. Read `task.md` body (Goal, Current State, Acceptance Criteria, Research Questions, Notes — whatever exists).
3. Read `alignment.md` via `${CLAUDE_PLUGIN_ROOT}/scripts/alignment-read.sh "<task_folder>"` (Bash) (should be missing or have no Task-Level section, since this command path only runs when we intend to author).

### Step 2 — Decide the conversation mode

Based on what Step 1 surfaced:

| task.md state | Mode | Opening move |
|---|---|---|
| Substantive Goal + ACs (≥40 words of content) | **Reflect-and-refine** | Paraphrase what's there, ask if the paraphrase captures the real driver or if something else is the point |
| Partial content (Goal only, or just a title) | **Draft-and-confirm** | Propose a draft Goal + expected result from available context, ask what's missing or wrong |
| Stub / empty | **Open exploration** | Ask openly what the user wants to achieve; multi-sentence answers welcome; refine iteratively |

The mode determines tone, not script. The agent MUST NOT fall into "ask 5 rigid questions in order" regardless of mode.

### Step 3 — Converse to surface the 4 fields

Operate conversationally. Over however many turns feel natural:

- **Goal** — what problem this solves, why it matters. One to three sentences is fine.
- **Expected result** — what's observable/different when the task ships.
- **Success criteria** — the falsifiable checklist. Propose items as they surface in conversation; confirm at the end.
- **Non-goals** — push proactively. Common drift sources: "Are we also doing X?" / "Is adjacent thing Y in scope?" / "Does this include migrating the existing data?". Non-goals prevent scope creep later — worth pulling a few out explicitly even if the user didn't mention them.

The agent MAY propose drafts for any field after gathering enough context, but always marks them as drafts and asks for correction.

### Step 4 — Assemble a draft and show it

When the 4 fields feel substantively covered, assemble the full `## Task-Level` section and show it verbatim to the user. Not a summary — the actual markdown that would be written.

### Step 5 — Confirm, edit, or cancel

> "Here's the task-level scope as I understood it (shown above). Write it to `alignment.md` as-is, edit a specific field, or cancel? [y]es / [e]dit / [c]ancel"

- `[y]` — write the file (see "Writing alignment.md" below).
- `[e]` — ask which field needs revision (Goal / Expected result / Success criteria / Non-goals), loop back to Step 3 for just that field, reassemble, re-confirm.
- `[c]` — abort; no write.

## alignment conversation — Phase-level (`--phase N`)

Same 4 fields, scope-adjusted to one phase. Same conversation modes (reflect-and-refine / draft-and-confirm / open exploration) based on what's already in `task.md`, `research.md`, or `architecture.md` for that phase.

Scope-adjusted wording:

- **Goal** — for research: what question(s) must research answer? For architecture: what design decisions does this phase commit to? For implementation: what will this phase actually build?
- **Expected result** — what will `research.md` / `architecture.md` / `implementation.md` contain when the phase is done?
- **Success criteria** — falsifiable per-phase criteria, not task-level ones
- **Non-goals** — investigations / design decisions / implementation scope explicitly deferred to a later phase or task

The phase-level agent MUST assume task-level scope already exists and NOT re-ask task-level questions. Phase-level is narrower: "given the task-level contract, what does THIS phase alone deliver?"

Confirm prompt:
> "Here's the Phase N scope (shown above). Write it to `alignment.md` as a `## Phase N — <Research|Architecture|Implementation>` section, edit a specific field, or cancel? [y]es / [e]dit / [c]ancel"

## Writing `alignment.md`

**File doesn't exist yet:**

Create the file with:

```markdown
# Alignment: <task_name>

**Task:** <task_name>
**Created:** <YYYY-MM-DD>

<section>
```

Where `<section>` is the H2 block you just authored.

**File exists, target section doesn't:**

Insert the new section preceded by a blank line, positioned in chronological order:

| Target | Insertion rule |
|---|---|
| `## Task-Level` | Insert immediately after the `**Created:**` metadata line (or after the H1 if metadata absent). If any `## Phase N` already exists, the new Task-Level MUST still precede it. |
| `## Phase 1 — Research` | Insert before the first later phase H2 (Phase 2 or Phase 3). If no later phase H2 exists, append at EOF. If only Task-Level exists, append at EOF. |
| `## Phase 2 — Architecture` | Insert before `## Phase 3 — Implementation` if present, else append at EOF. |
| `## Phase 3 — Implementation` | Always append at EOF. |

Rule of thumb: scan the file for `## Phase` headers in order; insert the new section immediately before the first header whose phase number is higher than the one being written.

**File exists, target section exists (overwrite case):**

Delete the existing H2 block (from `## <Section>` up to but not including the next `## ` or EOF). Insert the new section in the same position.

**Em-dash canonicalization on every write pass.**

Always emit `—` (U+2014) in phase H2 headers (`## Phase 1 — Research`, etc.). Additionally, on ANY write pass (create, append, or overwrite), scan the file for phase H2 headers that use hyphen (`-`) or en-dash (`–`) and rewrite them to em-dash. The reader accepts all three variants, but writes standardize on em-dash so diffs stay clean over time.

**File exists, reader returned `unknown_section` or other structural warnings:**

Before appending, surface the warnings to the user:

> `alignment.md` has structural warnings from the reader:
>   - unknown_section: `Custom Heading`
>   - success_criteria_not_checklist (task_level)
> Continue writing the new section? [y]es / [n]o

Default answer: `[y]` (the warnings don't block; the user may have intentionally authored extra content). Record this decision in the session; don't re-prompt on the same run.

## Session context

After writing (or cleanly cancelling), run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-write.sh "<project_name>" "<project_folder>" "<task>" "<task_path>"` (Bash) with the resolved project + task so compaction hooks can restore focus. **Omit the 5th arg** (epic) so the preserve-sentinel `{CURRENT_EPIC_OR_NULL}` applies and the existing `currentEpic` is kept.

## Next-step hint

After a successful write, print:

- Task-level: `"Scope contract written. Next: /ai-dev-assistant:research <task>"`
- Phase N: `"Phase N alignment written. Next: continue with /ai-dev-assistant:<research|design|implement> <task>"`

Optionally add one line (never auto-runs `/goal`): `"You can later drive implementation to done with a /goal condition built from this contract — surfaced at /implement; see references/goal-from-scope.md."`

## Errors & edge cases

| Scenario | Behavior |
|---|---|
| Task folder missing, name validates | Scaffold stub task.md (see "Stub scaffolding") and continue; report `Scaffolded new task folder: <path>` |
| Task folder missing, name invalid | Report validation error; abort. Do not scaffold. |
| Task folder missing, `--phase N` provided | Abort with: "Phase-level scope requires an existing task. Run `/ai-dev-assistant:scope <task>` (task-level) first, or `/ai-dev-assistant:research <task>` to begin Phase 1." |
| Ambiguous match across epics | Report candidate matches; abort |
| User hits Ctrl-C mid-conversation | No partial write; `alignment.md` untouched. If the stub was just scaffolded this run, leave it — it's a valid starting point for a later retry. |
| `--phase N` with N outside 1–3 | Report error; abort |
| `alignment.md` unreadable (permissions) | Reader returns `error` warning; surface to user; abort |
| User provides prose instead of checklist for success criteria | Accept prose; reader will later surface `success_criteria_not_checklist` warning — do NOT re-prompt in `/scope`, that's passive-aggressive |

## Related

- `references/alignment-contract.md` — canonical grammar + warning codes
- `alignment-reader` skill — the JSON contract this command reads
- `/ai-dev-assistant:research` — pre-analysis hook branches on `scope_contract_recommended` and calls this command inline
- `/ai-dev-assistant:design`, `/ai-dev-assistant:implement` — call with `--phase 2` / `--phase 3` as first sub-step
- `analysis-agent` — emits `scope_contract_recommended` signal that triggers the soft nudge

## Discoverability

- README Commands table
- Command frontmatter `description` (this file)
- `/ai-dev-assistant:next` mentions `/scope` as a retrofit option when the selected task has no `alignment.md`
- CONVENTIONS.md alignment section

## Do NOT

- Do not auto-generate any of the 4 fields. Claude MAY propose a draft, but user's reply is the final text.
- Do not block the task lifecycle. If the user says no, proceed without writing.
- Do not write partial sections. A section is either fully written (all 4 fields present, even if empty) or not written at all — the reader's `empty_field` warning is for humans who chose to leave a field blank, not for interrupted writes.
- Do not merge multiple phase sections in one invocation. `--phase` takes a single value.
