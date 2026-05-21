# PostToolBatch Aggregation Pattern

> Status: documented optional pattern. **Not shipped as a default-on hook** in this plugin. Copy the snippets below into your project's `.claude/hooks.json` (or a project-local hooks file) if you want batch-level aggregation. Requires Claude Code 2.1.118+ (Hooks Reference).

## What it is

`PostToolBatch` fires after a full batch of parallel tool calls resolves, **before the next model call**. There is no matcher — it fires once per batch. Compare to `PostToolUse`, which fires once per individual tool call.

For audit / review workflows that fan out across many files (`/code-quality:audit`, `/code-quality:security`, `/code-quality:solid`, `/code-quality:dry`), per-tool firing is noisy: each lint result emits its own hook event, the user sees N separate summaries, and per-tool aggregation has to be reconstructed downstream. `PostToolBatch` lets a single handler aggregate across all tool calls in the batch and emit one summary.

## When to use

- Aggregating findings across a batch of parallel `Bash` invocations of linters/scanners (PHPStan + Psalm + PHPMD running in parallel).
- Logging a single timestamped batch row to `.reports/batch-log.jsonl` instead of N rows per tool.
- Posting a single Slack summary on batch completion instead of per-tool fragments.
- Triggering a state sync (e.g., refreshing a check-run JSON) once after all parallel scanners settle.

## When **not** to use

- Per-tool gating where you need to block individual tool calls — that's `PreToolUse`.
- Per-tool error alerting where each failure should fire independently — that's `PostToolUse` / `PostToolUseFailure`.
- Single-tool flows (`/code-quality:lint` on one file) — the batch is size 1; standard `PostToolUse` is simpler.

## Worked example — batch summary aggregator

Project-local `.claude/hooks.json`:

```json
{
  "hooks": {
    "PostToolBatch": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${HOME}/.claude/scripts/quality-batch-summary.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Aggregator script `~/.claude/scripts/quality-batch-summary.sh`:

```bash
#!/usr/bin/env bash
# Reads the batch payload from stdin (JSON), summarizes audit findings.
set -eu
PAYLOAD=$(cat)

# Each tool call's output is in PAYLOAD.tool_calls[].output.
# Filter to lint/audit-flavored calls (heuristic: command starts with phpstan/psalm/phpmd/eslint/semgrep).
echo "$PAYLOAD" | jq -r '
  .tool_calls
  | map(select(.input.command? | test("^(ddev exec )?(phpstan|psalm|phpmd|eslint|semgrep|trivy|gitleaks)")))
  | "Quality batch — \(length) scanner(s):" ,
    (.[] | "  \(.input.command | split(" ")[0:2] | join(" ")): exit \(.exit_code // "?")")
'

exit 0
```

The script receives the batch payload on stdin (per Hooks Reference); each tool call has `input`, `output`, and `exit_code`. Filter to relevant tools, summarize, and emit one consolidated message.

## Why this plugin doesn't ship it by default

- Plugin-scoped `PostToolBatch` would fire across **every** Claude Code conversation while this plugin is enabled — including conversations that have nothing to do with quality auditing. That is the same noise problem `code-quality-audit/SKILL.md` solves for `FileChanged` by scoping linter-config watches to the skill (active only while the skill is loaded).
- `PostToolBatch` does not currently support a matcher (per the Hooks Reference). There's no way to scope it to "only during audit-style batches" at the hook layer; the handler script has to filter the payload itself (the example above does this with a `jq` test against the command name).
- Until upstream adds skill-scoped `PostToolBatch` or a matcher mechanism, the right place for this hook is **the user's project**, not the plugin.

## Future avenue

If `PostToolBatch` gains skill-scoping (matching this plugin's existing skill-scoped `FileChanged` + `PermissionDenied` pattern), or gains a matcher field, this plugin can ship a default-on aggregator. Track upstream changes in the Hooks Reference and re-evaluate.

## Cross-references

- `references/troubleshooting.md` — `Debug Your Config` cross-link for verifying the hook actually loads (`/hooks` slash command).
- Skill-scoped vs plugin-scoped hooks — see `CONVENTIONS.md` in plugin root.
- `if`-Bash subcommand semantics: `Bash(rm *)` matches `FOO=bar rm file` and `npm test && rm file` (per Hooks Reference 2026-04-25 clarification). There is no `&&`/`||` in `if` — register separate handlers for compound conditions.
