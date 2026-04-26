---
description: "Mark a task as done and move to completed. Trigger: 'finish task', 'mark done', 'task complete', 'close task'. Verifies /review ran (Phase 4 gates green per _review.json) when **Review Required:** true; legacy projects (Review Required: false) keep the v4.0.2 inline-gates posture. Surfaces candidate plays from the session via play_candidates mode (v3.15.0+). Slimmed v4.1.0+ — gates moved to /review."
allowed-tools: Read, Write, Bash(mv:*), Bash, Glob, Skill, Task
argument-hint: <task-name>
---

# Complete

Mark a task complete and move to `completed/`. Behavior current as of v4.1.0; full prose / examples / version history in `references/complete-walkthrough.md`.

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
   - Phase Status section: Phase 1, 2, 3 all `[x]`. Phase 4 status enforced by Step 3.
   On any fail: list remaining items, do NOT complete, offer to continue.

3. **Review Required check (v4.1.0+).** Read `**Review Required:**` field from `project_state.md`:
   - **`true` OR (absent AND `completed/` empty):** Phase 4 must be `[x]`. Verify `<task>/_review.json` exists with `gate_specific.pr_ready: true` (or `overall_verdict: "bypassed"` with all `bypass_reason` populated). On missing/incomplete audit: print soft-warn ("`/review` did not run; gates not validated. Continue without `/review`? [y/N]") default `[N]`. User declines → exit; suggest `/drupal-dev-framework:review <task>`.
   - **`false`:** legacy v4.0.2 posture. Run inline the gates that previously lived here: skill-review (conditional, see `references/complete-walkthrough.md`), plugin-validate (conditional), `/validate:all` standard gates. Soft-nudge / hard-block per existing v4.0.0 contract.
   - **Absent AND `completed/` non-empty:** treat as `false` (project predates v4.1.0; legacy posture). Print one-time soft-nudge: "v4.1.0 introduced /review as the pre-PR gate phase. Run `/drupal-dev-framework:upgrade-project` to opt into the new posture." Then proceed inline as legacy.

4. **Candidate-play surface (v3.15.0+).** Invoke `analysis-agent` in `play_candidates` mode (analyzes task artifacts + `git diff` for repeated decisions worth capturing). For each candidate, prompt `[y]/[n]/[d]`. `[y]` hands off to `/playbook-capture`. Opt-out: `--no-play-candidates`.

5. **Update `task.md`.** Add Completion section (date, status, files created/modified, summary, notes).

6. **Move task folder** per kind rules (Step 1) using `mv`.

7. **Update `project_state.md`.** Mark task completed; clear current-implementation-task field; if subtask completion empties `<epic>/in_progress/`, surface "epic ready for completion" hint to user (do NOT auto-complete the epic — user owns that decision).

8. **Suggest next task.** Surface `/next` recommendation. If all tasks done: print summary + offer to mark project done.

9. **Invoke `session-context-writer`** with project resolved and task set to `null`.

## Pointers

- Full walkthrough: `references/complete-walkthrough.md`
- Mandated wording: `references/gate-hardening-prompts.md`
- Audit shape: `references/gate-audit-schema.md`
- Quality-gate methodology: `references/quality-gates.md`
- Review phase (where gates moved to in v4.1.0): `references/review-phase-walkthrough.md`

## Related

- `/drupal-dev-framework:implement <task>` — continue Phase 3
- `/drupal-dev-framework:review <task>` — run Phase 4 gates before completing (v4.1.0+)
- `/drupal-dev-framework:upgrade-project` — set `**Review Required:**` explicitly on existing projects
- `/drupal-dev-framework:next` — see what's next
- `/drupal-dev-framework:status` — see all task statuses
- `/drupal-dev-framework:audit-status` — see hardened-gate audit state
