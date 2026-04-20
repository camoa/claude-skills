# The Agent Loop

The Agent SDK runs the same execution loop that powers the Claude Code CLI. Plugin authors benefit from understanding it because your plugin's skills, hooks, commands, and agents all participate in this loop — knowing where each one fires is the difference between a plugin that composes cleanly and one that fights the runtime.

## The loop at a glance

Every session follows one cycle, repeated until Claude produces output with no tool calls:

1. **Receive prompt** — Claude receives the prompt + system prompt + tool defs + history. SDK yields `SystemMessage(subtype="init")` with session metadata.
2. **Evaluate and respond** — Claude replies with text, tool calls, or both. SDK yields an `AssistantMessage`.
3. **Execute tools** — SDK runs each tool call. [Hooks](../06-hooks/writing-hooks.md) can intercept, modify, or block. Each tool result yields a `UserMessage`.
4. **Repeat** — steps 2–3 loop. Each full cycle is **one turn**.
5. **Final** — Claude produces a text-only response. SDK yields the final `AssistantMessage`, then a `ResultMessage` with the final text, tokens, cost, and session ID.

A quick question ("what files are here?") might be 1–2 turns. A complex task ("refactor auth and update tests") can chain dozens.

## Message types

| Type | Yielded when | Plugin relevance |
|------|--------------|------------------|
| `SystemMessage` | Session init and compaction boundary | `init` contains session ID, metadata. `compact_boundary` marks where context was compacted. |
| `AssistantMessage` | After each Claude turn | Text + tool-call blocks. This is where you see what Claude decided. |
| `UserMessage` | After each tool execution | Contains the tool result fed back to Claude. |
| `StreamEvent` | Only with partial messages enabled | Raw API streaming deltas. |
| `ResultMessage` | End of loop | Final text, token usage, cost, subtype (`success` / limit-hit reason). |

**TypeScript nuance:** `AssistantMessage` and `UserMessage` wrap the raw API message — content blocks live at `message.message.content`, not `message.content`. Python accesses them directly.

**Python type check:** `isinstance(msg, ResultMessage)`.
**TypeScript type check:** `msg.type === "result"`.

## Budget controls

Three caps plugin authors should know about:

| Option | What it caps |
|--------|--------------|
| `max_turns` / `maxTurns` | Maximum tool-use turns (final text-only turn not counted) |
| `max_budget_usd` / `maxBudgetUsd` | Spend cap across the whole session |
| `max_thinking_tokens` / `maxThinkingTokens` | Extended-thinking budget (when model supports it) |

Without limits, the loop runs until Claude finishes on its own. Fine for well-scoped tasks; risky for open-ended prompts. **Production rule of thumb:** always set a turn cap and a dollar cap.

## Effort level

The SDK honors an `effort` level (low/medium/high) that controls how hard Claude tries. It maps to model selection and thinking budget.

Plugin frontmatter has the same field:
```yaml
# skills/my-skill/SKILL.md
---
name: my-skill
description: ...
effort: medium
---
```

When an SDK app loads your plugin, the `effort` value on your skill/agent frontmatter is honored.

## Tool execution

The SDK runs tools **in parallel when safe**. Parallelism requires every tool in a batch to be marked read-only (custom tools via `readOnlyHint: true`, built-ins annotated by the runtime). Without that annotation, the loop serializes.

Plugin-hook interaction: hooks run **before** tool execution (`PreToolUse`) and **after** (`PostToolUse`, `PostToolUseFailure`). See [`../06-hooks/writing-hooks.md`](../06-hooks/writing-hooks.md) for the full sequence.

## Context window behavior

The SDK manages the context window on Claude's behalf. Key things plugin authors should know:

- **Skill descriptions** are loaded upfront (subject to the 1% budget / 8,000-char fallback — see [`../02-philosophy/core-philosophy.md`](../02-philosophy/core-philosophy.md))
- **Skill bodies** are loaded **on invocation**, not at startup
- **Compaction** fires automatically when the context nears the limit. Hooks (`PreCompact`, `PostCompact`) can save/restore state
- **Tool definitions** can be loaded eagerly or on-demand (see [`tool-search.md`](tool-search.md))

After compaction:
- Path-scoped rules (`paths:` frontmatter) are **lost** until their trigger file is read again
- Unscoped CLAUDE.md and rules are **re-injected** from disk
- Invoked skill bodies are **re-injected** at 5,000 tokens/skill, 25,000 total

Design plugins around this: if a rule must persist, don't use `paths:`.

## Sessions and continuity

A single `query()` is one-shot. For multi-turn conversations, use **sessions** (see [`subagents-sdk.md`](subagents-sdk.md) Sessions section). The session's `session_id` (from `SystemMessage(subtype="init")`) lets you resume later.

Subagents spawned via the `Agent` tool get their **own context window** — parent history does not cross over. The only channel is the prompt string written into the Agent tool call.

## Handling the result

```python
from claude_agent_sdk import query, AssistantMessage, ResultMessage

async for msg in query(prompt="..."):
    if isinstance(msg, AssistantMessage):
        # progress update — turn just completed
        pass
    if isinstance(msg, ResultMessage):
        if msg.subtype == "success":
            print(msg.result)
        else:
            print(f"Stopped: {msg.subtype}")  # hit max_turns, budget, etc.
```

**Don't break on `ResultMessage`** — a small number of trailing system events (`prompt_suggestion`, etc.) can arrive after it. Iterate to completion.

## Why plugin authors care

- **Where does my hook fire?** Step 3, before/after tool execution. See [`../06-hooks/hook-events.md`](../06-hooks/hook-events.md).
- **Where does my skill activate?** Claude reads skill descriptions at step 1 (loop start) and invokes them in step 2 when they match the prompt.
- **Where does my subagent run?** The parent calls `Agent`, which spawns the subagent in a fresh context, runs its own mini-loop, and returns the final message verbatim to the parent's step 3.
- **When does my MCP tool get loaded?** At step 1 (eagerly) or at the first search step (with tool search enabled).

Understanding these four beats makes plugin composition predictable.

## See Also

- [`overview.md`](overview.md) — SDK overview
- [`../06-hooks/writing-hooks.md`](../06-hooks/writing-hooks.md) — hooks fire inside this loop
- [`tool-search.md`](tool-search.md) — on-demand tool loading
- [`../02-philosophy/core-philosophy.md`](../02-philosophy/core-philosophy.md) — context budget numbers
- Upstream: [How the agent loop works](https://docs.claude.com/en/agent-sdk/agent-loop), [How Claude Code works](https://docs.claude.com/en/how-claude-code-works)
