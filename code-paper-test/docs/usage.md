# Using Paper Test

The [README](../README.md) is the shop window. This is the how: what the plugin does, when to reach for it, what it needs, how you know it is working, and where it fits with the rest of the marketplace.

## What it does

Paper testing is mentally executing a target with concrete values instead of just reading it. For code, that means tracing logic line by line with real inputs, writing out variable state as each line runs, and verifying every external call against its actual declared contract rather than assuming it behaves the way it sounds like it should. For skills, commands, agents, and configs, the same discipline traces instructions through Claude instead of code through a CPU: will a given phrasing actually invoke this skill, does Claude follow every step in order, do the tool and file references it names actually exist, and does the frontmatter say what the body needs it to say.

The plugin ships two ways to run this:

- **The `paper-test` skill**, invoked by natural language ("paper test this", "find bugs in this code", "check this config") or directly. It routes by size: a quick inline trace under 50 lines, or a structured 3-phase pass (happy path, edge cases, adversarial, self-review) from 50 to 300 lines, all in one agent.
- **`/code-paper-test:test-team <file-path...>`**, a competing agent team for 300+ line targets, security-critical code, or any skill/command/agent file. A Happy Path Validator, an Edge Case Hunter, and a Red Team Attacker each paper-test the target independently in isolated worktrees, then cross-challenge each other's findings before a fourth Synthesizer teammate writes the prioritized report.

Both modes verify external dependencies in two passes, existence (does the method exist) and behavioral contract (does its actual return, including chained property or method access, match what the caller assumes), and both scale scenario depth to the active effort level without ever lowering the verification bar.

## When to reach for it

- Before deploying an AI-generated change, especially one with external calls (a library method, a service, an API response) you have not independently confirmed. AI-generated code sounds plausible whether or not the method it calls actually exists.
- Reviewing unfamiliar or legacy code, or debugging without a debugger: tracing state by hand with concrete values surfaces what a skim misses.
- Building or editing a Claude Code skill, command, or agent, where the failure mode is not a runtime crash but a trigger phrase that never fires or a step Claude silently skips under compaction. Pair it with `plugin-creation-tools`' deterministic `skill-quality-reviewer` first, then paper-test for the semantic pass.
- Security-critical code, or a target large enough (300+ lines) that a single pass risks missing what a second, differently-motivated reader would catch. That is what the competing team buys you: the Red Team Attacker's job is to find what the Happy Path Validator was not looking for.

It is not a substitute for actually running the code. It is what you do before that, to catch what a smooth read-through and a green test suite that only exercises the happy path both miss.

## Prerequisites

- No other plugin is a required dependency; `code-paper-test` runs standalone.
- `/code-paper-test:test-team` needs Claude Code's agent-teams capability to spawn its isolated testers. The command checks this itself at Step 2 and, when teams are unavailable, tells you and falls back to asking Claude to run the single-agent `paper-test` skill instead.
- A target to test: a file, a set of files, or a skill/command/agent definition. The plugin reads and analyzes; it does not write or edit the target (`disallowed-tools: Write, Edit` on the `paper-test` skill; `test-team.md` legitimately writes its own analysis and report files).
- Optional: set `teammateDefaultModel` in `settings.json` if you want one model applied to every teammate instead of the per-spawn `Model: sonnet` default. Whether teammates render in split panes or run in the background is determined by whether the command runs inside tmux, not a setting.

## It's working if

- Asking Claude to "paper test" a small function returns a trace with concrete input values, line-by-line state, and a flaw report with a severity score, not a paraphrase of what the code probably does.
- `/code-paper-test:test-team <file>` reports the target's line count, states which routing tier it picked, and (once it proceeds) spawns three named teammates before writing `paper-test-team-report.md` next to the target file (or the JSON report too, with `--json`).
- The dependency verification in the output distinguishes existence from behavior: a call that exists but whose return shape was never checked is labeled differently from one that was fully verified, not folded into a single "verified" checkmark.
- When the target is a skill, command, or agent file, the report talks about trigger coverage, instruction fidelity, and reference verification, the skill/config lens, not code-style bugs that do not apply.
- If agent teams are not available, `/code-paper-test:test-team` says so plainly and points you at the `paper-test` skill instead of failing silently or pretending to have run the team.

## Where it fits

- **[ai-dev-assistant](../../ai-dev-assistant/README.md)** uses this plugin as part of its review method for Claude Code plugin and skill tasks: when a task touches plugin files, paper testing supplies the behavioral verification (does a skill or command actually do what it claims) that a structural check alone cannot. It is also the challenge tool that has been used to harden ai-dev-assistant's own plugin code.
- **[plugin-creation-tools](../../plugin-creation-tools/README.md)** is the deterministic pairing: its `skill-quality-reviewer` catches stale SDK references, dropped imperatives, and frontmatter gaps first; paper testing then covers the semantic ground that check cannot, trigger-phrase coverage, instruction fidelity, and context budget.
- **[code-quality-tools](../../code-quality-tools/README.md)** covers static analysis and security scanning (Semgrep, Trivy, Gitleaks, and the SOLID/DRY/TDD gates). Paper testing is complementary rather than overlapping: it is mental execution with concrete values on the target code at test time, not a scan.
- Not a marketplace plugin, but worth naming since the plugin's own docs draw the line explicitly: Claude Code's native security-guidance capability reviews Claude's own edits in real time as they happen. The Red Team Attacker lens here analyzes the target code for adversarial vulnerabilities at test time, before or after those edits. Different moments, not substitutes for each other.

For the reasoning behind gates-that-enforce versus guides-that-explain, and why paper testing treats the AI as an assistant to challenge rather than an oracle to trust, see [PHILOSOPHY.md](../../PHILOSOPHY.md).
