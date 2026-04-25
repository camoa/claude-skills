---
description: "Load context and start implementing a task. Trigger: 'start coding', 'implement task', 'begin implementation', 'Phase 3', 'write code'. REQUIRES completed architecture. Enforces TDD (test-first)."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Skill, Task
argument-hint: <task-name>
---

# Implement

Phase 3 of a task. Behavior current as of v4.0.2; full prose / examples / version history in `references/implement-walkthrough.md`.

## Usage

```
/drupal-dev-framework:implement <task-name>
```

## Runtime Steps

1. **Phase Transition Check.** Read `task.md` Phase Status. Evaluate Phases 1 and 2 independently:
   - Phase 2 not `[x]` → print one-line soft-nudge ("Phase 2 not complete; consider `/drupal-dev-framework:design <task>` first.").
   - Phase 1 not `[x]` → print one-line soft-nudge ("Phase 1 not complete; running `/implement` without research is unusual.").
   - Both `[x]` → silent.
   Never block.

2. **Worktree signals (v3.16.0+).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-signals.sh <task>`. On HIGH-strength signal (`another_task_active`, `dirty_tree`, `--worktree` flag, or `worktreeByDefault: true`), print soft-nudge offering `/worktree <task>`. Suppress when already inside a worktree. Never block.

3. **Dev-guides preflight.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh <task_folder>`. Display literal preflight prompt; block on `[c]/[a]/[n]` (default `[c]`). Apply choice. Write `_dev-guides-load.json` audit.

4. **Playbook load.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh <project_folder>`. Surface conflicts once-per-session per topic. Write `_playbook-load.json` audit.

5. **Alignment retrofit + phase-level offer.** Invoke `alignment-reader`. If `task_level.present: false`: offer task-level retrofit (4 questions, default `[n]`). On `[y]` execute task-level scope flow inline. Then offer phase-3 scope (default `[n]`); on `[y]` execute `--phase 3` inline. Never block.

6. **Load context.** Read `architecture.md` (required), `research.md` (context), referenced patterns from core/contrib, methodology refs (via `guide-integrator`). Activate `tdd-companion` skill.

7. **Author/update implementation.md.** Standard sections: Step Plan (numbered), Files Created/Modified, Progress (`[ ]`/`[x]` per step), TDD Log, Notes, Blockers. Update `task.md` Phase 3 in-progress.

8. **Post-plan epic check (v3.13.5+, BEFORE any code is written).** Re-invoke `analysis-agent` in folder mode (sees task+alignment+research+architecture+implementation). Branch on `decision`:
   - `keep_flat` / `insufficient_info` → silent, proceed.
   - `epic_candidate` → display "last chance before coding" offer (note: mid-implementation migration is expensive; step plan is discarded if migrating). Default `[n]`. `[y]` → `/migrate-to-epic`, stop. `[d]` → show rationale, re-ask.

9. **Traceability walkthrough (opt-in).** One-line `[y]/[n]` (default `[n]`). On `[y]`: pull AC; map each to implementation.md Progress entries OR architecture.md sections OR research.md decisions; status-annotate (`[complete]`, `[in-progress]`, `(planned)`, `— NOT YET ADDRESSED —`); print table; `[c]/[r]/[d]` (default `[c]`). Re-invokable mid-flight.

10. **Invoke `session-context-writer`** with resolved project + task.

11. **Hand off to interactive development.** Developer guides each step. Claude proposes (test-first), developer approves, Claude writes test then implementation, developer runs tests (Claude does NOT auto-run unless explicitly asked).

## Interactive Development Loop

For each acceptance criterion:
1. Developer requests piece to implement.
2. Claude proposes approach (test first, per TDD discipline from `references/tdd-workflow.md`).
3. Developer approves or adjusts.
4. Claude writes test, then implementation.
5. Developer runs tests.
6. Update `implementation.md` Progress + `task.md` AC checkboxes.
7. Repeat until task complete.

## Pointers

- Full walkthrough: `references/implement-walkthrough.md`
- TDD methodology: `references/tdd-workflow.md`
- Mandated wording: `references/gate-hardening-prompts.md`
- Audit shape: `references/gate-audit-schema.md` v1.0
- Worktree conventions: `references/worktree-conventions.md`

## Related

- `/drupal-dev-framework:research <task>` — Phase 1
- `/drupal-dev-framework:design <task>` — Phase 2
- `/drupal-dev-framework:complete <task>` — mark task done
- `/drupal-dev-framework:validate <task>` — validate against architecture
- `/drupal-dev-framework:worktree <task>` — isolate in `.worktrees/<task>/`
