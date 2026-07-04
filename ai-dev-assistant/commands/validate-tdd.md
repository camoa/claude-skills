---
description: "Run the TDD quality gate on demand and persist the result to the current task folder. Thin wrapper around /code-quality:tdd — adds task context, persistence, and the shared result envelope. Soft-nudge: reports fail verdict but never blocks. Introduced v3.13.0."
allowed-tools: Read, Write, Bash, Glob, Skill
argument-hint: "[<task-name>]"
---

# Validate: TDD

Run the TDD (Red-Green-Refactor discipline) quality gate against the current task. Wraps `/code-quality:tdd` from the `code-quality-tools` plugin; adds task-context resolution, result persistence to the task folder, and emits the shared result envelope (`references/validation-gate-result.md` v1.0).

## Usage

```
/ai-dev-assistant:validate-tdd                          # run against current task from session context
/ai-dev-assistant:validate-tdd <task-name>              # run against a specific task
/ai-dev-assistant:validate-tdd <task> --files <path>    # change-scoped: forward <path> as --changed to the underlying check
```

## What this does

1. **Resolve task context** — resolve the project folder in this order:
   (a) run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-read.sh` (Bash) and parse its JSON (`.project`, `.projectPath`, `.task`, `.taskPath`) if it resolves — it carries the active project's absolute path
   (b) walk up from `$PWD` until you find a directory containing `implementation_process/`
   (c) abort with "no project context — run /ai-dev-assistant:next first, or cd to a project workspace" if neither resolves

   Then resolve the task folder: if `<task-name>` arg is given, locate it under `<project>/implementation_process/in_progress/**/<task-name>/` (glob handles both flat and sub-epic nesting). If no arg, use the task from the `session-context-read.sh` output (`.task`/`.taskPath`). If the task doesn't resolve, abort with candidate suggestions.

2. **Verify dependency** — confirm `code-quality-tools` plugin is installed. Check: `ls ~/.claude/plugins/cache/camoa-skills/code-quality-tools/` returns a non-empty directory. Minimum supported version: **3.0.0** (earlier versions may work but are untested against this wrapper). If missing, abort with install instructions.

3. **Invoke the check** — execute the `/code-quality:tdd` flow as documented in the `code-quality-tools` plugin's `commands/tdd.md` within this command's own execution context. Do NOT attempt to shell out to the sibling slash command. If a `--files <list>` parameter was supplied to this wrapper, forward it to the underlying flow as `--changed <list>` — this scopes the gate to the listed files; the code-quality tool handles the empty-list → clean-skip case internally. When `--files` is absent, run the flow's standard whole-project scan (auto-detect project type, run the TDD check, surface findings). Capture the output for envelope construction in step 4.

4. **Parse the result** — classify the output into our verdict space (`pass | warning | fail | skipped`) per the "Verdict interpretation" section below. Extract any actionable findings into `messages[]`. If `/code-quality:tdd` wrote a JSON report to `.reports/tdd.json` (disk-read fallback), capture its path.

5. **Emit the shared envelope** — produce a JSON object matching `references/validation-gate-result.md` v1.0 for the tdd gate.

6. **Persist** — write the envelope to TWO locations:
   - `<task_folder>/validations/latest/tdd.json` — overwrite (most-recent-run lookup)
   - `<task_folder>/validations/history.jsonl` — append (full run log)

7. **Print CLI summary** — show verdict, top 3 messages, and the persisted-result paths. When invoked non-interactively (chained from `/validate:all` or CI equivalents), signal verdict via exit code: 0 for `pass`/`warning`/`skipped`; 1 for `fail`. In interactive use the printed summary IS the signal — Claude does not literally exit the session. User workflow is NEVER blocked regardless of verdict.

## Verdict interpretation

`/code-quality:tdd` output has to be mapped to our 4-value verdict enum. Heuristics (ordered; first match wins):

| Signal in output | Our verdict |
|---|---|
| Explicit "PASS" / "✓" / "all checks passed" / "no violations" | `pass` |
| Explicit "FAIL" / "✗" / "violations found" / "tests missing for <x>" | `fail` |
| Warnings-but-not-fatal phrasing ("1 concern", "minor issue", "consider") | `warning` |
| Skip indicators ("not applicable", "no code changes to check", "skipped — <reason>") | `skipped` |
| Ambiguous or empty output | `warning` (conservative — surface for human review) |

If `/code-quality:tdd` emits JSON via a `--json` flag (future enhancement), prefer structured parsing over heuristics. v1 uses heuristics because no stable JSON surface exists yet upstream.

## Shared envelope shape (per `references/validation-gate-result.md`)

```json
{
  "schema_version": "1.0",
  "gate": "tdd",
  "task": "<task_name>",
  "run_at": "<ISO-8601 UTC>",
  "verdict": "pass",
  "details": {
    "source": "code-quality-tools:tdd",
    "raw_output_path": "<path to .reports/tdd.json if produced, else null>",
    "code_quality_tools_version": "<version from plugin.json of code-quality-tools>"
  },
  "messages": ["<top findings>"]
}
```

## Persistence

Write order:
1. `mkdir -p <task_folder>/validations/latest`
2. Write envelope to `<task_folder>/validations/latest/tdd.json` (overwrites prior run)
3. Append envelope (as single line) to `<task_folder>/validations/history.jsonl`

`history.jsonl` uses JSON Lines format (one object per line, newline-separated). Append-safe; git-diff-legible; easy to tail.

## CLI output format

```
TDD gate on <task_name>: <verdict>

  • <message 1>
  • <message 2>
  • <message 3>

Saved:
  latest  → <task>/validations/latest/tdd.json
  history → <task>/validations/history.jsonl
```

On `pass`: 0-2 messages (usually "all checks passed" + a brief observation). On `fail`: up to 5 top findings surfaced.

## Error cases

| Scenario | Behavior |
|---|---|
| No session context AND no `<task-name>` arg | Print "no task context; pass a task name or run /ai-dev-assistant:next first" + exit 2 |
| `<task-name>` doesn't resolve to a folder | Print candidate suggestions + exit 2 |
| `code-quality-tools` plugin missing | Print "code-quality-tools not installed; install via /plugin install code-quality-tools@camoa-skills" + exit 3 |
| `/code-quality:tdd` fails to execute | Emit envelope with `verdict: skipped`, messages describing the failure, exit 0 |
| Persistence write fails | Still print CLI summary; mention the failure in messages; exit 1 |

## Soft-nudge posture

- Manual invocation always runs, regardless of task kind or applicability signals (no auto-skip in v1)
- `fail` verdict signals but does not block — user can continue working or fix the issue
- Non-zero exit codes surface the signal to CI / `/validate:all` chaining, but the local session keeps going

## Related

- `/ai-dev-assistant:validate-solid` / `:validate-dry` / `:validate-security` — sibling wrappers, same pattern
- `/ai-dev-assistant:validate-guides` — framework-owned gate, not a wrapper
- `/ai-dev-assistant:validate-visual-parity` / `:validate-visual-regression` — visual gates
- `/ai-dev-assistant:validate-all` — sequential orchestrator that calls this + all other gates
- `references/validation-gate-result.md` — the shared envelope contract
- `/code-quality:tdd` — the underlying check this command wraps
- `/code-quality:coverage`, `/code-quality:lint`, `/code-quality:review`, `/code-quality:audit`, `/code-quality:ultrareview` — NOT wrapped; invoke directly for deeper coverage
