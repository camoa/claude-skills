# Using Code Quality Tools

The [README](../README.md) is the shop window. This is the how: what the plugin does, when to reach for it, what it needs, how you know it is working, and where it fits with the rest of the marketplace.

## What it does

It runs the checks that separate "it runs" from "it is actually sound": TDD, SOLID, and DRY analysis, plus multi-layer security scanning (Semgrep, Trivy, Gitleaks, and framework-specific SAST) for Drupal and Next.js. Every command auto-detects your project type from real signals (`composer.json` with `drupal/core`, `.ddev/config.yaml`, `next.config.js`, a `next` dependency in `package.json`), so you never tell it which stack you are in, and a monorepo with both runs both toolchains.

`/review` scores code on a `/50` rubric, split evenly between Content (correctness, completeness, edge cases, error handling, security) and Structure (readability, separation of concerns, DRY, testability, extensibility); the quality gate is 35+/50 with no category below 2. `/audit` runs the individual tools and then correlates the results: files flagged by more than one tool are the hot spots, and a security issue sitting next to missing tests and a SOLID violation is called out as compounding risk, not three separate line items. `/security-debate` and `/architecture-debate` spawn 3-agent teams (Defender/Red Team/Compliance; Pragmatist/Purist/Maintainer) that cross-challenge each other's findings before you see a synthesized verdict, each agent in its own worktree with scoped tools and cost-controlled turns. All reports write to git-ignored `.reports/`.

## When to reach for it

- **Before a commit or PR**, when "it runs" is not your actual bar. `/audit` and `/review` are built for this moment.
- **Before deploying**, for the layers a generic linter or the native `/security-review` do not reach: taint analysis, dependency CVEs, secret scanning, and (Drupal) config-level checks.
- **During a refactor**, to find where the coupling and duplication actually are (`/solid`, `/dry`) rather than where you assume they are.
- **On a contentious call**, where a single confident pass is not enough and you want the debate (`/security-debate`, `/architecture-debate`).
- **Underneath `ai-dev-assistant`**, whose `/validate-tdd`, `/validate-solid`, `/validate-dry`, and `/validate-security` commands wrap these same gates with task context. You can also run this plugin standalone, without the full research-to-review lifecycle.

The honest limit: a gate can tell you a rubric score fell below 35, that a tool flagged a pattern, or that a debate did not reach consensus. It cannot make the model write better code on its own, and none of these checks stop drift from happening; they make it visible and gated, with an explicit bypass path (a `bypass_reason` you write, not a silent skip) when you choose to override one.

## Prerequisites

- **Drupal:** DDEV, Drupal 10.3+ or 11.x, PHP 8.2+ (8.3+ recommended). Tools run inside the DDEV container.
- **Next.js:** Node.js 18+, npm or yarn, TypeScript recommended.
- **System tools (both stacks):** Semgrep, Trivy, Gitleaks installed on the host or available to the command runner.
- **Optional, recommended:** a code-intelligence plugin (`php-lsp` or `typescript-lsp`) with its language-server binary, so `/solid`, `/dry`, and `/review` resolve inherited and config-wired relationships semantically instead of falling back to full-file reads.
- Run `/code-quality-tools:setup` first on a new project; it detects the stack and installs what is missing.

## It's working if

- `/code-quality-tools:setup` correctly names your stack (Drupal or Next.js, or both for a monorepo) without you telling it.
- After a run, the matching report exists under `.reports/`: `audit-report.json` and `audit-synthesis.md` for `/audit`, `security-report.json` for `/security`, `code-review-{name}.md` for `/review`, and so on.
- `/audit` names actual hot-spot files, not a generic pass/fail; `/review` prints a `/50` score with a per-category breakdown, not just a verdict.
- `/security` reports a layer count matching your stack (10 for Drupal, 7 for Next.js) and a Critical/High tally you can act on.
- `/security-debate` and `/architecture-debate` produce `.reports/security-debate.md` / `.reports/architecture-debate.md` with a synthesized, cross-challenged verdict, not three unreconciled opinions stapled together.
- If watch-mode is active, editing `composer.json`, `package.json`, `phpstan.neon*`, `psalm.xml`, `eslint.config.*`, or `tsconfig.json` re-triggers lint automatically; `CLAUDE_CODE_QUALITY_WATCH=0` turns that off mid-session if it is not what you want.

If a command reports the wrong stack, check for a stale `.ddev/config.yaml` or a leftover `next.config.js` from a prior scaffold; the detection is signal-based and will follow whatever config files are actually present.

## Where it fits

- **[ai-dev-assistant](../../ai-dev-assistant/README.md)** is the primary consumer: its `/validate-tdd`, `/validate-solid`, `/validate-dry`, and `/validate-security` commands wrap this plugin's gates with task context, and its Phase 4 `/review` runs them as part of the hard-gate set before a task is PR-ready. This plugin also requires no companion to run standalone; ai-dev-assistant declares it as a dependency (v3.13.0+), not the other way around.
- **security-guidance** (a separate, official plugin) is the in-session counterpart: it watches Claude's own edits as they happen, which reduces what reaches this plugin's whole-tree scans without replacing them. `/code-quality-tools:setup` offers to install it.
- **Native `/security-review` and Code Review (`/code-review ultra`)** cover the diff and the PR respectively; this plugin is the whole-codebase, CI-grade SAST stage underneath both, and `/generate-review-md` tunes the injection-model rubric that `/code-review` and `/review` share.
- **[plugin-creation-tools](../../plugin-creation-tools/README.md)** and **[code-paper-test](../../code-paper-test/README.md)** cover Claude Code plugin structure and behavioral verification respectively; this plugin does not check plugin/skill files itself, it checks the application code (Drupal, Next.js) those plugins are built to work on.

For the reasoning behind gates that enforce versus guides that explain the why, see the marketplace [PHILOSOPHY.md](../../PHILOSOPHY.md).
