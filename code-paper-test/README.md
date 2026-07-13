# Paper Test

[![Listed on ClaudePluginHub](https://www.claudepluginhub.com/badge/camoa-code-paper-test-code-paper-test)](https://www.claudepluginhub.com/plugins/camoa-code-paper-test-code-paper-test?ref=badge)

Does this code, skill, or config actually do what it claims, before you run it in anger? AI writes fast and sounds confident either way: a hallucinated method, a variable that is never assigned on one branch, a skill step Claude will quietly skip, all read fine and fail at runtime (or worse, fail silently). Paper testing catches them first, by mentally executing the target line by line with concrete values instead of just reading it and nodding along.

This plugin does that systematically. For code, it traces logic with real inputs and verifies every external call actually exists (both that it exists and that its return shape matches what the caller assumes). For skills, commands, agents, and configs, it traces instructions through Claude instead of code through a CPU: will this actually get invoked, does it follow every step, do the tool and file references it names actually exist. Routing scales the approach to the size and stakes of the target, from a quick inline trace to a competing agent team that argues over the findings.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md): skills work in Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more.

## See it in action

Small code gets a quick inline trace, no command needed, just ask:

```text
You: "paper test this function for edge cases"

  getDiscount($total, $coupon) is 8 lines -> quick trace mode
  SCENARIO: no coupon provided ($coupon = null)
    Line 2: if ($coupon == 'SAVE10')  -> false, skip
    Line 5: if ($coupon == 'SAVE20')  -> false, skip
    Line 8: return $discount          -> $discount is UNDEFINED

  FLAW: Line 8 returns an undefined variable when no coupon matches.
  Severity: HIGH. Fix: initialize $discount = 0 at the top of the function.
```

Larger or security-critical targets get the competing agent team:

```bash
$ /code-paper-test:test-team src/Service/PaymentService.php
  Target is 340 lines -> 3-agent team recommended
  Spawns: Happy Path Validator, Edge Case Hunter, Red Team Attacker (isolated worktrees)
  Step 4: the three cross-challenge each other's findings, disputing false positives
  Step 5: a 4th Synthesizer teammate reads all three analyses and writes the report
  -> paper-test-team-report.md written next to the target file
```

Nothing here is invented output: this is the same routing logic and the same command the plugin actually runs.

## When to reach for it

- Before deploying an AI-generated change, especially one that touches external calls (a library method, a service, an API) you have not independently confirmed exists and behaves as assumed.
- Reviewing unfamiliar code, or debugging without a debugger: tracing state by hand with concrete values finds what a skim misses.
- Building or editing a Claude Code skill, command, agent, or config: paper testing traces the instructions through Claude the same way it traces code through execution, and catches trigger phrasing that will not fire, steps Claude will skip, and references to tools or files that do not exist.
- Security-critical code or a 300+ line target, where the adversarial and edge-case lenses matter enough to justify the competing agent team over a single pass.

## Installation

```bash
# Add the marketplace
/plugin marketplace add https://github.com/camoa/claude-skills

# Install
/plugin install code-paper-test@camoa-skills
```

No plugin dependencies are declared. `/code-paper-test:test-team` needs Claude Code's agent-teams feature to spawn the isolated testers; when it is unavailable in your environment, the command says so and falls back to the single-agent `paper-test` skill.

## What it does, condensed

- **`paper-test` skill** (auto-invoked on phrases like "paper test this", "find bugs in this", "check this config", or call it directly): routes by size, quick trace under 50 lines, structured 3-phase (happy path, edge cases, adversarial) from 50 to 300 lines, all in one agent.
- **`/code-paper-test:test-team <file-path...>`**: a Happy Path Validator, Edge Case Hunter, and Red Team Attacker independently paper-test the target in isolated worktrees, cross-challenge each other's findings, and a 4th Synthesizer teammate writes the prioritized flaw report. Recommended for 300+ lines, security-critical code, or any skill/command/agent file. Accepts `--json` for a CI-consumable report.
- Every mode verifies external dependencies in two passes: existence (does the method exist) and behavioral contract (does its actual return match what the caller assumes, including chained property access).
- Effort-adaptive: both modes scale scenario depth to the active effort level, but the caller's effort is only ever a floor-raiser for the team's adversarial roles, never a way to cheapen them.

The full command reference, the 8 contract-pattern types, the JSON schema, and the skill/config testing methodology are in [docs/usage.md](docs/usage.md) and the `paper-test` skill's `references/` (`skills/paper-test/references/`).

## License

MIT

## Author

camoa

## Repository

https://github.com/camoa/claude-skills
