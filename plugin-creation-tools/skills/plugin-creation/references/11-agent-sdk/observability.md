# Observability (Agent SDK)

The Agent SDK exports traces, metrics, and log events via **OpenTelemetry (OTLP)**. For plugin authors running production agents based on the SDK, this is the recommended way to get visibility into tool calls, model latency, token usage, and failures.

This is an enterprise-tier feature — most plugin authors shipping to Claude Code users directly won't need it, but plugins bundled into SDK apps should document what signals they emit.

## How telemetry flows

The Agent SDK runs the Claude Code CLI as a child process. The **CLI has OpenTelemetry instrumentation built in** — the SDK itself produces no telemetry. You configure exporters via environment variables, and the CLI exports directly to your collector.

Three independent signals, each with its own enable switch:

| Signal | Contains | Enable with |
|--------|----------|-------------|
| **Metrics** | Counters for tokens, cost, sessions, lines of code, tool decisions | `OTEL_METRICS_EXPORTER` |
| **Log events** | Structured records per prompt, API request, API error, tool result | `OTEL_LOGS_EXPORTER` |
| **Traces** (beta) | Spans per interaction, model request, tool call, and hook | `OTEL_TRACES_EXPORTER` + `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` |

Master switch: `CLAUDE_CODE_ENABLE_TELEMETRY=1`. Until set, no telemetry is exported regardless of exporter config.

## Minimum OTLP config

```python
OTEL_ENV = {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",  # for traces
    "OTEL_TRACES_EXPORTER": "otlp",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://collector.example.com:4318",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Bearer your-token",
}

options = ClaudeAgentOptions(env=OTEL_ENV)
```

```typescript
// TypeScript: options.env *replaces* inherited env — spread process.env
options: { env: { ...process.env, ...otelEnv } }
```

**Two places to set env:**
1. **Process env** (recommended for production) — set in shell, container, or orchestrator. Every `query()` picks them up automatically.
2. **Per-call `options.env`** — when different agents in the same process need different telemetry settings.

Python merges `env` on top of inherited env. TypeScript **replaces** it — always spread `process.env` first or you'll lose `PATH`, `ANTHROPIC_API_KEY`, etc.

## Compatible backends

Any OTLP-compatible backend: Honeycomb, Datadog, Grafana (Tempo/Loki/Mimir), Langfuse, or a self-hosted OpenTelemetry collector.

**Do not** set `console` as an exporter — the SDK uses stdout as its message channel, so console exporter output would corrupt it. Use a local collector or Jaeger container for local inspection instead.

## Short-lived calls need explicit flush

The OpenTelemetry SDK inside the CLI batches exports. If your agent finishes before the batch interval, telemetry is lost. Flush explicitly when running one-shot scripts — see the upstream guide's flush section.

## Tagging and filtering

Standard OTLP resource attributes apply. Add `OTEL_RESOURCE_ATTRIBUTES` to tag every signal with your app name, environment, and plugin version:

```
OTEL_RESOURCE_ATTRIBUTES=service.name=my-validator,deployment.environment=prod,plugin.version=3.1.0
```

In your backend, filter spans by `service.name` to isolate your plugin's activity.

## Sensitive-data control

Prompts and tool results can contain secrets (file contents, env vars, user inputs). Before enabling log-event export in production:

1. Review what the event schema contains — see upstream [Monitoring](https://docs.claude.com/en/monitoring-usage) for the full list
2. Use the CLI's attribute redaction settings to drop sensitive fields
3. For high-sensitivity workloads, export **metrics only** — they have no prompt/tool-result content

## Plugin-author guidance

1. **Document the envelope.** If your plugin ships as part of an SDK app, note which `service.name` resource attribute you tag with and which spans/metrics are emitted by your plugin's components.
2. **Don't add a second telemetry layer.** The CLI already instruments hooks, tool calls, model requests. Your plugin's own hooks show up as spans automatically — no extra code.
3. **Traces are in beta.** Don't build production dashboards exclusively around trace data yet. Metrics and log events are stable.

## See Also

- Upstream: [Observability](https://docs.claude.com/en/agent-sdk/observability), [Monitoring usage](https://docs.claude.com/en/monitoring-usage)
- [Track cost and usage](https://docs.claude.com/en/agent-sdk/cost-tracking) — read token/cost from the response stream without a backend
