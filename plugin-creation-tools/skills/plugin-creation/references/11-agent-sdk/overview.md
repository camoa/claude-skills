# Agent SDK Overview

The **Agent SDK** (formerly Claude Code SDK) is the programmatic interface to the same tool loop, context management, and skill/hook/plugin machinery that power Claude Code. Use it when you need Claude Code's capabilities inside your own Python or TypeScript application — CI pipelines, headless automation, custom chat surfaces, or production agents.

For plugin authors, the SDK matters because:
1. **Testing** — you can script your plugin's commands and agents against a real Claude session.
2. **CI integration** — validator routines and `--json-schema` output let plugin repos automate checks (see [`../10-distribution/`](../10-distribution/)).
3. **Cross-deployment** — a plugin you ship to Claude Code users may also be consumed by Agent SDK apps that load `.claude/` settings.

## Package names (post-rename)

| Language | Package | Imports |
|----------|---------|---------|
| TypeScript / JavaScript | `@anthropic-ai/claude-agent-sdk` | `query`, `tool`, `createSdkMcpServer` |
| Python | `claude-agent-sdk` | `query`, `ClaudeAgentOptions` |

Old names (`@anthropic-ai/claude-code`, `claude-code-sdk`, `ClaudeCodeOptions`) are **retired**. Existing code must be migrated — see [`migration.md`](migration.md).

## The one-line mental model

```python
from claude_agent_sdk import query, ClaudeAgentOptions

async for message in query(
    prompt="Fix the bug in auth.py",
    options=ClaudeAgentOptions(allowed_tools=["Read", "Edit", "Bash"]),
):
    print(message)
```

Claude autonomously reads files, edits them, runs commands, and returns messages. You don't write the tool-execution loop — the SDK runs it for you.

This is the fundamental difference from the **Anthropic Client SDK** (`anthropic` package), which gives you raw API access and requires you to implement the tool loop yourself.

## When to use SDK vs CLI vs Client SDK

| Need | Use |
|------|-----|
| Daily interactive development | Claude Code CLI |
| One-off terminal task | Claude Code CLI |
| CI/CD pipeline that needs Claude | Agent SDK |
| Custom app embedding Claude Code | Agent SDK |
| Production agent with full autonomy | Agent SDK |
| Direct API call with your own tool loop | Anthropic Client SDK |
| No tool use, just completion | Anthropic Client SDK |

## Capabilities overview

The SDK gives you every Claude Code capability, programmable:

- **Built-in tools** — Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch, etc.
- **Custom tools** — register your own tools for the model (see [`custom-tools.md`](custom-tools.md))
- **Subagents** — delegate to named subagents with their own context window (see [`subagents-sdk.md`](subagents-sdk.md))
- **Sessions** — multi-turn conversations with state (see [`subagents-sdk.md`](subagents-sdk.md))
- **Session storage** — by default the SDK writes session transcripts to JSONL under `~/.claude/projects/`; a `SessionStore` adapter (`append`/`load` + 3 optional methods) mirrors them to your own backend (S3, Redis, a DB) so a session created on one host can resume on another. See the upstream **Agent SDK Session Storage** guide.
- **Permissions** — the same permission-mode system as the CLI (see [`permissions.md`](permissions.md))
- **Structured outputs** — force JSON-schema-compliant responses (see [`structured-outputs.md`](structured-outputs.md))
- **Tool search** — defer tool loading for large tool catalogs (see [`tool-search.md`](tool-search.md))
- **Hooks** — PreToolUse / PostToolUse / etc. fire inside SDK sessions too
- **MCP servers** — same `.mcp.json` loading as the CLI
- **Plugins** — programmatic `plugins` option; `.claude/` auto-loading optional
- **Observability** — OpenTelemetry traces, cost tracking (see [`observability.md`](observability.md))

## `.claude/` loading behavior

By default the SDK **does not** load filesystem settings (`.claude/`, CLAUDE.md, custom slash commands) unless you opt in. This is the opposite of the CLI default.

Opt in by passing `settingSources` / `setting_sources`:

```typescript
query({
  prompt: "...",
  options: { settingSources: ["user", "project", "local"] }
})
```

```python
ClaudeAgentOptions(setting_sources=["user", "project", "local"])
```

> **Caveat:** Current SDK releases have partially reverted this — omitting the option loads `user`/`project`/`local` for `query()` to match CLI behavior. Pass an empty list explicitly if you need the isolated behavior. Early Python SDK releases treated an empty list the same as omitting the option; upgrade before relying on `setting_sources=[]`.

## System prompt

The SDK also does **not** inherit Claude Code's CLI system prompt by default (v0.1.0+). To get Claude-Code-like behavior:

```typescript
query({
  prompt: "...",
  options: { systemPrompt: { type: "preset", preset: "claude_code" } }
})
```

Without this, Claude runs with a minimal system prompt. Use a custom string if your agent needs a specialized persona.

## Authentication

Set one of:
- `ANTHROPIC_API_KEY` — direct Anthropic API
- `CLAUDE_CODE_USE_BEDROCK=1` + AWS credentials — Amazon Bedrock
- `CLAUDE_CODE_USE_VERTEX=1` + Google Cloud credentials — Vertex AI
- `CLAUDE_CODE_USE_FOUNDRY=1` + Azure credentials — Azure AI Foundry

**Not permitted**: claude.ai login or Pro-tier rate limits from third-party agents unless explicitly approved.

## For plugin authors: testing your plugin via the SDK

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def test_plugin():
    async for message in query(
        prompt="Run /my-plugin:validate against this directory",
        options=ClaudeAgentOptions(
            setting_sources=["project"],
            allowed_tools=["Read", "Grep", "Bash"],
        ),
    ):
        if hasattr(message, "result"):
            print(message.result)

asyncio.run(test_plugin())
```

This is the pattern the [Routines-based auto-validate](../10-distribution/) uses under the hood.

## See Also

- [`migration.md`](migration.md) — migrating from Claude Code SDK
- [`custom-tools.md`](custom-tools.md) — register your own tools
- [`subagents-sdk.md`](subagents-sdk.md) — programmatic subagent definitions
- [`permissions.md`](permissions.md) — permission-mode handling
- [`structured-outputs.md`](structured-outputs.md) — `--json-schema` for CI
- [`tool-search.md`](tool-search.md) — deferred tool loading
- [`observability.md`](observability.md) — tracing and cost tracking
- [`agent-loop.md`](agent-loop.md) — how the loop actually works
- Upstream: [Agent SDK Overview](https://docs.claude.com/en/agent-sdk/overview), [Quickstart](https://docs.claude.com/en/agent-sdk/quickstart)
