---
description: "Run behavioral E2E tests via Playwright against the site under test, with an optional project-resolved preflight command registered by the e2e-setup recipe. Emits a standard validation envelope and _e2e.json audit. gate_type: e2e. Part of the /review dispatcher chain."
allowed-tools: Read, Write, Edit, Bash, Glob
argument-hint: "[<task>] [--task <name>] [--skip <reason>] [--smoke-only] [--include-e2e]"
---

# /validate:e2e

<!-- visual-review:dispatch-ready -->

Runs the project's registered behavioral tests + project-custom journey tests. Emits `_e2e.json` (gate audit) and `validations/latest/e2e.json` (standard envelope). Part of the `/review` change-impact dispatcher chain — the `<!-- visual-review:dispatch-ready -->` marker above is what causes `/review` to call this gate.

## Arguments

- `<task>` — task name (positional); scopes to registry surfaces tagged `gates: [e2e]`
- `--task <name>` — same as positional (flag form)
- `--skip <reason>` — bypass; reason must be non-empty and not start with `--`; writes bypass `_e2e.json`
- `--smoke-only` — pass `--grep "@smoke"` to Playwright; fast subset for PR checks
- `--include-e2e` — force-include flag (mirrors dispatcher convention)

## Step 1: Resolve task + codePath

Parse `$ARGUMENTS`. Extract task name (positional or `--task`).

Resolve `codePath` from `project_state.md` by running `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parsing `.codePath`. If `codePath` is null or unknown, prompt the user to run `/set-code-path` first and stop.

If no task name is provided (neither positional nor `--task`): resolve from `session_context.json` active task. If no active task is found, print: `"validate:e2e: no task specified — provide a task name or run with an active task."` and stop. (EC-F25)

## Step 2: --skip bypass

If `--skip <reason>` is present:
- Validate reason:
  - Must be non-empty and must not be only whitespace (trim then check).
  - Must not start with `--`.
  - If invalid, print the literal message: `"validate:e2e: --skip reason must be non-empty and must not start with '--'."` and exit 2. (EC-F11, EC-F12)
- Build bypass payload using `jq -n --arg` (NOT string interpolation) so special characters in the reason cannot break JSON structure or shell quoting. Write to a temp file, then pass the temp file path (or stdin) to `gate-audit-write.sh`. (EC-F13/RT-V5)

  Payload shape:
  ```json
  {
    "schema_version": "1.2",
    "gate_type": "e2e",
    "fired_at": "<ISO timestamp>",
    "task_folder": "<abs task folder>",
    "user_choice": "bypassed",
    "bypass_reason": "<reason>",
    "gate_specific": {
      "verdict": "skipped",
      "total_tests": 0,
      "passed": 0,
      "failed": 0,
      "skipped": 0,
      "envelope_path": null
    }
  }
  ```
  Note: `gate_specific.verdict` uses `"skipped"` (the enum value for gates that did not execute). The bypass intent is captured at the top-level `user_choice`/`bypass_reason` fields. (HP-F2, HP-F3)
- Call `scripts/gate-audit-write.sh <task_folder> e2e '<json>'` with the jq-assembled JSON passed safely (no raw string interpolation in shell quoting).
- Print: `E2E gate bypassed. Reason: <reason>. Recorded in _e2e.json.`
- Exit 0.

## Step 3: Read registry (Claude reads; script does not parse YAML)

Read `<codePath>/.visual-review/registry.yml`. Filter surfaces where the `gates` list contains `"e2e"`. Extract the `id` values. Pass them to `scripts/validate-e2e.sh` via `--surfaces-json '[...]'`.

Also read the optional top-level `e2e.preflight_command` (defined in the surface-registry schema). If present and non-empty, it is the preflight command the gate runs before the tests. The `e2e-setup` recipe resolved by `/setup-e2e` seeds this field with the framework's preflight command (the preflight command the e2e-setup recipe registered). Pass it through via `--preflight-cmd '<cmd>'`. If absent, pass nothing — no preflight runs.

If the registry is absent or has no `e2e` surfaces: run without `--task` scoping (all tests in `tests/e2e/behavioral/`).

## Step 4: Invoke validate-e2e.sh

Invoke `scripts/validate-e2e.sh <codePath> [--task <name>] [--smoke-only] [--surfaces-json '<json>'] [--preflight-cmd '<cmd>']`.

Capture stdout (the result JSON) and exit code.

## Step 5: Write standard validation envelope

Before proceeding: verify the script's stdout is valid JSON by running `jq empty` on it. If the stdout is empty or not valid JSON (e.g., because the script exited 2 before emitting JSON), surface the script's stderr verbatim and stop — do not attempt to build `_e2e.json` from invalid input. (EC-F21)

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

Build the `_e2e.json` payload from the script's result JSON. Use `jq -n --arg`/`--argjson` to assemble the payload (NOT string interpolation), so the JSON is always well-formed regardless of field content. (EC-F13/RT-V5)

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
    "envelope_path": "<task_folder>/validations/latest/e2e.json",
    "failed_tests": [{"title": "...", "file": "..."}],
    "preflight_warnings": []
  }
}
```

Note: `gate_specific.envelope_path` is required by the gate-audit schema (minimum alongside `verdict`). (HP-F1)

Call `scripts/gate-audit-write.sh <task_folder> e2e '<json>'` passing the jq-assembled JSON safely (via temp file or stdin, never raw single-quoted shell interpolation).

## Step 7: On fail — emit e2e-gate-fail prompt

If verdict is `fail`, emit the `e2e-gate-fail` prompt from `references/gate-hardening-prompts.md` substituting `{{failed_count}}`, `{{failed_test_list}}`, and `{{report_path}}`. (EC-F23)

The E2E gate is **soft** — it signals but does not block.

## Step 8: Print summary

```
/validate:e2e complete.
Verdict: <pass|fail|warning>
Tests: <passed>/<total> passed, <failed> failed, <skipped> skipped
Report: <report_path>
Audit: <task_folder>/_e2e.json
```
