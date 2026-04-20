# Custom Tools (Agent SDK)

The Agent SDK lets you define custom tools programmatically and make them available to Claude in your application. Tools are wrapped in an **in-process SDK MCP server** and passed to `query()`.

For plugin authors, custom tools are relevant when:
1. Your plugin ships an SDK-based companion app (validator, test runner, deployment tool) that needs its own tool surface.
2. You're writing test harnesses for your plugin's skills/agents.
3. You want to expose the same tool to both CLI users (via `.mcp.json`) and SDK users (via `createSdkMcpServer`).

## The four parts of a tool

| Part | Purpose |
|------|---------|
| **Name** | Unique identifier Claude uses to call the tool |
| **Description** | What the tool does — Claude reads this to decide when to call it |
| **Input schema** | Expected arguments. TS uses Zod; Python uses a dict or JSON Schema |
| **Handler** | Async function that runs. Returns `{ content, isError? }` |

## Minimal example

```typescript
import { tool, createSdkMcpServer, query } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

const getTemperature = tool(
  "get_temperature",
  "Get the current temperature at a location",
  {
    latitude: z.number().describe("Latitude coordinate"),
    longitude: z.number().describe("Longitude coordinate"),
  },
  async (args) => {
    const res = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=${args.latitude}&longitude=${args.longitude}&current=temperature_2m`);
    const data = await res.json();
    return { content: [{ type: "text", text: `${data.current.temperature_2m}°F` }] };
  }
);

const weatherServer = createSdkMcpServer({
  name: "weather",
  version: "1.0.0",
  tools: [getTemperature],
});

for await (const msg of query({
  prompt: "Temperature in SF?",
  options: {
    mcpServers: { weather: weatherServer },
    allowedTools: ["mcp__weather__get_temperature"],
  },
})) {
  console.log(msg);
}
```

```python
from claude_agent_sdk import tool, create_sdk_mcp_server, query, ClaudeAgentOptions

@tool(
    "get_temperature",
    "Get the current temperature at a location",
    {"latitude": float, "longitude": float},
)
async def get_temperature(args):
    # ... fetch and return
    return {"content": [{"type": "text", "text": "..."}]}

weather_server = create_sdk_mcp_server(
    name="weather", version="1.0.0", tools=[get_temperature],
)

async for msg in query(
    prompt="Temperature in SF?",
    options=ClaudeAgentOptions(
        mcp_servers={"weather": weather_server},
        allowed_tools=["mcp__weather__get_temperature"],
    ),
):
    print(msg)
```

## Tool naming

Registered tools are exposed to Claude as `mcp__{server_name}__{tool_name}`. In the example above the fully qualified name is `mcp__weather__get_temperature`. Use this exact form in `allowedTools` and in hook matchers.

To allow every tool from a server, use `mcp__weather__.*` (the `.*` makes the matcher a regex — see [`../06-hooks/writing-hooks.md`](../06-hooks/writing-hooks.md)).

## Optional parameters

- **TypeScript (Zod):** add `.default(...)` or `.optional()` to the field.
- **Python (dict schema):** every key is required. For optional parameters, leave them out of the schema, describe them in the tool description, and read with `args.get(...)` in the handler.
- **Python (JSON Schema dict):** supports enums, ranges, and optional fields directly — use when you need more than the dict shorthand.

## Return value structure

Handlers must return an object with:
- `content` (required): array of result blocks, each `{ type: "text" | "image" | "resource", ... }`
- `isError` (optional): `true` to signal failure — Claude reacts to this in the agent loop instead of the call throwing

Example image return:
```python
return {
    "content": [
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "..."}}
    ]
}
```

## Parallel tool calls

Claude can call tools in parallel **only** if every tool in a batch is marked safe. Tools with no side effects should set `readOnlyHint: true`:

```typescript
tool("lookup_price", "...", schema, handler, { readOnlyHint: true });
```

Without the annotation, Claude serializes tool calls conservatively. This is the single highest-leverage perf win for tool-heavy agents.

## Error handling pattern

Return an error block instead of throwing:

```python
return {
    "isError": True,
    "content": [{"type": "text", "text": f"Request failed: {error}"}],
}
```

Claude sees the error text and can react (retry, try a different input, ask the user). Throwing kills the tool loop.

## Restricting built-in tools

Pass a `tools` array to keep Claude focused:

```typescript
options: { tools: ["Read", "Grep"] }  // no Write, Edit, Bash, etc.
```

Combined with custom tools, this is how you build narrow-purpose agents. Omit `tools` to get the full built-in set.

## Plugin-author patterns

### Pattern 1: Shared tool surface

Ship the same tool to both CLI and SDK users:
- **CLI**: declare it in your plugin's `.mcp.json`
- **SDK**: re-export the handler and call `createSdkMcpServer` at runtime

This requires the tool's core logic be library code (not tied to MCP transport). Your plugin's MCP entry and the SDK registration both call the same function.

### Pattern 2: Validator harness

Your plugin's `/plugin-creation-tools:validate`-style commands can be implemented as an SDK-based test harness that registers the plugin's components, runs a scripted query, and asserts structured output (see [`structured-outputs.md`](structured-outputs.md)).

### Pattern 3: Tool search for large plugins

If your plugin exposes many tools, register them eagerly eats context. Use [`tool-search.md`](tool-search.md) to load them on demand.

## See Also

- [`tool-search.md`](tool-search.md) — deferred loading for tool-heavy plugins
- [`structured-outputs.md`](structured-outputs.md) — force JSON responses for CI
- [`../07-mcp/`](../07-mcp/) — plugin-side MCP server authoring
- [`../06-hooks/writing-hooks.md`](../06-hooks/writing-hooks.md) — matcher patterns for MCP tool names
- Upstream: [Custom Tools](https://docs.claude.com/en/agent-sdk/custom-tools)
