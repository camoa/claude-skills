---
description: "Display the audit state of a task — which v4.0.0 hardened gates fired, which were bypassed, and per-bypass reasons. Read-only. Introduced v4.0.0."
allowed-tools: Read, Bash, Glob
argument-hint: "[<task-name>] [--all]"
---

# Audit Status

Read-only display of v4.0.0 hardened-gate audit state per task. Surfaces gate-fire timing, user choices, bypass reasons, and missing audits (= silent skip evidence).

## Usage

```
/ai-dev-assistant:audit-status                  # current session task
/ai-dev-assistant:audit-status <task-name>      # specific task
/ai-dev-assistant:audit-status --all            # project-wide rollup
```

## What this does

### Step 1 — Resolve scope

- No arg → use `task` from current `session_context.json`
- `<task-name>` → resolve task folder under the current project's `implementation_process/in_progress/**/<task-name>/`
- `--all` → enumerate all task folders under `implementation_process/{in_progress,completed}/**`

Refuse if no project context resolved.

### Step 2 — For each task, scan audit files

The 7 v4.0.0 audit file types are:

- `_pre-analysis.json`
- `_coverage-mapping.json`
- `_skill-review.json`
- `_plugin-validate.json`
- `_phase-command-bypass.json`
- `_dev-guides-load.json`
- `_playbook-load.json`

For each task folder:

1. List which audit files exist
2. For each existing file, parse `gate_type`, `fired_at`, `user_choice`, `bypass_reason`, `gate_specific` per `references/gate-audit-schema.md` v1.0
3. Compute "expected but missing" gates:
   - `_pre-analysis.json` expected if `research.md` exists; missing → grandfathered (pre-v4.0.0) OR bypassed
   - `_coverage-mapping.json` expected if `research.md` exists with content > 200 lines (substantive)
   - `_skill-review.json` expected if task's git history shows `skills/*/SKILL.md` changes
   - `_plugin-validate.json` expected if task's git history shows plugin file changes
   - `_dev-guides-load.json` expected if any phase command ran (research.md / architecture.md / implementation.md exists)
   - `_playbook-load.json` expected if `playbookSets` non-empty OR `userPlaybook` set in project_state.md
   - `_phase-command-bypass.json` expected only when actual bypass happened — its presence IS the signal

### Step 3 — Print summary

#### Single-task format

```
Audit status for <task_name>:

  ✓ pre-analysis        fired 2026-04-24T20:30:00Z  user_choice: y          [keep_flat]
  ✓ coverage-mapping    fired 2026-04-24T20:32:00Z  user_choice: phase_marked_complete   [pass: 6/6 questions]
  ⊘ skill-review        not fired (no skill changes detected in this task's diff)
  ⊘ plugin-validate     not fired (no plugin file changes detected)
  ⚠ phase-command-bypass FIRED 2026-04-24T19:45:00Z  artifact: research.md  expected: research  active: null
  ✓ dev-guides-load     fired 2026-04-24T20:31:00Z  user_choice: c          [matched: gate, complete, quality → plugin:quality-gates]
  ✓ playbook-load       fired 2026-04-24T20:31:00Z  loaded: <framework>/best-practices/<author> + local (19 plays)

  Bypasses recorded: 0
  Missing audits (= unaudited): 0
  Health: ✓ all expected gates fired or correctly skipped
```

#### Symbols

- `✓` — gate fired correctly; user choice recorded
- `⊘` — gate not fired but expected behavior (signals didn't match; not a bypass)
- `⚠` — bypass detected (audit file present with `user_choice: bypassed` OR phase-command-bypass audit present)
- `✗` — gate expected to fire but audit file MISSING (silent bypass; the worst case)

#### `--all` format

Per-task summary line, grouped by health:

```
Audit status (project-wide):

  Healthy (8 tasks, all expected gates fired):
    - dev_framework_isolated_validators
    - dev_framework_user_patterns
    - dev_framework_dad_sandwich
    - …

  Bypasses recorded (2 tasks):
    - dev_framework_research_artifact_structure: pre-analysis bypassed (--skip-pre-analysis "stub task")
    - dev_framework_gate_hardening: phase-command-bypass recorded × 3 for research.md/architecture.md/implementation.md (pre-restart artifacts; see _pre-restart/)

  Missing audits (= silent bypass — worst case) (0 tasks):
    (none)

  Grandfathered (pre-v4.0.0 lifecycle) (1 task):
    - dev_framework_phase_checkpoints (no _pre-analysis.json; research.md authored before v4.0.0 install)
```

### Step 4 — Per-bypass details on demand

If single-task mode shows `⚠` for `phase-command-bypass`, ask: `[d]etails / [a]cknowledge / quit`.

- `[d]` → display literal `prompts:phase-command-bypass-acknowledge` template from `references/gate-hardening-prompts.md`. User picks `[a]cknowledge` (note bypass and continue) or `[r]e-run` (invoke proper phase command now).
- `[a]` → exit without action.

## What this does NOT do

- Does NOT modify audit files or task state
- Does NOT auto-remediate findings
- Does NOT enforce anything — read-only
- Does NOT cross-project rollup; `--all` is current project only

## Related Commands

- `/ai-dev-assistant:status` — task-level overview; includes Unaudited gates section as summary
- `/ai-dev-assistant:research`, `:design`, `:implement`, `:complete` — the phase commands that fire the audited gates
- `references/gate-audit-schema.md` v1.0 — schema for the 7 audit file types
- `references/gate-hardening-prompts.md` v1.0 — prompts surfaced by audit-status when bypasses are acknowledged
