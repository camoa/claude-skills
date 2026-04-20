# Migrating from Claude Code SDK to Agent SDK

The **Claude Code SDK** has been renamed to the **Claude Agent SDK**. The rename is a breaking change that affects every application that imported the old package. This page summarizes the migration for plugin authors — both for your own tooling and for documentation/skills you ship.

For the full upstream guide see [Migration Guide](https://docs.claude.com/en/agent-sdk/migration-guide).

## What changed

| Aspect | Old | New |
|--------|-----|-----|
| TS/JS package | `@anthropic-ai/claude-code` | `@anthropic-ai/claude-agent-sdk` |
| Python package | `claude-code-sdk` | `claude-agent-sdk` |
| Python options type | `ClaudeCodeOptions` | `ClaudeAgentOptions` |
| Docs location | Claude Code docs | API Guide → Agent SDK section |

The **Claude Code CLI itself is not affected**. Only the programmatic SDK changes.

## Migrate a TypeScript/JavaScript project

```bash
npm uninstall @anthropic-ai/claude-code
npm install @anthropic-ai/claude-agent-sdk
```

```typescript
// Before
import { query, tool, createSdkMcpServer } from "@anthropic-ai/claude-code";

// After
import { query, tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
```

Update `package.json`:
```json
{ "dependencies": { "@anthropic-ai/claude-agent-sdk": "^0.2.0" } }
```

Most named exports kept their names. Only the package string changes.

## Migrate a Python project

```bash
pip uninstall claude-code-sdk
pip install claude-agent-sdk
```

```python
# Before
from claude_code_sdk import query, ClaudeCodeOptions
options = ClaudeCodeOptions(model="claude-opus-4-7")

# After
from claude_agent_sdk import query, ClaudeAgentOptions
options = ClaudeAgentOptions(model="claude-opus-4-7")
```

Both the module name (`claude_code_sdk` → `claude_agent_sdk`) and the options type (`ClaudeCodeOptions` → `ClaudeAgentOptions`) changed.

## Breaking behavior changes (v0.1.0)

Beyond the rename, the SDK changed two defaults that affect existing code:

### 1. Minimal system prompt by default

**Before:** SDK inherited Claude Code's CLI system prompt.
**After:** SDK starts with a minimal system prompt. Your agent runs without Claude Code's coding-focused instructions.

Restore the old behavior:
```typescript
options: { systemPrompt: { type: "preset", preset: "claude_code" } }
```
```python
ClaudeAgentOptions(system_prompt={"type": "preset", "preset": "claude_code"})
```

Or pass a custom string for your own persona.

### 2. No `.claude/` auto-loading

**Before:** SDK read `~/.claude/settings.json`, project `.claude/settings.json`, `.claude/settings.local.json`, `CLAUDE.md`, and custom slash commands.
**After (v0.1.0):** Nothing loaded unless you opt in.

Opt in:
```typescript
options: { settingSources: ["user", "project", "local"] }
```
```python
ClaudeAgentOptions(setting_sources=["user", "project", "local"])
```

> **Caveat:** Current SDK releases have reverted this default for `query()` — omitting the option once again loads user/project/local to match the CLI. Pass `settingSources: []` (TS) or `setting_sources=[]` (Python) if you explicitly need isolated behavior. Python 0.1.59 and earlier treated empty list as omitted; upgrade before relying on it.

## What plugin authors should update

### In your own tooling

Any test scripts, CI helpers, or validator routines that import the SDK must be updated. Common places to check:

- `scripts/*.py` and `scripts/*.ts` in your plugin root
- GitHub Actions workflows that run `pip install claude-code-sdk` or `npm install @anthropic-ai/claude-code`
- Routine configurations that invoke the SDK
- Internal developer docs for your plugin

### In documentation you ship

If your plugin's `SKILL.md`, references, or examples mention "Claude Code SDK", rewrite to "Agent SDK" and link to [`overview.md`](overview.md). Leaving stale `Claude Code SDK` mentions in skill descriptions reduces retrieval accuracy — the term is no longer canonical.

### Grep your plugin before releasing

```bash
grep -rn "Claude Code SDK" path/to/your-plugin/
grep -rn "claude_code_sdk\|claude-code-sdk" path/to/your-plugin/
grep -rn "@anthropic-ai/claude-code[^-]" path/to/your-plugin/
grep -rn "ClaudeCodeOptions" path/to/your-plugin/
```

Every hit is a migration target. See the validator checks added in Track F (`skill-quality-reviewer.md`) — stale `Claude Code SDK` mentions are flagged as regressions.

## Why the rename happened

The original SDK was framed around coding tasks but had evolved into a general-purpose agent framework. The new name reflects that broader scope — building business agents, customer-support agents, SRE bots, etc. — not just coding agents.

For plugin authors this also means: if your plugin is coding-specific, that's still supported, but consider whether the SDK's wider scope opens new distribution channels.

## See Also

- [`overview.md`](overview.md) — current SDK capabilities
- Upstream: [Migration Guide](https://docs.claude.com/en/agent-sdk/migration-guide)
