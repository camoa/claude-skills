# PostToolBatch Aggregation Pattern

> Status: documented optional pattern. **Not shipped as a default-on hook** by this plugin. Copy the snippets below into your project's `.claude/settings.json` (or a project-local hooks file) if you want batch-level aggregation of agent-team runs. Requires Claude Code v2.1.118+ (Hooks Reference).

## What it is

`PostToolBatch` fires once after a full batch of parallel tool calls resolves, **before the next model call**. There is no matcher — it fires on every batch. Compare to `PostToolUse`, which fires once per individual tool call (and so fires concurrently when Claude makes parallel calls).

The framework's agent-team commands fan out across multiple teammates that each run tools and write their own output:

- **`/research-team`** spawns a 3-teammate Phase-1 research team; each teammate writes its own findings file, then the lead synthesizes.
- **`/validate:team`** spawns a 4-teammate validation team; each owns a subset of the v3.13.0 gates and writes its per-gate envelope.

When those teammates' tool calls land as a parallel batch, `PostToolBatch` is the one place a handler sees the whole batch at once — so it can emit a single roll-up instead of reconstructing it from N per-tool events.

## When to use

- Rolling up `/research-team` per-teammate findings files into one "all three perspectives written" line once the batch settles.
- Logging a single timestamped row per team run to a project log instead of one row per teammate.
- Posting a single notification (Slack, etc.) on team-run completion rather than per-teammate fragments.

## When not to use

- Per-tool gating — that is `PreToolUse`.
- Per-teammate error alerting where each failure should fire independently — that is `PostToolUse` / `PostToolUseFailure`.
- Single-agent flows (`/research`, and `/validate:all` which runs gates sequentially) — there is no parallel batch to aggregate; standard per-step handling is simpler.

## Worked example — team-run roll-up

Project-local `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolBatch": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/team-batch-summary.sh",
            "args": [],
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Aggregator `.claude/hooks/team-batch-summary.sh`:

```bash
#!/usr/bin/env bash
# Reads the PostToolBatch payload on stdin; summarizes teammate output writes.
set -eu
PAYLOAD=$(cat)
echo "$PAYLOAD" | jq -r '
  .tool_calls
  | map(select(
      (.tool_name == "Write")
      and ((.tool_input.file_path // "") | test("research-team-|/validations/"))
    ))
  | select(length > 0)
  | "drupal-dev-framework team batch — \(length) teammate output(s):",
    (.[] | "  \(.tool_input.file_path)")
'
exit 0
```

`PostToolBatch` input carries `tool_calls[]`, each element with `tool_name`, `tool_input`, `tool_use_id`, and `tool_response` (Hooks Reference). The handler filters the batch to teammate output writes and emits one consolidated line; emit it as `additionalContext` JSON if you want Claude to see the roll-up before the next turn.

## Why this plugin does not ship it by default

- A plugin-scoped `PostToolBatch` hook fires on **every** batch in **every** Claude Code conversation while drupal-dev-framework is enabled — including conversations that never touch `/research-team` or `/validate:team`. That is pure noise for the common case.
- `PostToolBatch` has **no matcher** (Hooks Reference) — there is no hook-layer way to scope it to "only during team runs." The handler script must filter the payload itself (the example does this with a `jq` test).
- Until upstream adds a matcher or skill-scoping for `PostToolBatch`, the right home for this hook is the **user's project**, not the plugin. This mirrors code-quality-tools' decision for the same primitive.

## Future avenue

If `PostToolBatch` gains a matcher or skill-scoping, the framework can revisit shipping a default-on team-run aggregator scoped to `/research-team` and `/validate:team`. Track the Hooks Reference and re-evaluate.

## Cross-references

- `commands/research-team.md`, `commands/validate-team.md` — the team commands whose output a project-local aggregator would roll up.
- `references/troubleshooting.md` — verifying a hook actually loads (`/hooks`).
- code-quality-tools ships the sibling pattern at `skills/code-quality-audit/references/post-batch-aggregation.md`.
