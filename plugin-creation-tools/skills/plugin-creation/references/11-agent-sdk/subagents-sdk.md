# Subagents in the SDK

Plugin authors defining subagents inside a plugin use Markdown frontmatter (`.claude/agents/*.md`) — see [`../05-agents/writing-agents.md`](../05-agents/writing-agents.md). The Agent SDK offers a **programmatic** alternative: define subagents inline in your code. The two approaches are complementary, not competing.

Use programmatic definitions when:
- Your plugin ships an SDK-based companion that builds agents dynamically at runtime
- Agent configuration depends on user input or runtime state
- You need different agents per request (e.g. strict vs lenient reviewer based on risk)
- You're writing test harnesses that spawn throwaway agents

## Markdown vs programmatic — field parity

| Markdown frontmatter | SDK `AgentDefinition` | Notes |
|----------------------|-----------------------|-------|
| `description:` | `description` | Natural-language activation trigger |
| body (system prompt) | `prompt` | Required in SDK; Markdown body is the system prompt |
| `tools:` | `tools` | Array of allowed tool names |
| `model:` | `model` | `sonnet` / `opus` / `haiku` / `inherit` |
| `skills:` | `skills` | Named skills loaded into the subagent |
| `memory:` | `memory` | `user` / `project` / `local` (Python only) |
| `mcpServers:` | `mcpServers` | Name reference or inline config |
| `permissionMode:` | — inherited from parent | SDK subagents inherit parent's permission mode; frontmatter value is ignored in plugin-packaged Markdown agents too |
| `hooks:` | — via parent `hooks` option | Scope hooks via the parent's config; plugin-packaged agent `hooks` are silently ignored |

Programmatic definitions **take precedence** when both exist with the same name.

## Minimum programmatic example

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const msg of query({
  prompt: "Review auth.ts for security issues",
  options: {
    allowedTools: ["Read", "Grep", "Glob", "Agent"],  // Agent required to spawn subagents
    agents: {
      "code-reviewer": {
        description: "Security-focused code reviewer. Use for quality and security audits.",
        prompt: "You are a security reviewer...",
        tools: ["Read", "Grep", "Glob"],
        model: "sonnet",
      },
    },
  },
})) {
  if ("result" in msg) console.log(msg.result);
}
```

```python
from claude_agent_sdk import query, ClaudeAgentOptions, AgentDefinition

async for msg in query(
    prompt="Review auth.py for security issues",
    options=ClaudeAgentOptions(
        allowed_tools=["Read", "Grep", "Glob", "Agent"],
        agents={
            "code-reviewer": AgentDefinition(
                description="Security-focused code reviewer. Use for quality and security audits.",
                prompt="You are a security reviewer...",
                tools=["Read", "Grep", "Glob"],
                model="sonnet",
            ),
        },
    ),
):
    if hasattr(msg, "result"):
        print(msg.result)
```

The **`Agent` tool** must be in `allowedTools` — it's the mechanism Claude uses to spawn subagents. Without it, defining agents has no effect.

## What subagents inherit

A subagent starts with a **fresh context window**. The only channel from parent to subagent is the prompt string the parent writes into the `Agent` tool call.

| Subagent receives | Subagent does NOT receive |
|-------------------|---------------------------|
| Its own system prompt (`AgentDefinition.prompt`) + the Agent-tool prompt | Parent conversation history or tool results |
| Project `CLAUDE.md` (only if `settingSources` includes `project`) | Skills — unless listed in `skills` |
| Tool definitions (inherited or restricted via `tools`) | Parent's system prompt |

**Design implication:** include every file path, error message, or decision the subagent needs **in the `Agent` tool prompt**. The parent's memory of the task is not transferred.

## Automatic vs explicit invocation

- **Automatic**: Claude reads each `description` and routes tasks that match. Write specific, action-oriented descriptions to improve routing.
- **Explicit**: mention the subagent by name in your prompt — `"Use the code-reviewer agent to..."` — to bypass auto-routing.

## Dynamic configuration pattern

Factory functions return `AgentDefinition` based on runtime state. Useful for:
- Plan-tier escalation (cheap model for free users, stronger for paid)
- Strictness flags (lenient vs strict reviewer)
- Per-tenant customization

```python
def create_security_agent(level: str) -> AgentDefinition:
    is_strict = level == "strict"
    return AgentDefinition(
        description="Security code reviewer",
        prompt=f"You are a {'strict' if is_strict else 'balanced'} reviewer...",
        tools=["Read", "Grep", "Glob"],
        model="opus" if is_strict else "sonnet",
    )

options = ClaudeAgentOptions(
    allowed_tools=["Read", "Grep", "Glob", "Agent"],
    agents={"security-reviewer": create_security_agent("strict")},
)
```

## Sessions

The SDK also exposes **sessions** — multi-turn conversations with state. A single `query()` call is a one-shot; sessions let you keep a conversation alive across prompts:

- **Python**: create a session object and call `.send()` / iterate messages; persist state across interactions
- **TypeScript**: similar pattern via the session helpers in `@anthropic-ai/claude-agent-sdk`

Sessions are what power long-running agent applications (customer-support bots, IDE integrations). For one-off scripted runs (CI validators, test harnesses), `query()` is enough.

See [Sessions guide](https://docs.claude.com/en/agent-sdk/sessions) for the full API.

## Caveats

- **Subagents cannot spawn subagents.** Do not include `Agent` in a subagent's `tools` array.
- **`general-purpose` is available by default.** Even without custom agents, if `Agent` is in `allowedTools` Claude can spawn the built-in general-purpose subagent.
- **Permission inheritance is strict.** When the parent uses `bypassPermissions`, `acceptEdits`, or `auto`, subagents inherit that mode and cannot override it. Subagents with less-constrained prompts can take dangerous actions under inherited permissions — audit your `AgentDefinition.prompt` strings with this in mind.

## See Also

- [`permissions.md`](permissions.md) — SDK permission handling
- [`../05-agents/writing-agents.md`](../05-agents/writing-agents.md) — Markdown-defined agents in plugins
- [`../08-configuration/permission-modes.md`](../08-configuration/permission-modes.md) — mode inheritance rules
- Upstream: [Subagents in the SDK](https://docs.claude.com/en/agent-sdk/subagents), [Sessions](https://docs.claude.com/en/agent-sdk/sessions)
