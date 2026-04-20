# Structured Outputs (Agent SDK)

Structured outputs force the agent to return a JSON object conforming to a schema you provide. The result arrives validated and type-checked — no regex parsing of free-form responses.

For plugin authors, this is **how you expose machine-readable output from agent-driven commands**. If your plugin's validator, lint runner, or audit command is implemented via the SDK, structured outputs are what CI consumes.

## Why it matters for plugins

Without structured outputs:
- CI scripts parse agent prose with regex → brittle
- Downstream tooling can't consume agent results reliably
- The agent can phrase the same result fifty ways

With structured outputs:
- One schema contract between the agent and every consumer
- `structured_output` is validated before you see it
- Type-safe parsing with Zod (TS) or Pydantic (Python)

## Quick start

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

const schema = {
  type: "object",
  properties: {
    company_name: { type: "string" },
    founded_year: { type: "number" },
    headquarters: { type: "string" },
  },
  required: ["company_name"],
};

for await (const msg of query({
  prompt: "Research Anthropic and return key info",
  options: {
    outputFormat: { type: "json_schema", schema },
  },
})) {
  if (msg.type === "result" && msg.subtype === "success" && msg.structured_output) {
    console.log(msg.structured_output);
    // { company_name: "Anthropic", founded_year: 2021, headquarters: "San Francisco, CA" }
  }
}
```

```python
from claude_agent_sdk import query, ClaudeAgentOptions, ResultMessage

schema = {
    "type": "object",
    "properties": {
        "company_name": {"type": "string"},
        "founded_year": {"type": "number"},
        "headquarters": {"type": "string"},
    },
    "required": ["company_name"],
}

async for msg in query(
    prompt="Research Anthropic and return key info",
    options=ClaudeAgentOptions(output_format={"type": "json_schema", "schema": schema}),
):
    if isinstance(msg, ResultMessage) and msg.structured_output:
        print(msg.structured_output)
```

The validated result appears on the `ResultMessage` (Python) / result message (TS) as `structured_output`.

## Schemas via Zod / Pydantic

Writing JSON Schema by hand is tedious and un-type-safe. Generate it from Zod (TS) or Pydantic (Python):

```typescript
import { z } from "zod";

const FeaturePlanSchema = z.object({
  summary: z.string(),
  steps: z.array(z.object({
    description: z.string(),
    complexity: z.enum(["low", "medium", "high"]),
  })),
  risks: z.array(z.string()),
});

const jsonSchema = z.toJSONSchema(FeaturePlanSchema);
// pass jsonSchema to options.outputFormat.schema
```

```python
from pydantic import BaseModel

class Step(BaseModel):
    description: str
    complexity: str  # "low" | "medium" | "high"

class FeaturePlan(BaseModel):
    summary: str
    steps: list[Step]
    risks: list[str]

# FeaturePlan.model_json_schema() returns the JSON Schema to pass
```

Both SDKs use **standard JSON Schema** — all basic types, `enum`, `const`, `required`, nested objects, and `$ref` definitions are supported. See the upstream [JSON Schema limitations](https://platform.claude.com/docs/en/build-with-claude/structured-outputs#json-schema-limitations) page for exceptions.

## `output_format` configuration

| Field | Description |
|-------|-------------|
| `type` | Always `"json_schema"` for structured outputs |
| `schema` | JSON Schema object. Generate from Zod / Pydantic or write inline. |

No other fields are required. The validator runs automatically before your consumer code sees the result.

## Plugin-author patterns

### Pattern 1: Validator output contract

A plugin validator command returns a consistent result shape. Define once, use everywhere:

```python
from pydantic import BaseModel

class ValidationIssue(BaseModel):
    file: str
    line: int | None = None
    severity: str  # "error" | "warning" | "info"
    code: str
    message: str

class ValidationResult(BaseModel):
    passed: bool
    total_issues: int
    issues: list[ValidationIssue]

schema = ValidationResult.model_json_schema()
# use schema in your plugin's SDK-driven validator
```

Routines and CI scripts can now parse `structured_output` directly instead of scraping text.

### Pattern 2: REVIEW.md / code-review plugins

Code-review plugins benefit heavily — structured output lets you emit PR review comments deterministically. See [`../10-distribution/`](../10-distribution/) for the REVIEW.md pattern.

### Pattern 3: Paper-test harness

When you're running the `code-paper-test` plugin's `/paper-test` against a plugin component via the SDK, force structured outputs so the harness can aggregate pass/fail across runs.

## Error handling

Two failure modes:
- **Schema-validation failure** — the agent produced output the schema rejected. Check `msg.subtype` and the error fields on the result message. The agent sometimes needs prompt refinement to match complex schemas.
- **Runtime error** — underlying API or tool failure. Handle as with any SDK query.

Keep schemas **tight but not rigid**: required fields for things the agent must always produce, optional fields for things it might not find. Over-constrained schemas cause repeated validation failures.

## See Also

- [`overview.md`](overview.md) — Agent SDK overview
- [`../10-distribution/`](../10-distribution/) — CI integration patterns
- Upstream: [Structured Outputs](https://docs.claude.com/en/agent-sdk/structured-outputs), [Build with Claude — structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
