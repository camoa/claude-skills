---
description: "Run ATK behavioral E2E tests + project-custom journey tests against the Drupal site. Emits a standard validation envelope and _e2e.json audit. gate_type: e2e. Part of the /review dispatcher chain."
allowed-tools: Read, Write, Edit, Bash, Glob
argument-hint: "[<task>] [--task <name>] [--skip <reason>] [--smoke-only] [--include-e2e]"
---

# /validate:e2e

<!-- visual-review:dispatch-ready -->

Runs ATK canned behavioral tests + project-custom journey tests. Emits `_e2e.json` (gate audit) and `validations/latest/e2e.json` (standard envelope). Part of the `/review` change-impact dispatcher chain — the `<!-- visual-review:dispatch-ready -->` marker above is what causes `/review` to call this gate.

Full walkthrough: `references/atk-e2e-walkthrough.md`.

## Arguments

- `<task>` — task name (positional); scopes to registry surfaces tagged `gates: [e2e]`
- `--task <name>` — same as positional (flag form)
- `--skip <reason>` — bypass; reason must be non-empty and not start with `--`; writes bypass `_e2e.json`
- `--smoke-only` — pass `--grep "@smoke"` to Playwright; fast subset for PR checks
- `--include-e2e` — force-include flag (mirrors dispatcher convention)

## Step 1: Resolve task + codePath

Parse `$ARGUMENTS`. Extract task name (positional or `--task`).

Resolve `codePath` from `project_state.md` via the `project-state-reader` skill. If `codePath` is null or unknown, prompt the user to run `/set-code-path` first and stop.

## Step 2: --skip bypass

If `--skip <reason>` is present:
- Validate: reason is non-empty AND does not start with `--` → if invalid, print error and exit 2.
- Build bypass payload:
  ```json
  {
    "schema_version": "1.2",
    "gate_type": "e2e",
    "fired_at": "<ISO timestamp>",
    "task_folder": "<abs task folder>",
    "gate_specific": {
      "verdict": "bypassed",
      "bypass_reason": "<reason>",
      "total_tests": 0,
      "passed": 0,
      "failed": 0,
      "skipped": 0
    }
  }
  ```
- Call `scripts/gate-audit-write.sh <task_folder> e2e '<json>'`.
- Print: `E2E gate bypassed. Reason: <reason>. Recorded in _e2e.json.`
- Exit 0.

## Step 3: Read registry (Claude reads; script does not parse YAML)

Read `<codePath>/.visual-review/registry.yml`. Filter surfaces where the `gates` list contains `"e2e"`. Extract the `id` values. Pass them to `scripts/validate-e2e.sh` via `--surfaces-json '[...]'`.

If the registry is absent or has no `e2e` surfaces: run without `--task` scoping (all tests in `tests/e2e/behavioral/`).

## Step 4: Invoke validate-e2e.sh

Invoke `scripts/validate-e2e.sh <codePath> [--task <name>] [--smoke-only] [--surfaces-json '<json>']`.

Capture stdout (the result JSON) and exit code.

## Step 5: Write standard validation envelope

Write the result to `<task_folder>/validations/latest/e2e.json` per `references/validation-gate-result.md` v1.0:
```json
{
  "schema_version": "1.0",
  "gate": "e2e",
  "task": "<task>",
  "run_at": "<ISO timestamp>",
  "verdict": "<pass|fail|warning>",
  "details": "<script result JSON>",
  "messages": []
}
```

## Step 6: Write gate audit

Build the `_e2e.json` payload from the script's result JSON:
```json
{
  "schema_version": "1.2",
  "gate_type": "e2e",
  "fired_at": "<ISO timestamp>",
  "task_folder": "<abs task folder>",
  "gate_specific": {
    "verdict": "<pass|fail|warning>",
    "total_tests": <n>,
    "passed": <n>,
    "failed": <n>,
    "skipped": <n>,
    "report_path": "<relative path to HTML report>",
    "failed_tests": [{"title": "...", "file": "..."}],
    "preflight_warnings": []
  }
}
```

Call `scripts/gate-audit-write.sh <task_folder> e2e '<json>'`.

## Step 7: On fail — emit e2e-gate-fail prompt

If verdict is `fail`, emit the `e2e-gate-fail` prompt from `references/gate-hardening-prompts.md` substituting `{failed_count}`, `{failed_test_list}`, and `{report_path}`.

The E2E gate is **soft** — it signals but does not block.

## Step 8: Print summary

```
/validate:e2e complete.
Verdict: <pass|fail|warning>
Tests: <passed>/<total> passed, <failed> failed, <skipped> skipped
Report: <report_path>
Audit: <task_folder>/_e2e.json
```
