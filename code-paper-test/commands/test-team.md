---
description: Paper test code or skills with competing agent team (Happy Path + Edge Case + Red Team). Use when user says "test team", "3 perspectives", "competing testers", "thorough paper test", "security review", "deep code analysis", "test this skill with team". Best for large code (300+ lines), security-critical paths, or skill/command testing where perspective diversity matters most. For 50-300 line files, the single-agent structured 3-phase mode in /paper-test is more cost-effective. Each tester runs in isolated worktree.
allowed-tools: Read, Write, Glob, Grep, WebSearch
argument-hint: "[--json] <file-path> [file-path...]"
---

# Test Team

Paper test code from 3 competing perspectives using an agent team. A Happy Path Validator traces correct flow, an Edge Case Hunter probes boundaries, and a Red Team Attacker tries adversarial inputs. They debate findings and produce a prioritized flaw report.

## Usage

```
/code-paper-test:test-team [--json] <file-path> [file-path...]
```

Pass `--json` to emit a CI-consumable JSON report alongside the markdown report. Schema: `skills/paper-test/references/json-output-schema.md` (`schema_version: "1.1"`; additive minor — CI should pin `^1\.`).

## What This Does

Spawns a team that paper-tests the specified code files from competing perspectives: three testers (Happy Path, Edge Case, Red Team) trace the code with different input strategies and cross-challenge findings, then a fourth **Synthesizer** teammate compiles a prioritized flaw report next to the target code (keeping the heavy reads off the lead).

> **Aggregating across parallel teammates:** Claude Code 2.1.118+ ships a `PostToolBatch` hook that fires once after a batch of parallel tool calls resolves (Hooks Reference). For users who want to aggregate per-teammate JSON outputs into a single batch summary (e.g., posting one consolidated finding count to Slack instead of three), `PostToolBatch` is the right primitive. This plugin does not ship the hook — copy it into your project's `.claude/hooks.json` if needed. Reference, don't implement.

## Instructions

When this command is invoked with `$ARGUMENTS`:

### Step 1 — Parse Arguments and Check Target Exists

Parse `$ARGUMENTS`:

- If the first token is `--json`, set `JSON_MODE=true` and consume it. Remaining tokens are file paths.
- Otherwise `JSON_MODE=false`. All tokens are file paths.

Verify each file exists using the Read tool.

If no arguments provided:
> What code should the team test? Provide one or more file paths:
> ```
> /code-paper-test:test-team src/Service/PaymentService.php
> ```

If a file doesn't exist:
> File not found: `{path}`. Check the path and try again.

Stop here if no valid targets.

Determine the **target directory** for output, resolved to an **absolute** path:
- Single file → same directory as the file
- Multiple files in same directory → that directory
- Multiple files across directories → their common parent directory

**`{target_dir}` MUST be absolute** (resolve it — e.g. `realpath`/`pwd` — before substituting it into any spawn prompt). Every teammate runs in its own `Isolation: worktree` checkout, so a *relative* `{target_dir}` would resolve INSIDE each teammate's worktree: the per-teammate analysis files would then be invisible across teammates (breaking the Task 4 cross-challenge, where each tester reviews the others' `*-analysis.md`) and invisible to the Synthesizer (which reads all three). An absolute path points every teammate at the same real directory.

### Step 2 — Check Prerequisites

Verify agent teams are available by attempting to create a team. If creation fails:

> Agent teams are not available in this environment.
>
> **Fallback:** Use the standard paper test skill instead — ask Claude to "paper test {file}".

Stop here if not available.

### Step 3 — Assess Scope

Read target files and count total lines.

**Routing by size:**

If fewer than 50 lines total:
> Target is {N} lines. For small code, use `/paper-test` (single-agent quick trace) instead.
> The 3-agent team adds overhead that isn't justified for small targets.

Stop here and suggest `/paper-test` unless user insists.

If 50–300 lines total and NOT skill/command files:
> Target is {N} lines. The single-agent structured 3-phase mode (`/paper-test`) covers all 3 perspectives (happy path, edge cases, adversarial) at 1/3 the cost of the agent team.
> Use the team anyway? (Best for security-critical code or when you want the cross-challenge debate.)

Continue only if user confirms. Otherwise redirect to `/paper-test`.

If 300+ lines total:
> Target is {N} lines. The 3-agent team is recommended — context pressure benefits from splitting, and cross-challenge catches what one agent misses.

Continue.

**Skill/Config Detection:**

If target files have YAML frontmatter (`---` delimiters) and contain step-by-step instructions rather than code:
> Target appears to be a skill/command/agent definition, not code.
> Switching to instruction tracing mode — the 3-agent team adds most value here because happy path, edge case, and red team perspectives genuinely find different things for instruction-based testing.
> See `references/skill-and-config-testing.md` for methodology.

Continue with skill-aware spawn prompts below.

### Step 4 — Create Shared Task List

Create a team and these tasks:

| # | Task | Assign to | Depends on |
|---|------|-----------|------------|
| 1 | Trace happy path — verify correct flow with ideal inputs | Happy Path Validator | — |
| 2 | Probe edge cases — boundary values, nulls, empty, large inputs | Edge Case Hunter | — |
| 3 | Attack with adversarial inputs — injection, malformed data, race conditions | Red Team Attacker | — |
| 4 | Cross-challenge — debate flaw severity, dispute false findings, identify blind spots | All three | 1, 2, 3 |
| 5 | Spawn the Synthesizer teammate, then report the saved report path | Lead | 4 |
| 5b | Synthesize prioritized flaw report from the three analyses | Synthesizer | 4, 5 |

**Quality Gate:** Each tester must complete ALL assigned categories before marking their task done. If a tester skips categories (e.g., Edge Case Hunter tests 3 of 6 categories), the Synthesizer should flag incomplete analysis in the final report and note which categories were untested.

### Step 5 — Spawn Teammates

**Compute per-teammate effort first.** The active effort level is `${CLAUDE_EFFORT}`.
Each teammate runs at `max(caller effort, role floor)` — caller effort is a
**floor-raiser**, never a floor-lowerer:

| Teammate | Role floor | Effective effort |
|----------|-----------|------------------|
| Happy Path Validator | `medium` | `max(${CLAUDE_EFFORT}, medium)` |
| Edge Case Hunter | `high` | `max(${CLAUDE_EFFORT}, high)` |
| Red Team Attacker | `high` | `max(${CLAUDE_EFFORT}, high)` |

Effort ordering: `low` < `medium` < `high` < `xhigh` < `max`. So a caller at
`low` or `medium` still gets Edge Case and Red Team at their `high` floor (the
adversarial lenses are never cheapened), while a caller at `xhigh`/`max` bumps
the whole team up. When `${CLAUDE_EFFORT}` is unset (model without effort
support), use each role's floor as-is. Substitute the resulting level into the
`**Effort:**` line of each spawn block below.

Spawn the **3 tester teammates** (the Synthesizer is spawned later, in Step 6) using the prompt templates below. Substitute `{target_dir}` with the directory computed in Step 1, `{list each file path}` with the validated targets, and interpolate `JSON_MODE={true|false}` near the top of each spawn prompt (so the teammate knows whether to emit the parallel `.json` report). After spawning:

1. Tell the user: "Team spawned. Teammates are working — the Synthesizer will compile the report when they finish."
2. If running inside tmux, teammates appear in split panes (visible output). Otherwise they run in-process (background).
3. Do NOT perform testing yourself — wait for all teammates to complete before proceeding.

### Step 6 — Synthesize (via the Synthesizer teammate)

When tasks 1–4 are complete, **spawn the Synthesizer teammate (Task 5b)** using the Teammate 4 block below — do NOT read the three analysis files into the lead's own context. The Synthesizer reads all three analysis files in its own fresh context and writes the final report, which keeps the heavy reads off the lead (the v0.11.0 context-economy fix). Substitute `{target_dir}` and interpolate `JSON_MODE={true|false}` into the spawn prompt exactly as for the testers.

The Synthesizer writes `{target_dir}/paper-test-team-report.md` (and, when `JSON_MODE=true`, `{target_dir}/paper-test-team-report.json`) using the Output Format below. The JSON aggregation honors the invariants: `findings` is always an array, severity values are uppercase (`CRITICAL` etc.), `status` is `fail` if any CRITICAL or HIGH finding exists, `warning` if only MEDIUM/LOW findings, `pass` only if no MEDIUM-or-higher findings. Each aggregated finding includes `found_by` (union of teammate roles whose per-teammate JSON reported the same file + line span + category) and `disputed` (boolean — `true` iff the cross-challenge markdown report lists this finding in its "Disputed Findings" table). See the schema's "Team-specific finding fields" section for the precise field contract.

When the Synthesizer completes, tell the user: "Paper test team complete. Report saved to `{target_dir}/paper-test-team-report.md`" (append "and `paper-test-team-report.json`" when `JSON_MODE=true`).

---

## Spawn Prompts

> **Teammate model:** the `**Model:** sonnet` lines below are explicit per-spawn
> defaults. A user who sets `teammateDefaultModel` in `settings.json` can drop
> the need to think about per-spawn models — see the plugin README "Configuration".
> The explicit lines are kept so the command works without that setting.

### Teammate 1: Happy Path Validator

**Model:** sonnet
**MaxTurns:** 15
**Isolation:** worktree
**Effort:** max(${CLAUDE_EFFORT}, medium)

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
5b. **Behavioral verification** — for each dependency confirmed to exist in step 5, run the B1 procedure:
   - Enumerate every assumption the CALLER makes about the return: fields accessed, assumed type (required vs optional), null-checked?, error modes handled, side effects relied on.
   - Locate the declared contract in priority order: type stub (.d.ts / .pyi / typeshed) → OpenAPI `responses` for the endpoint+status → official method docs → `@returns` / docblock → changelog as observed-behavior proxy.
   - Extract declared outputs (required vs optional, nullable, exact types, documented errors).
   - DIFF caller assumption vs declared: field declared? required not optional? type matches? nullable but unchecked? error mode handled? Each miss = flagged behavioral gap.
   - **Chained-object rule:** when a call returns an object, trace EVERY property/method the caller invokes on it and verify each against the contract. Do not stop at the first return type.
   - **Closed-source fallback:** mark "postcondition unknown — EXISTENCE VERIFIED / BEHAVIOR UNVERIFIED"; apply taint stance (assume return could be null/hostile/malformed — does code fail safely?); require a validation wrapper; flag as behavioral gap if none exists.
6. For code contracts (extends, implements, uses, injects):
   - Read parent/base classes and interfaces
   - Verify all abstract methods implemented, signatures match
7. Document expected outputs and side effects

WRITE your analysis to:
  {target_dir}/happy-path-analysis.md

If JSON_MODE=true (the lead will pass this in the spawn prompt), ALSO write a parallel structured report to:
  {target_dir}/happy-path-analysis.json

JSON shape — match `skills/paper-test/references/json-output-schema.md` exactly:
- `schema_version: "1.1"`, `tool: "test-team"`, `mode: "test-team"`, `target_type` per target type, `target_files`, `timestamp` (ISO 8601 UTC)
- `summary` with counts by severity (CRITICAL/HIGH/MEDIUM/LOW/INFO — uppercase), `total_findings`, `scenarios_traced`, `dependencies_verified`, `contracts_verified`
- `findings` is always an array; each finding has `severity`, `category`, `file`, `line_start`, `line_end`, `title`, `description`, `fix_suggestion`, `scoring_factors {reach, impact, reversibility, exploitability}` (1-3 each; omit only for INFO), and `found_by: ["happy_path"]`
- Do NOT include `disputed`, `team`, or cross-challenge data — the Synthesizer aggregates those later

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
| # | External Call | File | Exists? | Behavior verified? | Contract source | Issue |
|---|-------------|------|---------|-------------------|----------------|-------|

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

SKILL MODE:
If target files are skills, commands, or agents (.md with frontmatter):
- Instead of line-by-line code tracing, trace step-by-step INSTRUCTIONS
- Design 2-3 scenarios with different user messages
- Trace what Claude would do at each step
- Verify all tool/file/skill references exist
- Verify each referenced capability PRODUCES what the calling step consumes — run the B2 procedure:
  Enumerate what the calling step assumes the capability produces (fields, types, success handling). Locate the capability's declared output: MCP tool output schema, SKILL.md declared outputs, hook event payload schema. DIFF assumptions vs declaration. False-confidence check: does the gate verify production or only existence? If existence only, flag behavioral gap.
- Check frontmatter completeness and consistency
- Test trigger phrases (will Claude invoke this?)

WHEN DONE:
Message the other teammates: "Happy path analysis complete. Review happy-path-analysis.md"
Mark your task as completed.

To signal completion to the lead, either:
- Exit with code 2 to trigger a feedback loop (the lead reviews and may ask for more)
- Or output JSON: {"continue": false} to hard-stop your turn immediately
```

### Teammate 2: Edge Case Hunter

**Model:** sonnet
**MaxTurns:** 15
**Isolation:** worktree
**Effort:** max(${CLAUDE_EFFORT}, high)

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

If JSON_MODE=true, ALSO write the structured report to:
  {target_dir}/edge-case-analysis.json

Match `skills/paper-test/references/json-output-schema.md`. Use `found_by: ["edge_case"]` on each finding. `summary` should also include `categories_tested` (int 0-6). Omit `disputed`/`team`/cross-challenge.

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

SKILL MODE:
If target files are skills, commands, or agents (.md with frontmatter):
- Test with ambiguous user messages that might or might not trigger the skill
- Test with missing $ARGUMENTS, empty arguments, wrong argument types
- Test with non-existent file paths referenced in instructions
- Test what happens when a tool call returns empty results mid-workflow
- Check context budget — will the skill fit when context is 80% full?
- Check instruction fidelity — will Claude follow step 7 after a long step 3?

WHEN DONE:
Message the other teammates: "Edge case analysis complete. Review edge-case-analysis.md"
Mark your task as completed.

To signal completion to the lead, either:
- Exit with code 2 to trigger a feedback loop (the lead reviews and may ask for more)
- Or output JSON: {"continue": false} to hard-stop your turn immediately
```

### Teammate 3: Red Team Attacker

**Model:** sonnet
**MaxTurns:** 15
**Isolation:** worktree
**Effort:** max(${CLAUDE_EFFORT}, high)
**Note:** For complex security analysis, consider using `model: opus` for deeper reasoning.

```
You are the Red Team Attacker for a paper testing team.

TARGET FILES:
{list each file path}

YOUR MISSION:
Try adversarial inputs and find security/reliability holes. Your lens: "How would an attacker exploit this code?"

Note: The security-guidance plugin performs in-session edit review of Claude's own code changes in real time. Your role is different: you analyze the TARGET code for adversarial vulnerabilities at test time, before any session edits occur. These are complementary, not overlapping. Do not defer to security-guidance for target-code attack analysis — that is your job.

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

If JSON_MODE=true, ALSO write the structured report to:
  {target_dir}/red-team-analysis.json

Match `skills/paper-test/references/json-output-schema.md`. Use `found_by: ["red_team"]` on each finding. `summary` should also include `attack_categories_tested` (int 0-7), `exploitable` (int), `blocked` (int). Omit `disputed`/`team`/cross-challenge.

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

SKILL MODE:
If target files are skills, commands, or agents (.md with frontmatter):
- Test if skill can be tricked into running unintended tools
- Test if instructions leak sensitive info in error messages
- Test if agent team coordination can be disrupted (conflicting outputs, race conditions)
- Test if allowed-tools are too permissive (does the skill need Write access?)
- Test if description is so broad it steals triggers from other skills
- Check for prompt injection vectors in user-provided arguments

WHEN DONE:
Message the other teammates: "Red team analysis complete. Review red-team-analysis.md"
Mark your task as completed.

To signal completion to the lead, either:
- Exit with code 2 to trigger a feedback loop (the lead reviews and may ask for more)
- Or output JSON: {"continue": false} to hard-stop your turn immediately
```

### Teammate 4: Synthesizer

**Model:** inherit
**MaxTurns:** 10
**Isolation:** worktree

```
You are the Synthesizer for a paper testing team. The three analysis phases are complete.

YOUR MISSION:
Read the three analysis files and produce the final prioritized flaw report. You do NOT
re-test the code — you aggregate what the three testers already found.

FILES TO READ:
  {target_dir}/happy-path-analysis.md
  {target_dir}/edge-case-analysis.md
  {target_dir}/red-team-analysis.md
  [If JSON_MODE=true, also read happy-path-analysis.json, edge-case-analysis.json, red-team-analysis.json]

WRITE the final report to:
  {target_dir}/paper-test-team-report.md
  [If JSON_MODE=true, also write {target_dir}/paper-test-team-report.json per the team
   aggregation schema in skills/paper-test/references/json-output-schema.md]

Aggregate findings, de-duplicate across the three perspectives, record cross-challenge
outcomes, and split the Existence vs Behavioral Contract tables. Write the markdown report
in EXACTLY this format (this is the canonical Output Format — keep it in sync with the
command's "## Output Format" section):

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

## Existence Verification
| # | External Call | Exists? | Issue |
|---|-------------|---------|-------|

## Behavioral Contract Verification
| # | External Call | Behavior verified? | Contract source | Gap |
|---|-------------|-------------------|----------------|-----|

## Contract Verification
| # | Relationship | Verified? | Issue |
|---|-------------|-----------|-------|

## Blind Spots (Unanimous Agreements)
{Areas where all 3 agreed the code is fine — flag for human review}

## Recommended Test Cases
{Concrete test cases to write based on flaws found}
| # | Test | Input | Expected | Covers Flaw |
|---|------|-------|----------|-------------|

For the JSON report (JSON_MODE=true) honor the schema invariants in skills/paper-test/references/json-output-schema.md: `findings` is always an array, severity values are uppercase, `status` is `fail` if any CRITICAL/HIGH finding exists, `warning` for only MEDIUM/LOW, `pass` only when no MEDIUM-or-higher finding exists; set `found_by` (union of roles that reported the same file+line span+category) and `disputed` per the cross-challenge.

WHEN DONE:
Output: {"continue": false}
```

---

## Output Format

The Synthesizer (Teammate 4) synthesizes into `{target_dir}/paper-test-team-report.md`:

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

## Existence Verification
| # | External Call | Exists? | Issue |
|---|-------------|---------|-------|

## Behavioral Contract Verification
| # | External Call | Behavior verified? | Contract source | Gap |
|---|-------------|-------------------|----------------|-----|

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
- Skill/config testing: ask Claude to "paper test {skill}" (traces instructions, not code)
