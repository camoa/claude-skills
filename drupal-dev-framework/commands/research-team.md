---
description: Research or investigate a task with competing agent team (3 perspectives + debate)
allowed-tools: Read, Write, Glob, Grep, WebSearch, WebFetch
argument-hint: <task-name>
---

# Research Team

Research or investigate a task using an agent team with 3 competing perspectives that debate findings.

## Usage

```
/drupal-dev-framework:research-team <task-name>
```

## What This Does

Spawns a 3-teammate agent team for Phase 1 research. Detects whether the task is a **feature** (Build vs Use vs Extend debate) or a **bug** (competing hypothesis investigation). Each teammate writes their own findings file. The lead synthesizes a final output.

## Instructions

When this command is invoked with `$ARGUMENTS`:

### Step 1 — Locate Task

Read the project's `implementation_process/in_progress/$ARGUMENTS/task.md`.

If not found, tell the user:
> Task "$ARGUMENTS" not found. Create it first with `/research` or `/next`.

Extract from task.md: **goal**, **acceptance criteria**, **notes**.
Read `project_state.md` for Drupal version and project context.

### Step 2 — Detect Mode

Read the task goal and notes to determine the mode:

**FEATURE MODE** — goal contains keywords like: build, create, add, implement, new, feature, module, integrate, support
**BUG MODE** — goal contains keywords like: fix, bug, error, broken, failing, regression, issue, crash, 403, 500, exception

Tell the user which mode was detected:
> Detected: **[Feature/Bug] task**. Spawning [feature research / bug investigation] team.
> (Say "switch to [feature/bug] mode" to override.)

### Step 3 — Check Prerequisites

Verify agent teams are available. If not:

> Agent teams require the experimental flag:
> ```json
> // Add to ~/.claude/settings.json
> { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
> ```
> Or: `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
>
> **Fallback:** Run `/research $ARGUMENTS` for standard single-agent research.

Stop here if not available.

### Step 4 — Create Shared Task List

**FEATURE MODE** — create these tasks:

| # | Task | Assign to | Depends on |
|---|------|-----------|------------|
| 1 | Research contrib modules for $ARGUMENTS | Contrib Scout | — |
| 2 | Find core patterns for $ARGUMENTS | Core Pattern Finder | — |
| 3 | Challenge findings and debate recommendation | Devil's Advocate | 1, 2 |
| 4 | Respond to challenges from Devil's Advocate | Contrib Scout + Core Pattern Finder | 3 |
| 5 | Synthesize final research.md | Lead | 3, 4 |

**BUG MODE** — first, formulate 3 plausible hypotheses from the bug description. These must be meaningfully different causes, not variations of the same idea. Then create:

| # | Task | Assign to | Depends on |
|---|------|-----------|------------|
| 1 | Investigate Hypothesis A: {title} | Investigator A | — |
| 2 | Investigate Hypothesis B: {title} | Investigator B | — |
| 3 | Investigate Hypothesis C: {title} | Investigator C | — |
| 4 | Cross-challenge other hypotheses | All investigators | 1, 2, 3 |
| 5 | Synthesize investigation.md with root cause | Lead | 4 |

### Step 5 — Spawn Teammates

Spawn 3 teammates using the appropriate prompt templates below. After spawning:

1. Enable **delegate mode** (Shift+Tab) to prevent doing research yourself
2. Tell the user: "Team spawned. Enable delegate mode (Shift+Tab) to let teammates work. I'll synthesize when they finish."
3. Wait for all teammates to complete before proceeding

### Step 6 — Synthesize

When all teammates finish:

**FEATURE MODE:**
- Read `contrib-scout.md`, `core-patterns.md`, `challenge-log.md`
- Write `research.md` using the Feature Output Format below
- Update `task.md`: mark Phase 1 complete

**BUG MODE:**
- Read `hypothesis-a.md`, `hypothesis-b.md`, `hypothesis-c.md`
- Write `investigation.md` using the Bug Output Format below
- Update `task.md`: mark Phase 1 complete

Update `project_state.md` with current task status.

---

## Feature Mode — Spawn Prompts

### Teammate 1: Contrib Scout

**Model:** haiku

```
You are the Contrib Scout for a Drupal development research team.

PROJECT CONTEXT:
- Task: $ARGUMENTS
- Goal: {goal from task.md}
- Acceptance criteria: {criteria from task.md}
- Drupal version: {version from project_state.md or "10/11"}

YOUR MISSION:
Search drupal.org and the web for existing contrib modules that solve this problem.

For each relevant module, assess:
1. Maintenance status (last commit, open issues, maintainer activity)
2. Drupal 10/11 compatibility
3. Usage stats (number of reported installs)
4. Whether it solves the full problem or only part of it
5. Integration complexity (hooks, plugins, config needed)

WRITE your findings to:
  {project_path}/implementation_process/in_progress/$ARGUMENTS/contrib-scout.md

Use this format:

# Contrib Scout: $ARGUMENTS

## Modules Analyzed
| Module | Version | D10/D11 | Installs | Last Commit | Maintainer Status | Fit |
|--------|---------|---------|----------|-------------|-------------------|-----|

## Detailed Analysis
### {module_name}
- What it does:
- What it doesn't do:
- Integration approach:
- Risks:

## Scout Recommendation
Best candidate: {module} because {reason}
Gaps that need custom code: {gaps}

WHEN DONE:
Message the Devil's Advocate teammate: "Contrib research complete. Review contrib-scout.md"
Mark your task as completed.
```

### Teammate 2: Core Pattern Finder

**Model:** haiku

```
You are the Core Pattern Finder for a Drupal development research team.

PROJECT CONTEXT:
- Task: $ARGUMENTS
- Goal: {goal from task.md}
- Acceptance criteria: {criteria from task.md}
- Drupal version: {version from project_state.md or "10/11"}

YOUR MISSION:
Search Drupal core for reference implementations of the patterns needed for this task.

For each relevant pattern, document:
1. Primary example file path and key methods
2. The base class/interface to extend/implement
3. Dependencies injected and why
4. How core handles edge cases (permissions, caching, validation)
5. Any gotchas or deprecated approaches to avoid

WRITE your findings to:
  {project_path}/implementation_process/in_progress/$ARGUMENTS/core-patterns.md

Use this format:

# Core Patterns: $ARGUMENTS

## Patterns Found
| Pattern | Primary Example | Base Class | Applicability |
|---------|----------------|------------|---------------|

## Detailed Analysis
### {pattern_name}
- File: {path}:{line}
- Key methods: {method}() — {what it does}
- Dependencies: {service} — {why}
- How core handles: {edge case} → {approach}

## Pattern Recommendation
Follow: {pattern} from {file} because {reason}
Adapt: {what to change} because {why}

WHEN DONE:
Message the Devil's Advocate teammate: "Core pattern research complete. Review core-patterns.md"
Mark your task as completed.
```

### Teammate 3: Devil's Advocate

**Model:** sonnet

```
You are the Devil's Advocate for a Drupal development research team.

PROJECT CONTEXT:
- Task: $ARGUMENTS
- Goal: {goal from task.md}
- Acceptance criteria: {criteria from task.md}

YOUR MISSION:
Wait for the Contrib Scout and Core Pattern Finder to complete. Then:

1. Read their findings:
   - {project_path}/implementation_process/in_progress/$ARGUMENTS/contrib-scout.md
   - {project_path}/implementation_process/in_progress/$ARGUMENTS/core-patterns.md

2. Challenge EVERY major claim:
   - "Module X is well-maintained" → When was the last release? Are critical issues open?
   - "Core pattern Y fits" → Does it handle our specific requirements or just the general case?
   - "Use contrib" → Long-term maintenance cost? Will it block Drupal upgrades?
   - "Build custom" → Are we reinventing the wheel?

3. Force the Build vs Use vs Extend decision through adversarial questioning:
   - If scouts agree → find the strongest counterargument
   - If scouts disagree → identify which has better evidence
   - Always ask: "What's the cost of being wrong?"

4. Message scouts with specific challenges. Ask follow-ups. Don't accept weak evidence.

WRITE your challenge log to:
  {project_path}/implementation_process/in_progress/$ARGUMENTS/challenge-log.md

Use this format:

# Challenge Log: $ARGUMENTS

## Challenges Raised
| # | Claim | Source | Challenge | Evidence | Resolution |
|---|-------|--------|-----------|----------|------------|

## Debate Summary
{How the debate progressed, key turning points}

## Debated Recommendation
**Decision:** Build / Use / Extend
**Confidence:** High / Medium / Low
**Reasoning:** {Why this survived the debate}
**Strongest counterargument:** {Best case against this decision}
**Risk if wrong:** {What happens if this decision is wrong}

WHEN DONE:
Broadcast: "Challenge complete. Final recommendation in challenge-log.md"
Mark your task as completed.
```

---

## Bug Mode — Spawn Prompts

### Hypothesis Formation (Lead does this before spawning)

Read `task.md` goal, notes, and any error details. Formulate 3 plausible hypotheses that are meaningfully different — not variations of the same idea.

Example for "Users get 403 after login on certain pages":
- **A**: Permission/role config — route access requirements don't match assigned permissions
- **B**: Caching — page cache serves stale 403 from before login
- **C**: Session handling — session cookie not propagated to subdomain/path

### Teammate: Hypothesis Investigator (sonnet, all three)

All three get this template with their specific hypothesis:

```
You are Investigator {A/B/C} for a Drupal bug investigation team.

PROJECT CONTEXT:
- Task: $ARGUMENTS
- Bug description: {goal from task.md}
- Symptoms: {from task.md notes}
- Affected areas: {from task.md}
- Drupal version: {version from project_state.md or "10/11"}

YOUR HYPOTHESIS:
{hypothesis_title}: {hypothesis_description}

YOUR MISSION:
Investigate whether this hypothesis explains the reported bug.

1. Search for SUPPORTING evidence:
   - Relevant code paths, configuration, module behavior
   - Similar reported issues on drupal.org
   - Whether symptoms match what this cause would produce

2. Search for DISPROVING evidence:
   - Conditions that would prevent this cause
   - Symptoms your hypothesis can't explain
   - If this were the cause, what ELSE would we expect to see?

3. Propose a fix IF your hypothesis holds:
   - What specifically needs to change
   - Risk of the fix (side effects, regressions)
   - How to verify the fix works

4. Challenge other investigators:
   - Read their hypothesis files when available
   - Message them if you find evidence that weakens their theory
   - Be specific: "Your hypothesis can't explain symptom X because..."

WRITE your findings to:
  {project_path}/implementation_process/in_progress/$ARGUMENTS/hypothesis-{a/b/c}.md

Use this format:

# Hypothesis {A/B/C}: {hypothesis_title}

## Theory
{What this hypothesis claims is happening}

## Supporting Evidence
| # | Evidence | Source | Strength |
|---|----------|--------|----------|

## Contradicting Evidence
| # | Evidence | Source | Impact |
|---|----------|--------|--------|

## Proposed Fix
- Change: {what to modify}
- Risk: {side effects}
- Verify: {how to confirm it works}

## Verdict
**Confidence:** High / Medium / Low
{Why this hypothesis does or doesn't explain the bug}

WHEN DONE:
Broadcast: "Hypothesis {A/B/C} investigation complete. Review my findings."
Mark your task as completed.
```

---

## Feature Output Format

The lead writes `research.md` synthesizing all teammate files:

```markdown
# Research: {task_name}

## Problem Statement
{From task.md goal}

## Research Method
Agent team with 3 competing perspectives.
Source files: [contrib-scout.md](contrib-scout.md) | [core-patterns.md](core-patterns.md) | [challenge-log.md](challenge-log.md)

## Existing Solutions
| Solution | Type | Fit | Scout Assessment | DA Challenge | Final Verdict |
|----------|------|-----|------------------|--------------|---------------|

## Core Patterns Found
| Pattern | Location | Applicability | Finder Assessment | DA Challenge | Final Verdict |
|---------|----------|---------------|-------------------|--------------|---------------|

## Debated Recommendation
**Decision:** Build / Use / Extend
**Confidence:** High / Medium / Low
**Consensus:** {How the team arrived at this}
**Dissenting view:** {Any unresolved disagreement}
**Risk if wrong:** {Consequence of wrong decision}

## Key Patterns to Apply
{Patterns that survived the debate}

## Risks and Mitigations
| Risk | Raised by | Mitigation |
|------|-----------|------------|

## Decision Log
| Decision | For | Against | Outcome |
|----------|-----|---------|---------|
```

## Bug Output Format

The lead writes `investigation.md` synthesizing all hypothesis files:

```markdown
# Investigation: {task_name}

## Bug Description
{From task.md goal and notes}

## Investigation Method
Agent team with 3 competing hypotheses.
Source files: [hypothesis-a.md](hypothesis-a.md) | [hypothesis-b.md](hypothesis-b.md) | [hypothesis-c.md](hypothesis-c.md)

## Hypotheses Tested
| # | Hypothesis | Confidence | Outcome |
|---|-----------|------------|---------|
| A | {title} | High/Med/Low | Confirmed / Weakened / Disproved |
| B | {title} | High/Med/Low | Confirmed / Weakened / Disproved |
| C | {title} | High/Med/Low | Confirmed / Weakened / Disproved |

## Root Cause
**Winning hypothesis:** {letter}: {title}
**Confidence:** High / Medium / Low
**Key evidence:** {Strongest evidence that confirmed this}
**What ruled out the others:** {Brief summary}

## Proposed Fix
{From winning investigator, validated against other hypotheses}

### Changes Required
| File/Area | Change | Risk |
|-----------|--------|------|

### Verification Steps
1. {How to confirm the fix works}
2. {How to verify no regressions}

## Risks and Open Questions
| Item | Raised by | Status |
|------|-----------|--------|
```

## Next Steps

After research/investigation is complete:
1. Review findings with user
2. Move to Phase 2: `/drupal-dev-framework:design $ARGUMENTS`

## Related Commands

- `/drupal-dev-framework:research <task>` - Standard single-agent research (fallback)
- `/drupal-dev-framework:design <task>` - Design architecture (Phase 2)
- `/drupal-dev-framework:next` - See recommended next action
