---
description: "Use when a user wants the framework to scan their in-progress flat tasks and propose which ones might benefit from being decomposed into epics. Bulk-review workflow: analysis-agent examines each candidate, user accepts or rejects per-task, accepted proposals call /migrate-to-epic under the hood. Conservative — skips already-epics, subtasks, completed, and tasks with no signals. Introduced v3.11.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: "[--only-in-progress]"
---

# Propose Epics

Run the analysis agent over all candidate flat tasks in the active project and present per-task proposals for epic-ification. User accepts or rejects each; accepted proposals invoke `/migrate-to-epic` to do the file surgery.

This is the bulk-review counterpart to the inline pre-analysis hook in `/research` (which runs at new-task creation). Both consume the same `analysis-agent` with the same JSON Schema v1.0.

## Usage

```
/drupal-dev-framework:propose-epics
/drupal-dev-framework:propose-epics --only-in-progress    # (default; reserved flag for future extensions)
```

## What this does

1. Resolves the active project from `session_context.json`. If no project active, asks user to run `/drupal-dev-framework:next` first.
2. **Resolves `codePath`** by running `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parsing `.codePath`. If unknown, runs the detect+confirm flow (shared with `/set-code-path`) and persists the answer.
3. **Enumerates candidates** — every subfolder of `<project>/implementation_process/in_progress/` that is `kind: flat` (via `${CLAUDE_PLUGIN_ROOT}/scripts/fm-read.sh "<task_folder>"`, Bash, parse `.kind`). Skips:
   - `kind: epic` / `kind: sub_epic` (already an epic)
   - `kind: subtask` (inside an epic; subject to different analysis)
   - `completed/` subtasks (via folder-location check inside any epic's `completed/`)
   - Empty task folders (no task.md)
4. **Analyzes each candidate** — invokes `analysis-agent` (via Task tool, one subagent per candidate — they can run in parallel). Each returns structured JSON per `references/analysis-agent-schema.md` v1.0. **Normalize each candidate's JSON** through `${CLAUDE_PLUGIN_ROOT}/scripts/analysis-agent-normalize.sh` as it returns, before the schema-version check, presentation, or any `/migrate-to-epic` call — it deterministically clamps `confidence` to `low` when `code_read:false` (schema invariant 2).
5. **Presents per-task** — for each analyzed task, show the user the agent's decision:
   - `epic_candidate` — proposed children + rationale → ask user to accept / edit / reject / skip
   - `keep_flat` — brief "no change recommended" note; move on
   - `insufficient_info` — ask user for context; skip
6. **Accepted proposals** → invoke `/drupal-dev-framework:migrate-to-epic <task> --children "<proposed names>"` under the hood. Reports result.
7. **Summary** — `N analyzed, M accepted+migrated, K kept flat, L deferred/skipped, F failed`. Failed tasks (invalid JSON, schema mismatch, agent timeout, or subagent error) are reported explicitly at the end with the task name + failure reason — they are not silently dropped. Example final line: `Analyzed 7 of 8 (1 failed: settings_form_refactor — invalid JSON). 2 migrated, 4 kept flat, 1 skipped.`

## User interaction per epic candidate

```
[Analyzing 3 of 7 tasks] settings_form_refactor

Decision: epic_candidate (confidence: high)
Code read: yes

Signals: many_heterogeneous_criteria, multiple_code_areas, research_architecture_fragmented

Rationale: Scope cuts across 3 distinct concerns (migration, validation, UI testing)
with little cross-dependency. Proposed decomposition reduces each child to a clear
deliverable.

Proposed children:
  1. settings_form_migration    — Move existing form to ConfigFormBase
     rationale: Self-contained lift and shift
  2. settings_form_validation   — New validation rules per new schema
     rationale: Separable once the form class is in place
  3. settings_form_ui_tests     — Playwright smoke tests for admin flow
     rationale: UI layer; can ship after form work

Options:
  [Y] accept as proposed    — invoke /migrate-to-epic with these children
  [e] edit children list    — add/remove/rename before migrating
  [n] reject                — keep task flat; report why (optional note)
  [s] skip for now          — decide later
```

## Implementation notes (for the command body)

1. **Candidate enumeration** — iterate `<project>/implementation_process/in_progress/*/` and for each subfolder run `${CLAUDE_PLUGIN_ROOT}/scripts/fm-read.sh "<task_folder>"` (Bash, parse `.kind`). Filter to `kind: flat`. Do NOT recurse into epic folders; this run only considers top-level flat tasks.
2. **Parallel analysis** — Agent SDK Subagents model fits: spawn N subagents (one per candidate) via the Task tool. Each subagent invokes `analysis-agent` and returns the JSON. Parent aggregates. Reference: Claude Code Agent SDK Subagents docs [cite AS-1 in research.md].
3. **Accept flow** — on accept, build the child-names string (comma-separated) and invoke `/drupal-dev-framework:migrate-to-epic <task> --children "<csv>"`. The migration command handles the transactional work; this command only surfaces the proposal and relays the decision.
4. **Edit flow** — on edit, show the proposed children as an editable list; user can rename, remove, add. Validate names match `^[A-Za-z0-9_][A-Za-z0-9._-]*$` before passing to `/migrate-to-epic`.
5. **Reject / skip** — record decision silently; do NOT write to the task. Summary at the end shows counts.
6. **Schema version check** — parse `schema_version` field from each agent response. **Must be a JSON string** (e.g., `"1.0"`) — reject non-string types (number, null, missing) with an error note for that task and continue. If string but major version differs from the expected `"1.0"`, skip that task with an error note and continue. Don't block the whole run.

## Errors & edge cases

| Scenario | Behavior |
|---|---|
| No active project | Prompt to run `/next` first; exit without running analysis |
| No candidate tasks found | Report "no flat in-progress tasks found" and exit |
| `codePath` unknown at run time | Trigger detect+confirm flow (shared with `/set-code-path`); persist; resume |
| Agent returns invalid JSON | Report error for that task; skip; continue with others; count in `F failed` in final summary |
| Subagent crashes or times out | Report error for that task (with reason); skip; continue; count in `F failed` |
| Agent returns `decision: insufficient_info` | Report; ask user for context (optional); skip |
| User rejects mid-review (Ctrl-C) | Save any already-migrated tasks' state; exit cleanly |
| Task name matches another task's proposed child name | Accept but warn; `/migrate-to-epic` will abort if it would collide |

## Discoverability

- README Commands table
- Command frontmatter `description`
- marketplace.json plugin description
- Plugin CONVENTIONS.md Analysis Agent section
- `/drupal-dev-framework:next` mentions this command when the project has multiple long-running flat tasks

## Related

- `analysis-agent` — the subagent this command spawns per candidate
- `/drupal-dev-framework:migrate-to-epic` — atomic primitive invoked on accept
- `references/analysis-agent-schema.md` — the JSON output contract
- `references/code-path-detection.md` — detect+confirm flow for codePath
- `/drupal-dev-framework:set-code-path` — explicit codePath setter
- `/drupal-dev-framework:research` — inline pre-analysis hook counterpart
