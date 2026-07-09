---
description: "Route a described SITUATION or intent to the right ai-dev-assistant command or flow — a map by intent, not by task state (that's /next). Trigger: 'which command should I use', 'what flow fits this', 'I have a hard bug', 'I want to plan a feature', 'I need to review a branch', 'which command for X', 'how do I start this in ai-dev-assistant'. Static router — never runs the commands it names, only points at them. Introduced v5.20.0."
allowed-tools: Read
argument-hint: "[situation or intent, e.g. \"I have a hard bug\" | \"plan a new feature\" | \"review a branch before PR\"]"
---

# Which

Answer "which `ai-dev-assistant` command or flow fits what I'm trying to do?" — given a **situation or intent** described in plain language, not given the state of an active task.

## Not `/next` — read this first

**`/ai-dev-assistant:next` answers a different question than this command.** They are not redundant; they route on opposite axes:

- **`/next`** answers *"given where my task IS right now, what's the next action?"* — it reads `project_state.md` and the active task's phase files (research.md / architecture.md / implementation.md, work-order status, epic children) and tells you the single next command **for that task**. It is **state-based**.
- **`/which`** answers *"given a SITUATION or intent I can describe — 'I have a hard bug', 'I want to plan a feature', 'I need to review a branch' — which command or flow do I reach for?"* It never inspects project state, never reads a task folder, and doesn't know or care what phase anything is in. It is **intent-based**.

If you already have an active task and just want to keep moving on it, stop here and run `/ai-dev-assistant:next` instead — it will give you a state-correct answer this command cannot. Use `/which` when you don't have a task in front of you yet, or you have one but aren't sure which of several available commands applies to what you're about to do (e.g. "should this be `/pattern` or `/research-team`?").

This command is a **map, not an implementation** — it never invokes the commands it names. It tells you which one to run and why, then stops.

## Usage

```
/ai-dev-assistant:which                              # print the full situation → command map
/ai-dev-assistant:which I have a hard bug             # route a described situation
/ai-dev-assistant:which I want to plan a new feature
/ai-dev-assistant:which review a branch before PR
```

## What This Does

1. If `$ARGUMENTS` is empty, print the **Situation → Command Map** below in full and stop.
2. If `$ARGUMENTS` describes a situation, match it against the map's situations (semantic match, not literal keyword match — "I'm stuck on a weird bug" and "hard bug" and "something's broken and I don't know why" all match the same row). Reply with:
   - **Command:** the exact `/ai-dev-assistant:<command>` to run (with args if applicable)
   - **Why:** one line tying the situation to the command's job
   - **Alternatives:** other commands that could also fit, and what would make you pick them instead
3. Never execute the recommended command — this command's only output is the recommendation.
4. If the situation is actually "what do I do next on the task I'm already working on," redirect to `/ai-dev-assistant:next` instead of guessing (see the callout above).

## The Lifecycle Spine

Every task in the framework moves through the same six phases. Most rows in the map below resolve to one point on this spine:

```
/scope → /research → /design → /implement → /review → /complete
(optional)  Phase 1     Phase 2     Phase 3    Phase 4
```

| Phase | Command | Question it answers |
|---|---|---|
| 0 (optional) | `/ai-dev-assistant:scope <task>` | What is this task's Goal / Expected result / Success criteria / Non-goals? |
| 1 | `/ai-dev-assistant:research <task>` | What patterns/prior art exist? What should this be built on? |
| 2 | `/ai-dev-assistant:design <task>` | What's the architecture — components, dependencies, patterns? |
| 3 | `/ai-dev-assistant:implement <task>` | Write the code (TDD-enforced). |
| 4 | `/ai-dev-assistant:review <task>` | Run all hard-blocking gates before a PR. |
| — | `/ai-dev-assistant:complete <task>` | Mark done, archive, surface candidate plays. |

`/ai-dev-assistant:new` starts a brand-new project (before any task exists). `/ai-dev-assistant:next` is the state-aware pointer that walks this spine for you on an existing task — see the callout above.

## Situation → Command Map

### Starting from nothing
| Situation | Command |
|---|---|
| "I'm starting a whole new project" | `/ai-dev-assistant:new` |
| "I have a task idea but want to nail down scope before research" | `/ai-dev-assistant:scope <task>` |
| "I want to jump straight into investigating how to build this" | `/ai-dev-assistant:research <task>` |

### Investigating / deciding an approach
| Situation | Command |
|---|---|
| "I have a hard bug and need to dig in" | `/ai-dev-assistant:research <task>` — capture findings in research.md before touching code |
| "I want a second opinion / competing perspectives on a hard decision" | `/ai-dev-assistant:research-team <task>` — 3-perspective agent debate, use over `/research` when the call is genuinely contested |
| "I know roughly what I want but not which pattern to use" | `/ai-dev-assistant:pattern <use-case>` — pattern recommendation with a reference example |
| "I want to plan a feature's architecture" | `/ai-dev-assistant:design <task>` — requires research done first |
| "This task feels too big / has unrelated pieces bundled together" | `/ai-dev-assistant:migrate-to-epic <task>` (one task) or `/ai-dev-assistant:propose-epics` (bulk-scan all in-progress tasks) |

### Building
| Situation | Command |
|---|---|
| "I'm ready to write code" | `/ai-dev-assistant:implement <task>` — requires design done first, enforces TDD |
| "I want to check code against the documented architecture mid-build" | `/ai-dev-assistant:validate <component-or-file>` — architecture-fit check, distinct from the quality gates below |
| "I need an isolated workspace to build in parallel with another session" | `/ai-dev-assistant:worktree <task>` |
| "I want to build a large task as independent, gate-verifiable units, possibly unattended" | `/ai-dev-assistant:compile-work-orders <task>` then `/ai-dev-assistant:run-work-orders <task>` (`--parallel` for concurrent independent units) |

### Reviewing a branch / checking quality
| Situation | Command |
|---|---|
| "I need to review a branch before opening a PR" | `/ai-dev-assistant:review <task>` — Phase 4, runs all hard-blocking gates, writes PR_BODY.md on green |
| "I want an honest, non-self-reviewed pass (fresh context per gate)" | `/ai-dev-assistant:validate-team` — sibling to `/validate:all`, isolated agent teams |
| "I just want one specific gate (TDD / SOLID / DRY / security / guides)" | `/ai-dev-assistant:validate-tdd`, `-solid`, `-dry`, `-security`, `-guides` (or `-playbook-adherence`) |
| "I want the whole soft-nudge gate sweep without the Phase-4 ceremony" | `/ai-dev-assistant:validate-all` |
| "Does this match the Figma / design comp?" | `/ai-dev-assistant:visual-check` (ad hoc) or `/ai-dev-assistant:validate-visual-parity` (registry-driven, part of `/review`) |
| "Did anything visually regress vs. last green?" | `/ai-dev-assistant:validate-visual-regression` |
| "Does the user flow still work end-to-end?" | `/ai-dev-assistant:validate-e2e` |
| "What gates fired or were bypassed on this task?" | `/ai-dev-assistant:audit-status <task>` |

### Finishing
| Situation | Command |
|---|---|
| "I'm done, close the task" | `/ai-dev-assistant:complete <task>` — verifies `/review` ran when Review Required is true |
| "I'm ending my session, save in-flight state" | `/ai-dev-assistant:save-session` |

### First-time setup / configuration
| Situation | Command |
|---|---|
| "Set up visual regression / parity / E2E gates for this project" | `/ai-dev-assistant:setup-visual-regression`, `/ai-dev-assistant:setup-visual-parity`, `/ai-dev-assistant:setup-e2e` |
| "Tell the framework where my code actually lives" | `/ai-dev-assistant:set-code-path` |
| "Subscribe to or change this project's best-practices playbook" | `/ai-dev-assistant:set-playbook-sets`, `/ai-dev-assistant:set-user-playbook` |
| "Capture / review the plays in the local playbook" | `/ai-dev-assistant:playbook-capture`, `/ai-dev-assistant:playbook-review`, `/ai-dev-assistant:playbook-active` (read-only) |
| "Bring an older project's state up to current scaffolder parity" | `/ai-dev-assistant:upgrade-project` |
| "Install session-remembrance hooks / a dangerous-command guardrail" | `/ai-dev-assistant:install-remembrance-hook`, `/ai-dev-assistant:install-guardrails` |
| "I have old v2.x single-file tasks" | `/ai-dev-assistant:migrate-tasks` |

### Just looking
| Situation | Command |
|---|---|
| "Where am I / what's the project status" | `/ai-dev-assistant:status` |
| "What should I do next on my active task" | `/ai-dev-assistant:next` — **not this command**, see the callout above |
| "Clean up abandoned worktrees" | `/ai-dev-assistant:worktree-prune` |

## Flows (multi-step chains)

Some situations resolve to a short sequence, not one command:

- **Autonomous work-order path:** `/ai-dev-assistant:worktree <task>` → `/ai-dev-assistant:compile-work-orders <task>` → `/ai-dev-assistant:run-work-orders <task>` (add `--parallel` once compiled if units are independent).
- **Epic sizing:** `/ai-dev-assistant:migrate-to-epic <task>` (single) or `/ai-dev-assistant:propose-epics` (bulk scan) → then work the resulting subtasks through the normal spine; `/ai-dev-assistant:next` will bias toward the active epic's siblings once children exist.
- **Full lifecycle on one task:** `/ai-dev-assistant:scope` (optional) → `/ai-dev-assistant:research` → `/ai-dev-assistant:design` → `/ai-dev-assistant:implement` → `/ai-dev-assistant:review` → `/ai-dev-assistant:complete`.

## Related Commands

- `/ai-dev-assistant:next` — state-based "what's next on my active task" (the complement to this command)
- `/ai-dev-assistant:status` — full project/task overview
- `/ai-dev-assistant:pattern <use-case>` — narrower pattern-choice recommender (Phase 2 tool; `/which` is the broader command-level router)
