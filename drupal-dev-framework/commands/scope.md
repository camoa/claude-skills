---
description: "Author or retrofit a task's scope contract (alignment.md) through a structured 4-field conversation — Goal / Expected result / Success criteria / Non-goals. Runs before /research for new tasks, or on-demand for retrofitting existing tasks. Soft-nudge posture: never blocks the task lifecycle. Introduced v3.12.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: <task-name> [--phase 1|2|3]
---

# Scope

Author the alignment contract for a task. Produces `alignment.md` in the task folder per `references/alignment-contract.md` v1.0.

## Usage

```
/drupal-dev-framework:scope <task-name>              # author/retrofit task-level contract
/drupal-dev-framework:scope <task-name> --phase 1    # author phase-level contract (also callable inline from /research /design /implement)
/drupal-dev-framework:scope <task-name> --phase 2
/drupal-dev-framework:scope <task-name> --phase 3
```

Without `--phase`, authors the `## Task-Level` section. With `--phase N`, authors the corresponding `## Phase N — <Research|Architecture|Implementation>` section.

## What this does

1. Resolves `<task-name>` to a task folder using the usual resolver (in-progress folder, epic subfolder, etc.).
2. Invokes `alignment-reader` skill to read the current state of `alignment.md` (if any).
3. **Overwrite guard** — if the target section already exists, asks before overwriting.
4. Runs the alignment conversation — **one question at a time**, author-authored, never auto-generated.
5. Writes the section to `alignment.md` (creates the file with H1 + metadata if absent).
6. Invokes `session-context-writer` skill with resolved project + task.
7. Prints next-step hint.

## Task resolution

Accept task names in these forms:
- `<task_name>` — search under `implementation_process/in_progress/` for a folder matching exactly
- `<epic>/<subtask>` — explicit epic-subtask path (inside the epic's `in_progress/`)
- absolute or relative path to a task folder

If the task doesn't resolve, report the options and abort.

## Overwrite guard (retrofit case)

Invoke `alignment-reader` at start. Behavior:

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

Follow brainstorming convention: **one question at a time**. The user's reply is the source of truth. You MAY draft a Goal or Non-goals suggestion after gathering context, but mark it as "Here's a draft — please edit or replace" — never silently accept your own suggestion.

Prompts, in order:

1. **Goal.** Ask:
   > "What is the single-sentence Goal of `<task>`? (What problem does this solve? Start with a verb.)"

   Append reply verbatim to the `### Goal` field body.

2. **Expected result.** Ask:
   > "What Expected Result will be observable when this task ships? Describe the after-state in 1–3 sentences."

   Append reply to `### Expected result`.

3. **Success criteria.** Ask:
   > "List the Success Criteria — falsifiable statements, each one checkable. One per line. Hit enter on an empty line when done."

   Collect lines until blank line. Format each as `- [ ] <text>`. Append under `### Success criteria`.

4. **Non-goals.** Ask:
   > "Any explicit Non-Goals? Things people might assume are in scope but aren't. One per line; empty line to finish."

   Collect lines until blank line. Format each as `- <text>`. Append under `### Non-goals`.

5. **Confirm and write.** Show the assembled Task-Level section and ask:
   > "Write this `## Task-Level` section to `alignment.md`? [y]es / [e]dit / [c]ancel"

   - `[y]` — write the file (see "Writing alignment.md" below)
   - `[e]` — ask which field to edit (Goal / Expected result / Success criteria / Non-goals), re-run that prompt, re-assemble, re-confirm
   - `[c]` — abort cleanly; no write

## alignment conversation — Phase-level (`--phase N`)

Same 4 fields, scope-adjusted wording. Use "this phase's <research|architecture|implementation>" in place of "this task" throughout.

Phase 1 example:
1. "Goal of **this phase's research**: what question(s) must this research answer?"
2. "Expected Result of research: what will `research.md` contain when done?"
3. "Success Criteria for research — falsifiable statements. One per line; empty line to finish."
4. "Non-Goals for research — investigations explicitly out of scope. One per line; empty line to finish."
5. "Write this `## Phase 1 — Research` section to `alignment.md`? [y]es / [e]dit / [c]ancel"

Phase 2 and Phase 3 substitute "architecture"/"implementation" (and `## Phase 2 — Architecture` / `## Phase 3 — Implementation` in the H2 header and confirm prompt).

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

After writing (or cleanly cancelling), invoke `session-context-writer` skill with the resolved project + task so compaction hooks can restore focus. Pass `{CURRENT_EPIC_OR_NULL}` as the epic sentinel per the skill's contract.

## Next-step hint

After a successful write, print:

- Task-level: `"Scope contract written. Next: /drupal-dev-framework:research <task>"`
- Phase N: `"Phase N alignment written. Next: continue with /drupal-dev-framework:<research|design|implement> <task>"`

## Errors & edge cases

| Scenario | Behavior |
|---|---|
| Task doesn't resolve | Report candidate matches if any; abort |
| User hits Ctrl-C mid-conversation | No partial write; `alignment.md` untouched |
| `--phase N` with N outside 1–3 | Report error; abort |
| `alignment.md` unreadable (permissions) | Reader returns `error` warning; surface to user; abort |
| User provides prose instead of checklist for success criteria | Accept prose; reader will later surface `success_criteria_not_checklist` warning — do NOT re-prompt in `/scope`, that's passive-aggressive |

## Related

- `references/alignment-contract.md` — canonical grammar + warning codes
- `alignment-reader` skill — the JSON contract this command reads
- `/drupal-dev-framework:research` — pre-analysis hook branches on `scope_contract_recommended` and calls this command inline
- `/drupal-dev-framework:design`, `/drupal-dev-framework:implement` — call with `--phase 2` / `--phase 3` as first sub-step
- `analysis-agent` — emits `scope_contract_recommended` signal that triggers the soft nudge

## Discoverability

- README Commands table
- Command frontmatter `description` (this file)
- `/drupal-dev-framework:next` mentions `/scope` as a retrofit option when the selected task has no `alignment.md`
- CLAUDE.md alignment section

## Do NOT

- Do not auto-generate any of the 4 fields. Claude MAY propose a draft, but user's reply is the final text.
- Do not block the task lifecycle. If the user says no, proceed without writing.
- Do not write partial sections. A section is either fully written (all 4 fields present, even if empty) or not written at all — the reader's `empty_field` warning is for humans who chose to leave a field blank, not for interrupted writes.
- Do not merge multiple phase sections in one invocation. `--phase` takes a single value.
