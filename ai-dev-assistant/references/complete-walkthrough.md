# Complete — Full Walkthrough

Tutorial-depth reference for the `/ai-dev-assistant:complete` command. The runtime command body (see `commands/complete.md`) is a terse imperative summary; this file documents every sub-step, rationale, version history, and worked example in full.

**Loaded only when explicitly read.** No hook or skill auto-loads this file.

---



Mark a task as complete and move it to the completed folder.

## Usage

```
/ai-dev-assistant:complete <task-name>
```

## What This Does (v3.0.0 + v3.10.0 epic awareness + v4.0.0 hardened gates)

1. Invokes `task-completer` skill
2. Loads task from `implementation_process/in_progress/{task_name}/`
3. **Invoke `task-frontmatter-reader` (v1.0.0+) to learn the task's `kind` and parent.** Different completion rules apply per kind (see below).
4. Verifies acceptance criteria are met
5. Updates `task.md` with completion notes
6. Moves entire task directory to `implementation_process/completed/{task_name}/`
7. Updates `project_state.md`
8. **If the completed task is a subtask**, check its parent epic's `children[]`: if all siblings are now completed, print a "epic ready for completion" hint to the user (don't auto-complete the epic — the user owns that decision).
9. Suggests next task (if any)

## Hierarchy-aware completion rules (v3.10.0)

- **`kind: flat`** — unchanged v3.0.0 behavior. Target: project-level `completed/<name>/`.
- **`kind: subtask`** — completion moves the folder from `<epic>/in_progress/<subtask>/` to `<epic>/completed/<subtask>/`. **The child stays inside the epic.** The epic's `children[]` list still references the subtask by id. Spatial association with the parent epic is preserved — you can always browse the epic folder to see its full history.
- **`kind: epic`** or **`kind: sub_epic`** — pre-completion gate enforces that `<epic>/in_progress/` is empty (all children have already moved to `<epic>/completed/`). If any child is still in progress, abort listing them. When the gate passes, the whole epic folder (including its internal `in_progress/`=empty and `completed/`=full) moves to project-level `completed/<epic>/`. History stays intact in one move.
Do NOT touch dependency graphs (`blocks`/`blocked_by`) here — dependency-aware routing is the concern of `/next`, not completion.
8. **Invokes `session-context-writer` skill with project and task set to `null` (task is now completed)**

## Pre-Completion Checks

Before marking complete, verifies:
- [ ] All acceptance criteria marked done in task file
- [ ] Tests pass (user confirmation required)
- [ ] No blocking issues noted
- [ ] Implementation section is complete

If checks fail:
- Lists remaining items
- Does NOT complete task
- Offers to continue working

## Worktree merge prompt (v3.16.0+)

**Run AFTER the 5 quality gates pass and BEFORE the candidate-play surface.** Soft-nudge — default skip; never blocks.

Invoke `scripts/worktree-detect.sh "$PWD"`. If `in_worktree: false` → skip; continue to candidate-play surface.

If `in_worktree: true`:

> Print: "This task is on worktree `<worktree_path>` (branch `<branch>`). Choose:
> 1. Merge back to main + remove worktree
> 2. Push branch + open PR (worktree stays)
> 3. Skip — leave everything as-is
>
> Pick [1/2/3] (default 3):"

On `1`:
- `cd <main_path>` (from worktree-detect output)
- `git checkout main`
- `git merge --no-ff <branch>`
- If merge conflicts: abort merge; print conflict files; instruct user to resolve manually; do NOT remove worktree
- If clean: `git worktree remove "<worktree_path>"`; print "Merged `<branch>` to main; worktree removed. Run `git push` when ready."

On `2`:
- `cd "<worktree_path>"`
- `git push -u origin <branch>`
- If `gh` CLI available: ask "Open PR via `gh pr create`? [y/n]"; on `y`, run `gh pr create`
- Leave worktree in place; print "Branch pushed; worktree kept at `<worktree_path>`."

On `3`:
- No-op. Continue to candidate-play surface.

## Skill-review gate (v4.0.0+, hardened)

**This gate is non-bypassable.** Same anti-bypass clause as pre-analysis. Skipping requires `--skip-skill-review <reason>` flag, recorded in `<task>/_skill-review.json` `bypass_reason`.

**Trigger:** staged or branched changes include `skills/*/SKILL.md` files. Detection:

```bash
git diff --cached --name-only | grep -E "skills/.*/SKILL\.md" || \
  git diff main...HEAD --name-only | grep -E "skills/.*/SKILL\.md"
```

If any matches → fire the gate. If none → skip silently (no audit; not a bypass).

### Steps

1. **Invoke** `plugin-creation-tools:skill-quality-reviewer` agent via Task tool against the project's `skills/` directory. Capture full agent output verbatim.
2. **Display** the literal `prompts:skill-review-decision` template from `references/gate-hardening-prompts.md`. Substitutions: `{{skills_reviewed}}` (comma-list of skill names from the diff), `{{findings}}` (verbatim agent output).
3. **Block** on user `[a]ccept / [r]emediate / [b]ypass` choice.
4. **Write audit** to `<task>/_skill-review.json` via `gate-audit-write.sh`. `user_choice: "accepted"` for `[a]`, `"remediated"` for `[r]` (after the user has made remediation edits), `"bypassed"` for `[b]` (with `bypass_reason` from free-text prompt).
5. **Refusal case:** if `plugin-creation-tools` is not installed, halt with: "Required gate `skill-quality-reviewer` (from plugin-creation-tools) not available. Install plugin-creation-tools or pass `--skip-skill-review <reason>` to bypass." Do NOT degrade silently.

## Plugin-validate gate (v4.0.0+, hardened)

**This gate is non-bypassable.** Same anti-bypass clause. Skipping requires `--skip-plugin-validate <reason>` flag.

**Trigger:** staged or branched changes include any plugin file under `commands/`, `skills/`, `references/`, `hooks/`, `scripts/`, or `.claude-plugin/`. Detection:

```bash
git diff --cached --name-only | grep -E "(commands|skills|references|hooks|scripts|\.claude-plugin)/" || \
  git diff main...HEAD --name-only | grep -E "(commands|skills|references|hooks|scripts|\.claude-plugin)/"
```

If any matches → fire the gate.

### Steps

1. **Invoke** `/plugin-creation-tools:validate --strict` slash command (DDF dogfoods strict validation on its own plugin changes). Capture full output verbatim.
2. **Display** the literal `prompts:plugin-validate-decision` template. Substitutions: `{{plugins_validated}}` (comma-list), `{{findings}}` (verbatim slash-command output).
3. **Block** on user `[a]ccept / [r]emediate / [b]ypass` choice.
4. **Write audit** to `<task>/_plugin-validate.json` via `gate-audit-write.sh`.
5. **Refusal case:** same as skill-review — halt if plugin-creation-tools not installed; explicit-skip-required.

## Candidate-play surface (v3.15.0+)

After the 5 quality gates pass and before the task moves to `completed/`, surface 0-N candidate plays the framework detected during this task. Skipped if `--no-play-candidates` flag is passed OR if the project has `userPlaybookState != "set"` (no playbook to capture into).

### Step 1 — Invoke analysis-agent in `play_candidates` mode

Per `references/analysis-agent-schema.md` v1.1, invoke `analysis-agent` (Task tool) with:

```json
{
  "mode": "play_candidates",
  "task_folder": "<abs path>",
  "code_path": "<abs path or null>",
  "git_diff_since": "<commit SHA at task start>",
  "active_playbook_sets": ["<from project-state-reader>"],
  "user_playbook_path": "<from project-state-reader>",
  "schema_version": "1.1"
}
```

The agent emits `candidates[]` with each carrying file:line evidence (≥2 occurrences), confidence, rationale, suggested_section. Filter `confidence: low` by default unless user passes `--include-low-confidence`.

### Step 2 — Per-candidate prompt

For each remaining candidate, print:

```
Candidate play: "<title>"
Section: <suggested_section>
Confidence: <high|medium>
Evidence:
  - <file:line>: <snippet>
  - <file:line>: <snippet>

Capture? [y]es / [n]o / [d]etails — show full rationale
```

- `[y]` → hand off to `/playbook-capture` flow with the draft pre-filled (title + section + What suggested from rationale + Example pre-filled from evidence snippets).
- `[n]` → skip silently, no record.
- `[d]` → print full agent rationale + signals; re-ask y/n.

### Step 3 — Continue to task move

After all candidates handled, continue with the existing `/complete` flow (move task to `completed/`, update `project_state.md`, etc.).

### Notes

- **Never blocks.** All candidates can be declined; task completes regardless.
- **Skip when `userPlaybookState != "set"`** — no destination for captured plays.
- **Threshold ≥2 evidence** enforced agent-side per schema; consumers don't re-check.
- **`--no-play-candidates`** opt-out for users who don't want this step.

## Example

```
/ai-dev-assistant:complete settings_form

Task: settings_form

Pre-completion check:
✓ Acceptance criteria: 5/5 complete
? Tests pass: [Awaiting your confirmation]
✓ No blocking issues

Please confirm tests pass to complete this task.
```

After user confirms (v3.0.0):

```
Task completed: settings_form

Updated files:
- Moved: implementation_process/in_progress/settings_form/ → completed/settings_form/
  - task.md
  - research.md
  - architecture.md
  - implementation.md
- Updated: project_state.md

Up Next:
- content_entity (in_progress, Phase 2)

Run: /ai-dev-assistant:design content_entity
```

## Task File Updates

Adds completion section to task file before moving:

```markdown
## Completion

**Completed:** {date}
**Status:** Complete

### Files Created/Modified
- `src/Form/SettingsForm.php` - Created
- `config/schema/mymodule.schema.yml` - Created
- `tests/src/Unit/SettingsFormTest.php` - Created

### Summary
{Brief summary of what was implemented}

### Notes
{Any implementation notes for future reference}
```

## project_state.md Updates

Updates the project state:

```markdown
## Current Implementation Task
Working on: {next_task or "None - all tasks complete"}
File: {path or "-"}

## Completed Implementation Tasks
- ✅ settings_form - {date}
- ✅ {previous_task} - {date}
```

## All Tasks Complete

When completing the last task:

```
All tasks complete!

Project: {project_name}
Completed tasks: {count}

Options:
1. Define new tasks
2. Mark project as done
3. Review completed work

What would you like to do?
```

## Related Commands

- `/ai-dev-assistant:implement <task>` - Continue implementing a task
- `/ai-dev-assistant:validate <task>` - Validate before completing
- `/ai-dev-assistant:next` - See what's next
- `/ai-dev-assistant:status` - See all task statuses
