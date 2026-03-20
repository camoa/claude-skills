---
description: Structured 3-phase paper test mode for 50-300 line files. Runs all 3 perspectives (happy path, edge cases, adversarial) sequentially in a single agent with self-review.
---

# Structured 3-Phase Mode (50–300 lines)

Run all 3 phases sequentially in a single agent. Each phase uses a different lens to force perspective diversity — the same diversity that 3 separate agents would provide, without the coordination overhead.

## Phase A: Happy Path (verify correct flow)

Design 2–3 scenarios with ideal inputs. For each:
1. Trace line-by-line recording variable state
2. At each conditional, note which branch and why
3. For loops, trace EACH iteration
4. Verify EVERY external call (Read the actual source — never assume)
5. Verify code contracts (extends, implements, injects)
6. Document expected outputs and side effects

## Phase B: Edge Cases (probe boundaries)

Design scenarios for EACH category:
1. Null/undefined — missing parameters
2. Empty — empty string, empty array, zero-length
3. Zero and negative — 0, -1, negative amounts
4. Boundary values — MAX_INT, very long strings, Unicode
5. Type mismatches — string where int expected
6. Missing keys — config values, array keys that don't exist

For each: trace line-by-line with the adversarial input, note the exact line where failure occurs.

## Phase C: Adversarial (security and reliability)

Design attack scenarios for EACH relevant category:
1. SQL injection / XSS / command injection
2. Path traversal
3. Malformed data — invalid JSON, oversized payloads
4. Race conditions — concurrent access, TOCTOU
5. Resource exhaustion — unbounded loops, memory

For each: trace the malicious input from entry point to dangerous operation. Check if framework protections actually apply to THIS code path.

## Phase D: Self-Review

After all 3 phases, review your own findings:
- Any false positives? Remove them.
- Any blind spots? All 3 perspectives covered, or did you unconsciously skip categories?
- Which findings are confirmed by multiple phases? (Higher confidence)
- Prioritize: Critical → High → Medium → Low

## Output Template

```
# Paper Test Report — [File/Function]

## Target
[File paths, line counts]

## Method
Structured 3-phase (single agent, all perspectives)

## Phase A: Happy Path
[Scenarios, traces, dependency/contract verification]

## Phase B: Edge Cases
| # | Category | Input | Line | Result | Severity |
[Table of findings]

## Phase C: Adversarial
| # | Category | Payload | Entry | Reaches Danger? | Blocked By |
[Table of findings]

## Prioritized Flaws
| # | Line | Flaw | Found In Phase | Severity | Fix |
[Merged, deduplicated, prioritized]

## Summary
- Happy path scenarios: [N]
- Edge case categories: [N]/6
- Adversarial categories: [N]/5
- Total flaws: [N] (Critical: [N], High: [N], Medium: [N])
```
