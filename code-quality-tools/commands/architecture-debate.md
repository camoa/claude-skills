---
description: Debate architecture and SOLID findings with three competing subagents (Pragmatist + Purist + Maintainer) across two rounds. Use when user says "debate architecture", "SOLID debate", "is this over-engineered", "should I refactor", "architecture review with debate", "code structure debate", "design review". Best for contentious design decisions where reasonable people disagree.
allowed-tools: Read, Write, Glob, Grep, Bash
argument-hint: <file-or-directory-path>
---

# Architecture Debate

Analyze code architecture from 3 competing perspectives. A Pragmatist defends shipping, a Purist advocates clean architecture, and a Maintainer focuses on long-term readability. A second round has each of them dispute the other two, and the synthesis reports where they disagreed and where all three agreed.

## Usage

```
/code-quality-tools:architecture-debate <file-or-directory-path>
```

## What This Does

Dispatches 3 competing subagents that debate the architecture of the specified code, in two rounds: each analyzes from a different perspective, then each reads and disputes the other two. The lead synthesizes a balanced `architecture-debate.md` in the run's report directory, with agreed improvements and accepted trade-offs.

## Instructions

When this command is invoked with `$ARGUMENTS`:

### Step 0 — Resolve the report directory

Reports do not live in the audited repository. Ask the suite where this run's reports go, rather than guessing a path — run this from the project root:

```bash
REPORT_DIR="$(bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/report-dir.sh" --ensure)" \
  && REPORT_DIR="$(cd "$REPORT_DIR" && pwd)" && echo "$REPORT_DIR"
```

Use that value as `{report_dir}` everywhere below, including in the spawn prompts. It must be **absolute**: the analysts run in isolated worktrees, so a relative path would give each its own private directory, and neither the challenge round nor the lead would find anything to read. The `cd`/`pwd` above is what guarantees that. `--ensure` creates the directory with the 0700 that keeps quoted source and matched-secret filenames off a shared machine, so do not `mkdir` it yourself.

### Step 1 — Check Target Exists

Parse `$ARGUMENTS` as a file or directory path. Verify it exists using the Read tool.

If no arguments provided:
> What code should the team review? Provide a file or directory path:
> ```
> /code-quality-tools:architecture-debate src/Service/
> /code-quality-tools:architecture-debate web/modules/custom/my_module
> ```

If path doesn't exist:
> Path not found: `{path}`. Check the path and try again.

### Step 2 — Check Prerequisites

Nothing beyond the target itself. This command dispatches ordinary subagents with the Agent
tool, which is always available; it needs no agent team, no experimental flag and no Task
tools.

If the Agent tool is unavailable in this session:

> Subagents are not available in this environment.
>
> **Fallback:** Use `/code-quality-tools:solid` for automated SOLID analysis, or ask Claude to "review architecture of {path}".

Stop here if not available.

### Step 3 — Assess Scope

Read target files and count total lines.

If fewer than 30 lines total:
> Target is {N} lines. For small code, a direct review may be more efficient.
> Continue with the 3-agent debate? (The team adds most value with complex architectures.)

Continue if user confirms or if 30+ lines.

### Step 4 — Plan the two rounds

The debate runs in two rounds, and **you sequence them** — dispatch round 2 only after all
three of round 1 have written their files. Nothing in the harness enforces this ordering.
The shared task list that once did requires the Task tools, which current models exclude by
default (v2.1.233+), so the order is yours to keep.

| Round | Work | Who | Reads |
|---|---|---|---|
| 1 | Defend the current architecture — what works, why it ships | Pragmatist | the code |
| 1 | Identify SOLID/DRY violations, propose clean architecture | Purist | the code |
| 1 | Assess maintainability — what confuses a new developer in 6 months | Maintainer | the code |
| 2 | Cross-challenge — dispute trade-offs, find real consensus on what to fix | all three, in parallel | their own round-1 file plus the other two |
| 3 | Synthesize the balanced assessment | you | all six files |

**Quality Gate:** Each agent must address ALL aspects of their perspective. If an agent skips areas (e.g., Purist only checks SRP but ignores OCP/LSP/ISP/DIP), note that in the synthesis and name what was not covered.

### Step 5 — Round 1: dispatch the three analysts

Dispatch all three in **one message**, so they run concurrently. Each is an ordinary
subagent: call the Agent tool with the prompt template below, `model: sonnet`, and
`isolation: "worktree"`. Do **not** pass `name` — a `name` makes the agent a teammate, which
needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and buys nothing here, because every analyst
delivers by writing a file rather than by replying.

After dispatching:

1. Tell the user: "Three analysts are working — I'll run the challenge round when they finish."
2. Do NOT analyze anything yourself. Wait for all three.
3. Confirm each file exists before continuing. An agent that returns prose but writes no file has delivered nothing, and reads exactly like one that found nothing.

**Model & monitoring.** Each prompt below pins `**Model:** sonnet`; naming the model per dispatch is how it is set. There is no global default setting — `teammateDefaultModel` was removed in Claude Code v2.1.234 and a leftover value is ignored. To force one model across every subagent, set `CLAUDE_CODE_SUBAGENT_MODEL` with `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (v2.1.257+); the second is a boolean that promotes the first above the per-dispatch value, which otherwise wins. Watch progress with `/tasks`. Do **not** run the whole debate as a background session (`claude --bg`): the analysts already run in worktree isolation, so that is a worktree-of-worktrees plus permission-auto-deny scenario that is untested.

### Step 5b — Round 2: the cross-challenge

This is the round that makes it a debate rather than three reports side by side. Dispatch all three again in one message, same models and isolation, each with this prompt:

```
You are the {role} in an architecture debate. Round 1 is finished.

YOUR OWN ROUND-1 ANALYSIS:
  {report_dir}/{your-file}.md

THE OTHER TWO ANALYSES:
  {report_dir}/{other-file-1}.md
  {report_dir}/{other-file-2}.md

YOUR MISSION:
Read all three. Then dispute them.

1. Which of their recommendations would you refuse to make, and why? Name the file and
   the change.
2. Where has one of them changed your own round-1 position? Say which, and why.
3. Which proposed refactor costs more than the problem it solves? Which cheap fix did
   they all miss?
4. Where do all three of you agree? Agreement across a pragmatist, a purist and a
   maintainer is either a genuine consensus or a shared blind spot. Say which, and why.

Disagreement is the product here. If you find nothing to dispute, say so explicitly and
explain why the other two were right. Do not manufacture a dispute, and do not stay quiet
to avoid one.

WRITE to: {report_dir}/{your-role}-challenge.md

Format:
# {Role} Challenge

## Recommendations I would refuse
| Their proposal | Why I refuse | What I would do instead |

## Positions I changed
## Unanimous — consensus or blind spot?
## Summary
```

Wait for all three challenge files before synthesizing.

### Step 6 — Synthesize

When all six files exist:

- Read the three round-1 analyses: `{report_dir}/pragmatist-analysis.md`, `{report_dir}/purist-analysis.md`, `{report_dir}/maintainer-analysis.md`
- Read the three round-2 challenges: `{report_dir}/pragmatist-challenge.md`, `{report_dir}/purist-challenge.md`, `{report_dir}/maintainer-challenge.md`
- Write `{report_dir}/architecture-debate.md` using the Output Format below. Consensus, Accepted Trade-offs and Disputed Findings all come from round 2 — a "consensus" drawn from round 1 alone is three independent opinions that happen to agree, which is not the same thing.
- A missing challenge file is reported, never silently skipped: say which lens did not challenge, so a reader knows the assessment rests on two perspectives rather than three.
- Tell the user: "Architecture debate complete. Assessment saved to `{report_dir}/architecture-debate.md`"

---

## Spawn Prompts

### Analyst 1: Pragmatist

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
  {report_dir}/pragmatist-analysis.md

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
When the file is written, you are done. Do not message anyone — the lead reads your
file and dispatches the challenge round; there is no channel between you and the other two.
Mark your task as completed.
```

### Analyst 2: Purist

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
  {report_dir}/purist-analysis.md

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
When the file is written, you are done. Do not message anyone — the lead reads your
file and dispatches the challenge round; there is no channel between you and the other two.
Mark your task as completed.
```

### Analyst 3: Maintainer

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
  {report_dir}/maintainer-analysis.md

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
When the file is written, you are done. Do not message anyone — the lead reads your
file and dispatches the challenge round; there is no channel between you and the other two.
Mark your task as completed.
```

---

## Output

Writes into `{report_dir}`, the audit report directory this run resolves:

- `architecture-debate.md` — the lead's synthesis
- `pragmatist-analysis.md`, `purist-analysis.md`, `maintainer-analysis.md` — one per analyst, round 1
- `pragmatist-challenge.md`, `purist-challenge.md`, `maintainer-challenge.md` — one per analyst, round 2; left in place as the evidence behind the synthesis

## Output Format

The lead synthesizes into `{report_dir}/architecture-debate.md`:

```markdown
# Architecture Debate Assessment

## Target
{file/directory path, total lines, total files}

## Debate Method
Three competing subagents, two rounds.
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

- `/code-quality-tools:review` — Single-agent rubric-scored code review (faster, no debate)
- `/code-quality-tools:solid` — Automated SOLID check (tools only)
- `/code-quality-tools:security-debate` — Security-focused 3-agent debate
