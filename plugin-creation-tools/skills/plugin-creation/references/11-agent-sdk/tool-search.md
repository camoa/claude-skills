# Tool Search (Agent SDK)

Tool search lets the agent work with **hundreds or thousands of tools** without loading every tool definition into context. The agent searches a catalog and loads the 3–5 most relevant tools on demand.

This matters for plugin authors when:
- Your plugin exposes dozens of MCP tools and you don't want them all in every user's context
- You're building an SDK app that connects to multiple remote MCP servers
- Tool selection accuracy matters (degrades past ~30–50 tools loaded at once)

Tool search is **enabled by default** in the SDK.

## The problem it solves

Two scaling problems hit plugin authors around ~30–50 tools:

1. **Context bloat.** 50 tools can use **10–20K tokens** of context just for definitions — before any actual work happens.
2. **Selection accuracy.** Past ~30–50 tools in context, Claude's ability to pick the right tool drops noticeably.

Tool search trades one upfront **search round-trip** for a smaller context on every turn. For small tool sets (<~10 tools), eager loading is still faster — use `ENABLE_TOOL_SEARCH=false` in that case.

## Configuration

Via the `ENABLE_TOOL_SEARCH` environment variable (set in process env or `options.env`):

| Value | Behavior |
|-------|----------|
| unset / `true` | Always on. Tool defs never loaded into context upfront. Default. |
| `auto` | Activates when tool defs exceed **10%** of the context window; otherwise loads all upfront. |
| `auto:N` | Same as `auto` with threshold `N%`. `auto:5` activates at 5%, lower values activate sooner. |
| `false` | Always off. All tool defs loaded every turn. |

## Minimum example

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

for await (const msg of query({
  prompt: "Find and run the appropriate database query",
  options: {
    mcpServers: {
      "enterprise-tools": { type: "http", url: "https://tools.example.com/mcp" },
    },
    allowedTools: ["mcp__enterprise-tools__*"],  // wildcard pre-approves all
    env: { ENABLE_TOOL_SEARCH: "auto:5" },
  },
})) {
  // ...
}
```

```python
options = ClaudeAgentOptions(
    mcp_servers={"enterprise-tools": {"type": "http", "url": "https://tools.example.com/mcp"}},
    allowed_tools=["mcp__enterprise-tools__*"],
    env={"ENABLE_TOOL_SEARCH": "auto:5"},
)
```

## Optimize tool discovery

Search matches against tool **names** and **descriptions**. Plugin-author takeaways:

1. **Use descriptive tool names.** `search_slack_messages` surfaces on more queries than `query_slack`.
2. **Write keyword-rich descriptions.** "Search Slack messages by keyword, channel, or date range" beats "Query Slack" by a wide margin.
3. **Categorize in your system prompt.** Add a hint: `"You can search for tools to interact with Slack, GitHub, and Jira."` — this gives the agent context about what's searchable.

## Limits

- **Maximum tools**: 10,000 per catalog
- **Search returns**: 3–5 most relevant tools per search
- **Model support**: Sonnet 4+, Opus 4+ — **no Haiku**

## Plugin-author patterns

### Pattern 1: Many MCP tools in one plugin

If your plugin exposes 20+ MCP tools, tool search is how users get acceptable performance. Document the `ENABLE_TOOL_SEARCH=auto:5` env var in your plugin README.

### Pattern 2: Deferred over eager

The Claude Code harness also has a "deferred tools" mechanism exposed via `ToolSearch`. The SDK's tool search operates on the **same idea at the MCP layer**: tool definitions aren't loaded until the agent searches for them. Use this when a plugin bundles a large tool catalog alongside a thin user-facing skill.

### Pattern 3: Small-set opt-out

If your plugin exposes <10 tools and the user is running through the SDK, set `ENABLE_TOOL_SEARCH=false` to skip the search round-trip. Faster first response, same context cost.

## Compaction interaction

When the SDK compacts earlier messages to free context, **previously discovered tools may be removed** from the active set. The agent will search again as needed. This is usually transparent, but for very long sessions you may see repeated searches for the same tool.

## See Also

- [`custom-tools.md`](custom-tools.md) — building tools the search catalog covers
- [`../02-philosophy/core-philosophy.md`](../02-philosophy/core-philosophy.md) — context-budget guidance
- Upstream: [Tool Search](https://docs.claude.com/en/agent-sdk/tool-search), [Tool Search in the API](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool)
