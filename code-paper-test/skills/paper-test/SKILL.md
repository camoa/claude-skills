---
name: paper-test
description: Use when testing code, skills, commands, or configs through mental execution — trace logic line-by-line with concrete values to find bugs, logic errors, edge cases, contract violations, and AI hallucinations. Use when user says "paper test", "trace this", "find bugs", "check for edge cases", "audit this code", "verify AI code", "test this skill", "test this agent", "validate this implementation", "review this logic", "check dependencies", "check this config", "walk through this code", "step through this", "dry run", "sanity check", "red team this", "poke holes in this". MUST verify external calls — never assume methods exist. Use proactively before deploying changes or after AI generates code.
version: 0.10.0
model: sonnet
allowed-tools: Read, Glob, Grep, Bash
user-invocable: true
---

# Paper Test

Systematically test code by mentally executing it line-by-line with concrete values.

## Routing — Choose the Right Approach

| Target Size | Approach | Why |
|-------------|----------|-----|
| **< 50 lines** | Quick trace (workflow below) | Fast, inline, sufficient for small code |
| **50–300 lines** | Structured 3-phase | One agent, all 3 perspectives, sequential — thorough without coordination overhead |
| **300+ lines or security-critical** | `/code-paper:test-team` (3 agents) | Context pressure justifies splitting. Cross-challenge debate catches what one agent misses. |
| **Skill/command/agent files** | `/code-paper:test-team` | Different lenses genuinely find different things for instruction-based testing |

If the user asks for "paper test" without specifying, read the target files, count lines, and recommend the appropriate approach. For 50–300 lines, use Structured 3-Phase mode. Only recommend `/test-team` for 300+ lines, explicit "test team" requests, or security-critical code.

## Structured 3-Phase Mode (50–300 lines)

Read `references/structured-3-phase.md` for the full methodology. It runs Phase A (happy path), Phase B (edge cases, 6 categories), Phase C (adversarial, 5 categories), and Phase D (self-review) sequentially in one agent.

## Quick Trace Mode (< 50 lines)

For small code, skip the structured phases — just trace with concrete values following the workflow below.

## When to Use

- "Paper test this code" / "Trace this code" / "Test without running"
- "Find bugs in this code" / "Check for edge cases"
- "Validate this implementation" / "Review this logic"
- "Paper test this skill" / "Test this command" / "Validate this agent"
- "Check this config" / "Verify this YAML" / "Trace this prompt"
- Before deploying changes; debugging without a debugger
- Reviewing unfamiliar or AI-generated code
- Validating complex logic (loops, conditionals, recursion)

## Method

Follow code logic with concrete test cases to find:
1. **Potential issues** — bugs, wrong assumptions, edge cases
2. **Missing code** — what's needed but not written to achieve intent

NOT just reading — actually run the code in your head with real values.

## Effort-Adaptive Scenario Depth

The number of scenarios traced per phase scales with the active effort level so
the skill is honest about cost in CI and smoke runs. The current effort level is
`${CLAUDE_EFFORT}`. Apply this floor:

| Effort | Scenarios per phase | Posture |
|--------|---------------------|---------|
| `low` | 1 (happy path) + 1 error case | Fast smoke check — minimum honest coverage |
| `medium` | 2 per phase | Balanced — happy path, key edge cases, main error path |
| `high` / `xhigh` / `max` | 3+ per phase | Thorough — full edge and adversarial coverage |

Regardless of effort, ALWAYS trace at least one happy path and one error case,
and ALWAYS verify every external call (effort never lowers the verification
bar — it only scales scenario breadth). When `${CLAUDE_EFFORT}` is unset (model
without effort support), default to `medium`.

## Workflow

Trace the target with concrete values. The 8-step workflow:

1. **Define test scenarios** — concrete inputs; happy path first, then edge cases (count per "Effort-Adaptive Scenario Depth" above)
2. **Trace line by line** — record variable state after each line
3. **2b. Track data flow across boundaries** — type transformations, coercion, serialization, framework wrapping
4. **Follow every branch** — note which branch each conditional takes and why
5. **Track loop iterations** — trace each iteration with index and values
6. **Verify external dependencies** — for EVERY external call, Read/Grep the actual source; never assume
6b. **Verify behavioral contracts** — for every dependency confirmed to exist, enumerate caller assumptions about the return and diff against the declared contract. Procedures: `references/behavioral-verification.md` §B1 (code/library calls) and §B2 (plugin/MCP/hook/skill references). Closed-source fallback: apply taint stance; flag as behavioral gap if no validation wrapper exists. Chained-object rule: trace every property/method invoked on the return object, not just the return type.
7. **Verify code contracts** — extends/implements/uses/injects — all abstract methods, signatures, services
8. **Note output and flaws** — return value, side effects, state changes; then **untested path analysis** (branches never exercised)

Full step-by-step detail with templates for each step, the verification
procedures, the flaw catalog summary, the module testing strategy, and the
output template are in `references/workflow.md`.

## Critical: Never Assume

For every external method, service, interface, or config value the code touches,
**verify it** with the Read and Grep tools — do not guess. If the source is
unavailable (closed-source package), mark it explicitly as an UNVERIFIED RISK
rather than assuming it works. This is the single highest-value discipline of
paper testing, especially for AI-generated code. Procedures: `references/workflow.md`
(verification section), `references/dependency-verification.md`,
`references/contract-patterns.md`.

A method existing is not it returning what you assume. Existence verification is the first pass; behavioral verification is the second: locate the declared contract (type stub → OpenAPI → docs → docblock), enumerate every assumption the caller makes about the return, and diff. For closed-source targets with no contract: apply the taint stance — assume the return could be null, hostile, or malformed. See `references/behavioral-verification.md`.

## JSON Output Mode (`--json`)

For CI integration, aggregation, or programmatic consumption, invoke with `--json` to emit a stable, versioned JSON document instead of the markdown report.

- Available on `/paper-test` (quick and structured-3-phase modes) and `/code-paper:test-team` (lead synthesis).
- Schema is pinned at `schema_version: "1.0"` with an additive-only minor-version contract. CI should pin `^1\.`, not exact match.
- Severity values match the existing rubric exactly: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `INFO`.
- `findings` is always an array — `[]` when clean, never `null` or omitted.
- `status` is the overall gate verdict: `pass` / `warning` / `fail`. Use `pass` only when no MEDIUM-or-higher findings exist and the run completed fully.

**Use JSON mode for:** CI gates, dashboards, pipelines chaining into `jq` or monitoring. **Stay in markdown for:** interactive analysis and educational traces. Full schema, finding-object shape, team-report extensions, skill/config categories, optional `rubric_score` block, and CI gate patterns: see `references/json-output-schema.md`.

```
/paper-test --json src/Service/UserService.php
/code-paper:test-team --json src/Service/PaymentService.php
```

## Pairing with `skill-quality-reviewer` for Skill Testing

When paper-testing a skill, command, or agent file, run `plugin-creation-tools:skill-quality-reviewer` first (deterministic: stale SDK refs, dropped imperatives, frontmatter gaps) then paper-test for the semantic analysis (instruction fidelity, trigger coverage, context budget). See `references/skill-and-config-testing.md` §"Deterministic + Agentic pairing". In skill-mode, after verifying tool/file/skill references exist, verify each referenced capability PRODUCES what the calling step consumes — see `references/behavioral-verification.md` §B2.

## References

All detailed guides are in the `references/` directory:

- `references/workflow.md` — full 8-step workflow, verification detail, flaw catalog, module strategy, output template
- `references/core-method.md` — complete paper testing method with worked examples
- `references/structured-3-phase.md` — the 50–300 line single-agent 3-phase methodology
- `references/dependency-verification.md` — how to verify external calls
- `references/contract-patterns.md` — all code contract types
- `references/ai-code-auditing.md` — testing AI-generated code
- `references/fork-vs-fresh.md` — decision record: why `/test-team` spawns fresh-context (not forked) teammates
- `references/hybrid-testing.md` — module-level testing strategy
- `references/common-flaws.md` — catalog of frequent bugs
- `references/advanced-techniques.md` — progressive injects, red team testing, attack surface analysis, AAR format
- `references/severity-scoring.md` — consistent severity rubric for flaw prioritization
- `references/blind-ab-comparison.md` — comparing two implementations side by side
- `references/rubric-scoring.md` — structured grading for code quality assessment
- `references/skill-and-config-testing.md` — testing skills, commands, agents, and configs
- `references/json-output-schema.md` — stable JSON schema for `--json` mode (CI integration)
- `references/behavioral-verification.md` — B1 (code/library behavioral contracts) and B2 (plugin/MCP/hook/skill output contracts)
