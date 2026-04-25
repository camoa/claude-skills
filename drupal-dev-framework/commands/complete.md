---
description: "Mark a task as done and move to completed. Trigger: 'finish task', 'mark done', 'task complete', 'close task'. Runs ALL 7 quality gates (5 standard + skill-review + plugin-validate when staged changes match) before allowing completion. Surfaces candidate plays from the session via play_candidates mode (v3.15.0+)."
allowed-tools: Read, Write, Bash(mv:*), Bash, Glob, Skill, Task
argument-hint: <task-name>
---

# Complete

Mark a task complete and move to `completed/`. Behavior current as of v4.0.2; full prose / examples / version history in `references/complete-walkthrough.md`.

## Usage

```
/drupal-dev-framework:complete <task-name>
```

## Runtime Steps

1. **Read task hierarchy.** Invoke `task-frontmatter-reader` (v1.0.0+) to learn `kind` and `parent`. Hierarchy-aware completion rules per kind:
   - `flat` → moves to project-level `completed/<name>/`.
   - `subtask` → moves from `<epic>/in_progress/<subtask>/` to `<epic>/completed/<subtask>/` (stays in epic; preserves spatial association).
   - `epic` / `sub_epic` → enforce `<epic>/in_progress/` is empty (all children done) before allowing the epic to complete; whole folder moves to project-level `completed/<epic>/`.

2. **Pre-completion checks.** Verify:
   - All Acceptance Criteria in `task.md` marked `[x]`.
   - User confirms tests pass (Claude does NOT auto-run).
   - No blocking issues in `implementation.md` Blockers section.
   - `implementation.md` Progress section all `[x]`.
   On any fail: list remaining items, do NOT complete, offer to continue.

3. **Skill-review hardened gate (v4.0.0+, conditional non-bypassable).** If `git diff --cached --name-only` (or branch diff vs main) shows `skills/*/SKILL.md` changes: invoke `plugin-creation-tools:skill-quality-reviewer` agent. Display findings using literal `prompts:skill-review-decision` template. Block on `[a]ccept/[r]emediate/[b]ypass` (no default — user MUST pick). Write `_skill-review.json` audit. Skip flag: `--skip-skill-review <reason>`.

4. **Plugin-validate hardened gate (v4.0.0+, conditional non-bypassable).** If staged changes include any plugin file: invoke `/plugin-creation-tools:validate`. Display findings using literal `prompts:plugin-validate-decision` template. Block on `[a]ccept/[r]emediate/[b]ypass` (no default). Write `_plugin-validate.json` audit. Skip flag: `--skip-plugin-validate <reason>`.

5. **Standard quality gates** (5 from v3.13.0+ `code-quality-tools` skills). Run/verify TDD, SOLID, DRY, Security, Guides per usual `/validate:all` semantics. Soft-nudge on fail; never blocks.

6. **Candidate-play surface (v3.15.0+).** Invoke `analysis-agent` in `play_candidates` mode (analyzes task artifacts + `git diff` for repeated decisions worth capturing). For each candidate, prompt `[y]/[n]/[d]`. `[y]` hands off to `/playbook-capture`. Opt-out: `--no-play-candidates`.

7. **Update `task.md`.** Add Completion section (date, status, files created/modified, summary, notes).

8. **Move task folder** per kind rules (Step 1) using `mv`.

9. **Update `project_state.md`.** Mark task completed; clear current-implementation-task field; if subtask completion empties `<epic>/in_progress/`, surface "epic ready for completion" hint to user (do NOT auto-complete the epic — user owns that decision).

10. **Suggest next task.** Surface `/next` recommendation. If all tasks done: print summary + offer to mark project done.

11. **Invoke `session-context-writer`** with project resolved and task set to `null`.

## Anti-bypass clause (applies to gates 3, 4)

Skipping requires the documented `--skip-*` flag with free-text reason; bypass is recorded on disk and surfaced via `/audit-status` Unaudited gates.

## Pointers

- Full walkthrough: `references/complete-walkthrough.md`
- Mandated wording: `references/gate-hardening-prompts.md`
- Audit shape: `references/gate-audit-schema.md` v1.0
- Quality-gate methodology: `references/quality-gates.md`

## Related

- `/drupal-dev-framework:implement <task>` — continue Phase 3
- `/drupal-dev-framework:validate <task>` — validate before completing
- `/drupal-dev-framework:next` — see what's next
- `/drupal-dev-framework:status` — see all task statuses
- `/drupal-dev-framework:audit-status` — see hardened-gate audit state
