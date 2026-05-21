# drupal-ai-contrib

AI-assisted Drupal contribution **quality** — *evidence over assertion*.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md) — skills work in Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more.

## Why this exists

Drupal is openly concerned about the *quality* of AI-assisted contributions: AI makes
contributing cheap but makes *reviewing* expensive. This plugin's purpose is not "help
someone contribute" — it is to make AI a **trusted, good-practice** way to contribute:
AI-assisted code that passes drupalci, survives maintainer review on the first or
second round, follows Drupal + PHP best practices, and follows the Code of Conduct and
the adopted AI-contribution policy.

## Core principle — evidence over assertion

Every gate passes **only on a produced artifact** — a command's output, a file diff, a
live API response, a real pipeline result. **Never** on the model stating "done",
"passes", or "should work". The plugin's job is to *produce, capture, and check* that
artifact. It applies the same discipline to its own output.

## Installation

```bash
/plugin marketplace add camoa/claude-skills
/plugin install drupal-ai-contrib@camoa-skills
```

## The contribution arc

Six stages — **detect-driven, not a forced sequence**. Each command checks the state it
needs and runs regardless of whether earlier commands ran; a command that finds a real
gap points at `setup` for *that gap only*. `setup` is the on-ramp, never a prerequisite.

## Commands

| Command | Purpose |
|---------|---------|
| `/drupal-ai-contrib:setup` | Onboard + environment-match a contribution workspace — DDEV with the workflow-matched add-on, CI gate config, the Drupal AI skills. Idempotent. |
| `/drupal-ai-contrib:issue` | Work the issue lifecycle — review prior work first, then create / comment / claim, with three-way issue-fork handling. |
| `/drupal-ai-contrib:verify` | The centerpiece — the local drupalci-parity gate set at CI strictness + the AI-policy gate + the eval gate, every gate on a captured artifact. |
| `/drupal-ai-contrib:review` | Honest fresh-context review against scope, standards, security, and the AI policy. |
| `/drupal-ai-contrib:submit` | Create / update the merge request and the AI-disclosure comment at the policy threshold. |
| `/drupal-ai-contrib:pipeline` | Fetch the real GitLab MR pipeline and gate on it — the authoritative final check. |

## Agents

| Agent | Model | Role |
|-------|-------|------|
| `fresh-context-reviewer` | sonnet | Read-only (`tools: Read, Grep, Glob, Bash`); reviews a diff with no build narrative. |
| `external-fact-verifier` | sonnet | Read-only (`tools: WebFetch, WebSearch, Read, Bash`); verifies an external fact against source or a live probe. |
| `ai-policy-checker` | sonnet | Read-only (`tools: WebFetch, WebSearch, Read`); live-fetches the AI-policy + eval state, maturity-tagged. |

All three are read-only — `disallowedTools: Edit, Write`.

## Skills

- **`drupal-ai-contrib`** — umbrella & router; supplies the contribution knowledge layer.
- Six worker skills — one per command (`contribution-setup` / `-issue` / `-verify` /
  `-review` / `-submit` / `-pipeline`), each backing its command.
- **`contribution-guardrails`** — the cross-cutting development discipline: evidence
  over assertion, the no-guessing rule, the verification-gate artifact contracts.

## Hooks

- **`PostToolUse`** (`Edit|Write`) — re-verification ledger: records every edited
  contribution file so `verify` re-fires the gate for any path changed after it passed.
- **`SessionStart`** — a one-line reminder, emitted only in a contribution workspace,
  that AI-policy + eval guidance must be re-confirmed per contribution.

## The knowledge layer — dev-guides

Technical how-to comes from the `camoa/dev-guides` contribution guides
(`drupal/contributing/` and `drupal/contributing-with-ai/`), loaded via the
`dev-guides-navigator` skill. Worker skills cite guides by slug; they never embed guide
content or fetch dev-guides URLs directly.

## Relationship to drupal-dev-framework

A contribution **is** a `drupal-dev-framework` (DDF) task. DDF owns the phase lifecycle
and its phase gates. `drupal-ai-contrib` is a separate layer **outside** DDF — it adds
contribution-quality commands and gates on top, without forking or modifying DDF.

## Interop — delegate, never reinvent

`code-quality-tools` (philosophy / standards review) · `code-paper-test` (paper
testing) · `drupalorg-cli` (issue / MR / pipeline CLI) · `drupal_devkit` (Drupal AI
skill install) · `ai_best_practices` (the canonical AI policy + evals).
