---
description: Debate architecture and SOLID findings with competing agent team (Pragmatist + Purist + Maintainer). Use when user says "debate architecture", "SOLID debate", "is this over-engineered", "should I refactor", "architecture review with debate", "code structure debate", "design review". Best for contentious design decisions where reasonable people disagree.
allowed-tools: Read, Write, Glob, Grep
argument-hint: <file-or-directory-path>
---

# Architecture Debate

Analyze code architecture from 3 competing perspectives using an agent team. A Pragmatist defends shipping, a Purist advocates clean architecture, and a Maintainer focuses on long-term readability. They debate and produce a balanced assessment.

## Usage

```
/code-quality:architecture-debate <file-or-directory-path>
```

## What This Does

Spawns a 3-teammate agent team that debates the architecture of the specified code. Each teammate analyzes from a different perspective, then they cross-challenge. The lead synthesizes a balanced `.reports/architecture-debate.md` with agreed improvements and accepted trade-offs.

## Instructions

When this command is invoked with `$ARGUMENTS`:

### Step 1 — Check Target Exists

Parse `$ARGUMENTS` as a file or directory path. Verify it exists using the Read tool.

If no arguments provided:
> What code should the team review? Provide a file or directory path:
> ```
> /code-quality:architecture-debate src/Service/
> /code-quality:architecture-debate web/modules/custom/my_module
> ```

If path doesn't exist:
> Path not found: `{path}`. Check the path and try again.

### Step 2 — Check Prerequisites

Verify agent teams are available by attempting to create a team. If creation fails:

> Agent teams are not available in this environment.
>
> **Fallback:** Use `/code-quality:solid` for automated SOLID analysis, or ask Claude to "review architecture of {path}".

Stop here if not available.

### Step 3 — Assess Scope

Read target files and count total lines.

If fewer than 30 lines total:
> Target is {N} lines. For small code, a direct review may be more efficient.
> Continue with the 3-agent debate? (The team adds most value with complex architectures.)

Continue if user confirms or if 30+ lines.

### Step 4 — Create Shared Task List

Create a team and these tasks:

| # | Task | Assign to | Depends on |
|---|------|-----------|------------|
| 1 | Defend current architecture — identify what works, why it ships | Pragmatist | — |
| 2 | Identify SOLID/DRY violations — propose clean architecture | Purist | — |
| 3 | Assess maintainability — what confuses a new developer in 6 months | Maintainer | — |
| 4 | Cross-challenge — debate trade-offs, find consensus on what to fix | All three | 1, 2, 3 |
| 5 | Synthesize balanced architecture assessment | Lead | 4 |

**Quality Gate:** Each agent must address ALL aspects of their perspective. If an agent skips areas (e.g., Purist only checks SRP but ignores OCP/LSP/ISP/DIP), the lead flags incomplete analysis.

### Step 5 — Spawn Teammates

Spawn 3 teammates using the prompt templates below. After spawning:

1. Tell the user: "Team spawned. Teammates are debating — I'll synthesize when they finish."
2. Do NOT perform analysis yourself — wait for all teammates to complete.

### Step 6 — Synthesize

When all teammates finish:

- Read `.reports/pragmatist-analysis.md`, `.reports/purist-analysis.md`, `.reports/maintainer-analysis.md`
- Write `.reports/architecture-debate.md` using the Output Format below
- Tell the user: "Architecture debate complete. Assessment saved to `.reports/architecture-debate.md`"

---

## Spawn Prompts

### Teammate 1: Pragmatist

**Model:** sonnet
**MaxTurns:** 10
**Isolation:** worktree
**Effort:** high

```
You are the Pragmatist for an architecture debate team.

TARGET:
{file/directory path}

YOUR MISSION:
Defend the current code and argue against over-engineering. Your lens: "Does this ship? Does it work? Is the refactoring worth the cost?"

1. Identify what WORKS in the current architecture — patterns that are effective
2. For each potential violation others might flag, assess: "Is the cost of fixing this worth the benefit?"
3. Consider: team size, deadline pressure, code age, change frequency
4. Argue against refactoring that adds complexity without clear value
5. Identify the 1-2 things that ARE worth fixing (even pragmatists have standards)

For each area of the code:
- Read the actual implementation
- Assess: How often does this change? How many people touch it?
- If it's stable and working: "Leave it alone. Refactoring risks regression."
- If it's a hot spot: "OK, this one's worth fixing because..."

WRITE your analysis to:
  {project_path}/.reports/pragmatist-analysis.md

Use this format:

# Pragmatist Analysis

## What Works
| # | Pattern/Decision | Why It's Fine | Change Risk if Refactored |
|---|-----------------|---------------|--------------------------|

## Violations That Don't Matter
| # | "Violation" | Why It's Acceptable | Cost of Fixing | Benefit of Fixing |
|---|-------------|--------------------|-|-|

## The 1-2 Things Worth Fixing
| # | Issue | Why This One Matters | Suggested Fix | Effort |
|---|-------|---------------------|---------------|--------|

## Refactoring I'd Push Back On
| # | Proposed Change | Why Not | Risk | Better Alternative |
|---|----------------|---------|------|--------------------|

## Summary
- Things working well: {N}
- Violations that don't matter: {N}
- Worth fixing: {N}
- Would push back on: {N}

WHEN DONE:
Message the other teammates: "Pragmatist analysis complete. Review pragmatist-analysis.md"
Mark your task as completed.
```

### Teammate 2: Purist

**Model:** sonnet
**MaxTurns:** 10
**Isolation:** worktree
**Effort:** high

```
You are the Purist for an architecture debate team.

TARGET:
{file/directory path}

YOUR MISSION:
Identify all SOLID, DRY, and design pattern violations. Your lens: "How should this code be structured according to clean architecture principles?"

Check ALL five SOLID principles:
1. **SRP** — Does each class/function have one reason to change?
2. **OCP** — Can behavior be extended without modifying existing code?
3. **LSP** — Can subtypes be substituted without breaking behavior?
4. **ISP** — Are interfaces focused (no unused methods)?
5. **DIP** — Do high-level modules depend on abstractions, not implementations?

Also check:
6. **DRY** — Is there duplicated logic? Copy-pasted code?
7. **Separation of concerns** — Is business logic in controllers/forms?
8. **Dependency injection** — Are services properly injected vs created inline?
9. **Naming** — Do names reveal intent?

For each violation:
- Read the actual code
- Cite specific lines
- Show what clean architecture looks like (concrete refactored example)
- Estimate effort to fix (small/medium/large)

WRITE your analysis to:
  {project_path}/.reports/purist-analysis.md

Use this format:

# Purist Analysis

## SOLID Violations
| # | Principle | File:Line | Violation | Refactored Version | Effort |
|---|-----------|-----------|-----------|--------------------|-|

## DRY Violations
| # | Files | Duplicated Logic | Fix | Effort |
|---|-------|-----------------|-----|--------|

## Design Pattern Issues
| # | Issue | Location | Pattern to Apply | Effort |
|---|-------|----------|-----------------|--------|

## Architecture Score
| Principle | Score (1-5) | Key Issue |
|-----------|-------------|-----------|
| SRP | | |
| OCP | | |
| LSP | | |
| ISP | | |
| DIP | | |
| DRY | | |
| Separation | | |

## Recommended Refactoring Priority
1. {highest impact refactoring}
2. {next}
3. {next}

## Summary
- SOLID violations: {N}
- DRY violations: {N}
- Design issues: {N}
- Architecture score: {total}/35

WHEN DONE:
Message the other teammates: "Purist analysis complete. Review purist-analysis.md"
Mark your task as completed.
```

### Teammate 3: Maintainer

**Model:** sonnet
**MaxTurns:** 10
**Isolation:** worktree
**Effort:** high

```
You are the Maintainer for an architecture debate team.

TARGET:
{file/directory path}

YOUR MISSION:
Assess this code from the perspective of someone who has to maintain it for the next 2 years. Your lens: "If I'm on-call at 2am, can I understand and fix this? If a new team member joins, can they contribute in a week?"

Evaluate:
1. **Cognitive load** — How much context do I need to hold in my head?
2. **Discoverability** — Can I find where things happen? Are there surprises?
3. **Debuggability** — When something breaks, can I trace the issue?
4. **Documentation** — Are the "why" decisions documented? (Not just "what")
5. **Test coverage** — If I change this, will tests catch regressions?
6. **Onboarding** — Could a mid-level dev understand this in a reasonable time?

For each concern:
- Read the actual code
- Describe the specific maintenance burden
- Rate maintenance risk: Easy / Moderate / Hard / Nightmare
- Suggest improvement (if worth the effort)

WRITE your analysis to:
  {project_path}/.reports/maintainer-analysis.md

Use this format:

# Maintainer Analysis

## Cognitive Load Assessment
| # | Area | Load Level | What Makes It Hard | Fix |
|---|------|-----------|-------------------|-----|

## Discoverability Issues
| # | "Where does X happen?" | Answer Difficulty | Why It's Hard to Find |
|---|----------------------|------------------|----------------------|

## Debuggability
| # | Failure Scenario | Can I Trace It? | What's Missing |
|---|-----------------|----------------|----------------|

## Documentation Gaps
| # | Decision | Why It Matters | What Should Be Documented |
|---|----------|---------------|--------------------------|

## Test Coverage Gaps
| # | Area | Covered? | Risk if Changed Without Tests |
|---|------|----------|------------------------------|

## Onboarding Assessment
- Time for mid-level dev to contribute: {estimate}
- Biggest blocker to understanding: {description}
- What I'd explain first: {description}

## Maintenance Risk Rating
| Area | Rating | Reasoning |
|------|--------|-----------|
| Overall | Easy / Moderate / Hard / Nightmare | |
| Most fragile part | | |
| Most stable part | | |

## Summary
- Cognitive load issues: {N}
- Discoverability issues: {N}
- Documentation gaps: {N}
- Test coverage gaps: {N}
- Overall maintenance rating: {rating}

WHEN DONE:
Message the other teammates: "Maintainer analysis complete. Review maintainer-analysis.md"
Mark your task as completed.
```

---

## Output Format

The lead synthesizes into `.reports/architecture-debate.md`:

```markdown
# Architecture Debate Assessment

## Target
{file/directory path, total lines, total files}

## Debate Method
Agent team with 3 competing perspectives.
Source: [pragmatist-analysis.md] | [purist-analysis.md] | [maintainer-analysis.md]

## Summary
| Perspective | Key Position | Issues Found | Worth Fixing |
|-------------|-------------|--------------|--------------|
| Pragmatist | {1-line summary} | {N} | {N} |
| Purist | {1-line summary} | {N} | {N} |
| Maintainer | {1-line summary} | {N} | {N} |

## Consensus: Fix These
Issues all three (or 2 of 3) agree should be addressed:
| # | Issue | Pragmatist | Purist | Maintainer | Effort | Impact |
|---|-------|-----------|--------|------------|--------|--------|

## Accepted Trade-offs
Issues where the team agreed to leave as-is:
| # | Issue | Why Accept | Revisit When |
|---|-------|-----------|--------------|

## Disputed Findings
| # | Issue | For (who) | Against (who) | Resolution |
|---|-------|----------|---------------|------------|

## Architecture Score
| Category | Purist Score | Maintainer Rating | Pragmatist View |
|----------|-------------|-------------------|-----------------|
| SRP | {1-5} | {Easy/Hard} | {Worth fixing?} |
| OCP | {1-5} | {Easy/Hard} | {Worth fixing?} |
| LSP | {1-5} | {Easy/Hard} | {Worth fixing?} |
| ISP | {1-5} | {Easy/Hard} | {Worth fixing?} |
| DIP | {1-5} | {Easy/Hard} | {Worth fixing?} |
| DRY | {1-5} | {Easy/Hard} | {Worth fixing?} |

## Prioritized Improvements
| # | Change | Why | Effort | Risk | Agreed By |
|---|--------|-----|--------|------|-----------|

## Leave Alone
{Code that works, isn't worth refactoring, and all agree should stay}
```

## Related Commands

- `/code-quality:review` — Single-agent rubric-scored code review (faster, no debate)
- `/code-quality:solid` — Automated SOLID check (tools only)
- `/code-quality:security-debate` — Security-focused 3-agent debate
