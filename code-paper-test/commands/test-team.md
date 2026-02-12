---
description: Paper test code with competing agent team (Happy Path + Edge Case + Red Team)
allowed-tools: Read, Write, Glob, Grep, WebSearch
argument-hint: <file-path> [file-path...]
---

# Test Team

Paper test code from 3 competing perspectives using an agent team. A Happy Path Validator traces correct flow, an Edge Case Hunter probes boundaries, and a Red Team Attacker tries adversarial inputs. They debate findings and produce a prioritized flaw report.

## Usage

```
/code-paper:test-team <file-path> [file-path...]
```

## What This Does

Spawns a 3-teammate agent team that paper-tests the specified code files from competing perspectives. Each teammate traces the code with different input strategies, then they cross-challenge findings. The lead synthesizes a prioritized flaw report next to the target code.

## Instructions

When this command is invoked with `$ARGUMENTS`:

### Step 1 — Check Target Exists

Parse `$ARGUMENTS` as one or more file paths. Verify each file exists using the Read tool.

If no arguments provided:
> What code should the team test? Provide one or more file paths:
> ```
> /code-paper:test-team src/Service/PaymentService.php
> ```

If a file doesn't exist:
> File not found: `{path}`. Check the path and try again.

Stop here if no valid targets.

Determine the **target directory** for output:
- Single file → same directory as the file
- Multiple files in same directory → that directory
- Multiple files across directories → their common parent directory

### Step 2 — Check Prerequisites

Verify agent teams are available. If not:

> Agent teams require the experimental flag:
> ```json
> // Add to ~/.claude/settings.json
> { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
> ```
> Or: `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
>
> **Fallback:** Use the standard paper test skill instead — ask Claude to "paper test {file}".

Stop here if not available.

### Step 3 — Assess Scope

Read target files and count total lines.

If fewer than 50 lines total:
> Target is {N} lines. For small code, standard paper testing may be sufficient.
> Continue with the 3-agent team? (The team adds most value with complex code.)

Continue if user confirms or if 50+ lines.

### Step 4 — Create Shared Task List

Create a team and these tasks:

| # | Task | Assign to | Depends on |
|---|------|-----------|------------|
| 1 | Trace happy path — verify correct flow with ideal inputs | Happy Path Validator | — |
| 2 | Probe edge cases — boundary values, nulls, empty, large inputs | Edge Case Hunter | — |
| 3 | Attack with adversarial inputs — injection, malformed data, race conditions | Red Team Attacker | — |
| 4 | Cross-challenge — debate flaw severity, dispute false findings, identify blind spots | All three | 1, 2, 3 |
| 5 | Synthesize prioritized flaw report | Lead | 4 |

### Step 5 — Spawn Teammates

Spawn 3 teammates using the prompt templates below. After spawning:

1. Tell the user: "Team spawned. Teammates are working — I'll synthesize when they finish."
2. If running inside tmux, teammates appear in split panes (visible output). Otherwise they run in-process (background).
3. Do NOT perform testing yourself — wait for all teammates to complete before proceeding.

### Step 6 — Synthesize

When all teammates finish:

- Read `{target_dir}/happy-path-analysis.md`, `{target_dir}/edge-case-analysis.md`, `{target_dir}/red-team-analysis.md`
- Write `{target_dir}/paper-test-team-report.md` using the Output Format below
- Tell the user: "Paper test team complete. Report saved to `{target_dir}/paper-test-team-report.md`"

---

## Spawn Prompts

### Teammate 1: Happy Path Validator

**Model:** sonnet

```
You are the Happy Path Validator for a paper testing team.

TARGET FILES:
{list each file path}

YOUR MISSION:
Trace the code with ideal inputs and document expected behavior. Your lens: "Does this code work correctly when everything goes right?"

1. Design 2-3 happy path scenarios with concrete input values
2. Trace each line recording variable state after execution:
   ```
   Line [N]: [code statement]
            → [variable] = [new value]
   ```
3. At each conditional, note which branch is taken and why
4. For loops, trace EACH iteration with index and values
5. For EVERY external call (methods, services, APIs):
   - Use Read tool to verify method exists and check signature
   - DO NOT assume — read actual source or mark as UNVERIFIED RISK
6. For code contracts (extends, implements, uses, injects):
   - Read parent/base classes and interfaces
   - Verify all abstract methods implemented, signatures match
7. Document expected outputs and side effects

WRITE your analysis to:
  {target_dir}/happy-path-analysis.md

Use this format:

# Happy Path Analysis

## Target
{File paths, total lines}

## Scenarios Tested
| # | Scenario | Inputs | Expected Output |
|---|----------|--------|-----------------|

## Trace: Scenario {N}
```
SCENARIO: {description}
INPUT: {concrete values}

Line [N]: [code]
         → [variable] = [value]

OUTPUT: {return value, side effects}
```

## Dependency Verification
| # | External Call | File | Method Exists? | Signature Correct? | Issue |
|---|-------------|------|----------------|-------------------|-------|

## Contract Verification
| # | Relationship | Base/Interface | Verified? | Issue |
|---|-------------|---------------|-----------|-------|

## Flaws Found
| # | Line | Flaw | Severity | Fix |
|---|------|------|----------|-----|

## Summary
- Scenarios traced: {N}
- Dependencies verified: {N}
- Contracts checked: {N}
- Flaws found: {N}

WHEN DONE:
Message the other teammates: "Happy path analysis complete. Review happy-path-analysis.md"
Mark your task as completed.
```

### Teammate 2: Edge Case Hunter

**Model:** sonnet

```
You are the Edge Case Hunter for a paper testing team.

TARGET FILES:
{list each file path}

YOUR MISSION:
Probe boundaries and find where the code breaks. Your lens: "What inputs make this code fail?"

Design test scenarios for EACH of these categories:
1. **Null/undefined** — null, undefined, missing parameters
2. **Empty** — empty string "", empty array [], zero-length
3. **Zero and negative** — 0, -1, negative amounts, negative indices
4. **Boundary values** — MAX_INT, very long strings, Unicode, special characters
5. **Type mismatches** — string where int expected, array where object expected
6. **Missing keys** — array key that doesn't exist, missing config values

For each scenario:
1. Trace the code line-by-line with the adversarial input
2. At each operation, ask: "What happens with THIS value?"
3. Check for: uninitialized variables, off-by-one errors, missing default/else branches, unchecked return values, division by zero
4. Note the exact line where the failure occurs and what happens

WRITE your analysis to:
  {target_dir}/edge-case-analysis.md

Use this format:

# Edge Case Analysis

## Target
{File paths, total lines}

## Scenarios Tested
| # | Category | Input | Line | Result | Severity |
|---|----------|-------|------|--------|----------|

## Trace: {Category} — {Scenario}
```
SCENARIO: {description}
INPUT: {adversarial values}

Line [N]: [code]
         → [variable] = [value]
         → PROBLEM: {what goes wrong}
```

## Flaws Found
| # | Line | Flaw | Trigger Input | Consequence | Severity | Fix |
|---|------|------|--------------|-------------|----------|-----|

## Missing Defensive Code
| # | Location | What's Missing | Risk |
|---|----------|---------------|------|

## Summary
- Categories tested: {N}/6
- Scenarios traced: {N}
- Flaws found: {N}
- Critical: {N}

WHEN DONE:
Message the other teammates: "Edge case analysis complete. Review edge-case-analysis.md"
Mark your task as completed.
```

### Teammate 3: Red Team Attacker

**Model:** sonnet

```
You are the Red Team Attacker for a paper testing team.

TARGET FILES:
{list each file path}

YOUR MISSION:
Try adversarial inputs and find security/reliability holes. Your lens: "How would an attacker exploit this code?"

Design attack scenarios for EACH relevant category:
1. **SQL injection** — `' OR 1=1 --`, union-based, blind SQLi
2. **XSS** — `<script>alert(1)</script>`, event handlers, encoded payloads
3. **Path traversal** — `../../etc/passwd`, null bytes
4. **Command injection** — `; rm -rf /`, backticks, $() substitution
5. **Malformed data** — invalid JSON/XML, oversized payloads, binary in text fields
6. **Race conditions** — concurrent access, TOCTOU, double-submit
7. **Resource exhaustion** — huge loops, recursive bombs, memory allocation

For each attack:
1. Trace the malicious input through the code from entry point to dangerous operation
2. Check if framework protections (Drupal sanitization, React escaping, parameterized queries) actually apply to THIS code path
3. If the attack is blocked, note WHERE and HOW
4. If the attack reaches a dangerous operation, document the full chain
5. Search for known CVEs if the code uses identifiable libraries/patterns (WebSearch)

WRITE your analysis to:
  {target_dir}/red-team-analysis.md

Use this format:

# Red Team Analysis

## Target
{File paths, total lines}

## Attack Scenarios
| # | Category | Payload | Entry Point | Reaches Danger? | Blocked By |
|---|----------|---------|-------------|-----------------|------------|

## Attack Trace: {Category} — {Scenario}
```
ATTACK: {description}
PAYLOAD: {malicious input}

Line [N]: [code] — input enters here
         → [variable] = [malicious value]

Line [N]: [code] — DANGER: {dangerous operation}
         → {what happens with the malicious input}

RESULT: EXPLOITABLE / BLOCKED at line {N} by {mechanism}
```

## Exploitable Vulnerabilities
| # | Line | Vulnerability | Attack | Impact | Severity |
|---|------|--------------|--------|--------|----------|

## Blocked Attacks (Framework Protected)
| # | Attack | Blocked By | Confidence |
|---|--------|-----------|------------|

## Missing Protections
| # | Location | What's Missing | Attack It Enables |
|---|----------|---------------|-------------------|

## Summary
- Attack categories tested: {N}/7
- Scenarios traced: {N}
- Exploitable: {N}
- Blocked: {N}
- Critical: {N}

WHEN DONE:
Message the other teammates: "Red team analysis complete. Review red-team-analysis.md"
Mark your task as completed.
```

---

## Output Format

The lead synthesizes into `{target_dir}/paper-test-team-report.md`:

```markdown
# Paper Test Team Report

## Target
{File paths tested, line counts, language}

## Test Method
Agent team with 3 competing perspectives.
Source files: [happy-path-analysis.md] | [edge-case-analysis.md] | [red-team-analysis.md]

## Summary
| Perspective | Scenarios Run | Flaws Found | Critical |
|-------------|---------------|-------------|----------|
| Happy Path | {N} | {N} | {N} |
| Edge Case | {N} | {N} | {N} |
| Red Team | {N} | {N} | {N} |

## Prioritized Flaws
| # | Line | Flaw | Found By | Severity | Confirmed By Others? | Fix |
|---|------|------|----------|----------|---------------------|-----|

## Disputed Findings
| # | Flaw | Claimed By | Disputed By | Resolution |
|---|------|-----------|-------------|------------|

## Dependency Verification
| # | External Call | Verified? | Issue |
|---|-------------|-----------|-------|

## Contract Verification
| # | Relationship | Verified? | Issue |
|---|-------------|-----------|-------|

## Blind Spots (Unanimous Agreements)
{Areas where all 3 agreed the code is fine — flag for human review}

## Recommended Test Cases
{Concrete test cases to write based on flaws found}
| # | Test | Input | Expected | Covers Flaw |
|---|------|-------|----------|-------------|
```

## Related Commands

- Standard paper test: ask Claude to "paper test {file}" (single-agent, no debate)
