# drupal-ai-contrib

AI-assisted Drupal contribution **quality** — *evidence over assertion*.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md) — skills work in Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more.

## Why this exists

Drupal is openly concerned about the *quality* of AI-assisted contributions: AI makes
contributing cheap but makes *reviewing* expensive. A contribution that looks finished
but fails drupalci, drifts from the coding standards, or hides undisclosed AI authorship
does not save the project time — it spends a maintainer's time.

This plugin exists to make AI a **trusted, good-practice** way to contribute:
AI-assisted code that passes drupalci, survives maintainer review on the first or second
round, follows Drupal + PHP best practices, and follows the Code of Conduct and the
adopted AI-contribution policy.

## What you get

Running the plugin's gates *before* you push means:

- **Your MR is not bounced by drupalci.** The same `phpcs` / `phpstan` / `phpunit` /
  `cspell` jobs CI runs are mirrored locally at CI strictness — environment-matched to
  the CI-target core — so failures surface on your machine, not in the pipeline.
- **You do not burn maintainer goodwill.** A fresh-context agent reviews the diff
  against scope, standards, and security, so the obvious findings are caught before a
  human reviewer ever sees them.
- **You do not risk a disclosure violation.** Significant AI use must be disclosed under
  the adopted policy; undisclosed use is sanctionable (education → temporary ban →
  permanent ban). The plugin assesses the threshold and prepares the disclosure where
  the policy requires it.
- **You ship exactly what was asked.** Over-delivery is review burden a maintainer did
  not ask for — scope discipline is a gate here, not a suggestion.

## Core principle — evidence over assertion

Every gate passes **only on a produced artifact** — a command's output, a file diff, a
live API response, a real pipeline result. **Never** on the model stating "done",
"passes", or "should work". The plugin's job is to *produce, capture, and check* that
artifact. It applies the same discipline to its own output.

## Built on the Drupal AI standards

This plugin does **not** invent its own rules. AI governance for Drupal contributions is
an actively evolving standard, developed in the **`ai_best_practices`** drupal.org
project — the canonical source of truth for the adopted *Policy on the use of AI when
contributing to Drupal* and the contribution **eval suite** (`evals/evals.json`).

Because that standard is still being created, the plugin **tracks it live** rather than
freezing a snapshot that goes stale:

- The `ai-policy-checker` agent fetches the current policy and eval state on **every
  contribution**, and tags each fact **SETTLED / DRAFT / DISCUSSION** so you know what
  is binding versus still in debate.
- The eval gate runs `ai_best_practices`' `evals/evals.json` when available and degrades
  gracefully when it changes — it never hard-pins a schema.
- No policy text is hard-coded in this plugin. As `ai_best_practices` evolves, the
  plugin follows it without needing a release.

The plugin is the **implementation layer** for those standards inside your editor;
`ai_best_practices` remains the authority.

## Installation

```bash
/plugin marketplace add camoa/claude-skills
/plugin install drupal-ai-contrib@camoa-skills
```

**Companions & tools** — `dev-guides-navigator` (companion — supplies the contribution
how-to guides; install it alongside), `mglaman/drupalorg-cli` (issue / MR / pipeline
operations — the executable is `drupalorg`; install the PHAR per
`skills/drupal-ai-contrib/references/drupalorg-cli.md`), DDEV (the local environment),
and a drupal.org account with GitLab access. `setup` detects what is missing and points
you at it; nothing is a hard prerequisite.

## The contribution arc

Six stages — **detect-driven, not a forced sequence**. Each command checks the state it
needs and runs regardless of whether earlier commands ran; a command that finds a real
gap points at `setup` for *that gap only*. `setup` is the on-ramp, never a prerequisite
— a contributor with a ready environment can enter at `issue`, or even at `verify` with
work already underway.

1. **`setup`** — onboard + environment-match the workspace, so local gate results
   actually match CI.
2. **`issue`** — work the issue lifecycle; review prior work *first*, so the
   contribution is not a duplicate.
3. **`verify`** — run the drupalci-parity gates locally at CI strictness, so CI does not
   bounce the MR.
4. **`review`** — honest fresh-context review, so the obvious findings are caught before
   a maintainer sees them.
5. **`submit`** — open the MR with the AI disclosure the policy requires, so the
   submission is compliant.
6. **`pipeline`** — confirm the *real* GitLab pipeline — the authoritative final gate;
   local green is not "done".

## Walkthrough — contribute a fix to an existing module

```bash
# 1. Onboard: detect the workflow, match the environment to CI's target core.
/drupal-ai-contrib:setup

# 2. Claim the issue (numeric drupal.org / GitLab issue ID); reviews prior work first.
/drupal-ai-contrib:issue 3456789

#    ...develop the fix. contribution-guardrails applies during development —
#    evidence over assertion, no guessing external facts.

# 3. Verify locally — the drupalci-parity gates at CI strictness, on captured artifacts.
/drupal-ai-contrib:verify

# 4. Honest review — a fresh-context agent checks scope, standards, security, disclosure.
/drupal-ai-contrib:review

# 5. Open / update the merge request, with the AI disclosure the policy requires.
/drupal-ai-contrib:submit 3456789

# 6. Confirm the real GitLab pipeline — the authoritative final gate.
/drupal-ai-contrib:pipeline
```

You can also enter without a command — *"I want to contribute a fix to the Pathauto
module"* routes to the right stage.

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
  contribution file so `verify` re-fires the gate for any path changed after it passed,
  and so `submit` / `review` can flag a green `verify` invalidated by later edits.
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
testing) · `mglaman/drupalorg-cli` (issue / MR / pipeline CLI — executable `drupalorg`)
· `drupal_devkit` (Drupal AI skill install) · `ai_best_practices` (the canonical AI
policy + evals).
