# drupal-ai-contrib

[![Listed on ClaudePluginHub](https://www.claudepluginhub.com/badge/camoa-drupal-ai-contrib-drupal-ai-contrib)](https://www.claudepluginhub.com/plugins/camoa-drupal-ai-contrib-drupal-ai-contrib?ref=badge)

AI-assisted Drupal.org contributions get bounced for unverified claims and policy misses. AI makes contributing cheap, but it makes *reviewing* expensive: a contribution that looks finished but fails drupalci, drifts from coding standards, or hides undisclosed AI authorship does not save a maintainer's time, it spends it.

This plugin runs the gates before you push, so the failure surfaces on your machine instead of in the pipeline or in a maintainer's inbox. **Evidence over assertion** is the core rule: every gate passes only on a produced artifact (a command's output, a file diff, a live API response, a real pipeline result), never on the model stating "done" or "should work". It mirrors the drupalci jobs locally at CI strictness, runs a fresh-context review against scope and standards, assesses the AI-contribution disclosure threshold, and checks the real GitLab pipeline before calling anything finished.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md): skills work in Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more.

## See it in action

A fix to an existing module, from claiming the issue to confirming the real pipeline. The commands are real; the output is trimmed to what you would actually see.

```text
$ /drupal-ai-contrib:setup
  Detected workflow: module contribution. Environment-matched to the CI-target core.
  drupalorg CLI: found.  glab: authenticated.  SSH key: registered.

$ /drupal-ai-contrib:issue 3456789
  Prior work reviewed: no duplicate MR found.
  Fork: none existing → branch created from your issue fork.

  ...develop the fix. contribution-guardrails applies during development: evidence
  over assertion, no guessing external facts.

$ /drupal-ai-contrib:verify
  phpcs ...... PASS   phpstan .... PASS   phpunit .... PASS   cspell ..... PASS
  ai-policy .. PASS   eval ....... PASS   (artifacts captured for each)

$ /drupal-ai-contrib:review
  0 blockers, 1 should-fix (missing docblock on FeedController::build(), line 42).
  Verdict: another development pass needed.

  ...fix flagged, re-verify, then:

$ /drupal-ai-contrib:submit 3456789
  MR opened against 11.x. AI-disclosure comment posted (policy threshold met).
  Next: /drupal-ai-contrib:pipeline

$ /drupal-ai-contrib:pipeline
  phpunit ... passed   phpcs ... passed   eslint (allow_failure) ... failed
  Verdict: not done, an allow_failure job is red and local green did not cover it.
```

Nothing here was a guess: the review found a real gap before a maintainer would have, and the pipeline check caught what a bare "green" would have hidden. That is the plugin doing its job.

## When to reach for it

Reach for it any time you or an AI assistant is preparing a contribution to a Drupal.org project: a bug fix, a new feature, a security patch, a documentation change to a module, theme, or core. It fits equally whether you are writing the patch by hand and want the gates as a safety net, or an AI agent is doing most of the typing and you want its output held to the same bar a human contributor is held to.

It is not needed for work that never leaves your own site: a client build, a private module, a one-off script. The gates here exist because a drupal.org merge request is reviewed by someone else's time, not yours.

## Installation

```bash
/plugin marketplace add https://github.com/camoa/claude-skills
/plugin install drupal-ai-contrib@camoa-skills
```

**Companions & tools:** `dev-guides-navigator` (companion, supplies the contribution how-to guides; install it alongside), `mglaman/drupalorg-cli` (issue / MR / pipeline operations, the executable is `drupalorg`; install the PHAR per `skills/drupal-ai-contrib/references/drupalorg-cli.md`), `glab` (installed and authenticated for `git.drupalcode.org`, for the authenticated GitLab MR / pipeline / fork-push operations), DDEV (the local environment), and a drupal.org account with GitLab access. `setup` detects what is missing and points you at it; nothing here is a hard prerequisite for the plugin to load.

## Commands

| Command | Purpose |
|---------|---------|
| `/drupal-ai-contrib:setup` | Onboard + environment-match a contribution workspace. Idempotent. |
| `/drupal-ai-contrib:issue` | Work the issue lifecycle: review prior work first, then create / comment / claim, with three-way issue-fork handling. |
| `/drupal-ai-contrib:verify` | The centerpiece: drupalci-parity gates at CI strictness plus the AI-policy gate and the eval gate, every gate on a captured artifact. |
| `/drupal-ai-contrib:review` | Honest fresh-context review against scope, standards, security, and the AI policy. |
| `/drupal-ai-contrib:submit` | Create / update the merge request and the AI-disclosure comment at the policy threshold. |
| `/drupal-ai-contrib:pipeline` | Fetch the real GitLab MR pipeline and gate on it: the authoritative final check. |

Six stages, detect-driven rather than a forced sequence: each command checks the state it needs and runs regardless of whether earlier commands ran, and a command that finds a real gap points at `setup` for that gap only. You can also enter without a command: *"I want to contribute a fix to the Pathauto module"* routes to the right stage.

The full component list (agents, skills, hooks, the knowledge layer, and how the standards stay current) is in [docs/usage.md](docs/usage.md).

## Built on the Drupal AI standards

This plugin does not invent its own rules. AI governance for Drupal contributions is an actively evolving standard, developed in the **`ai_best_practices`** drupal.org project, the canonical source of truth for the adopted *Policy on the use of AI when contributing to Drupal* and the contribution **eval suite** (`evals/evals.json`). Because that standard is still being written, the plugin tracks it live instead of freezing a snapshot that goes stale: the `ai-policy-checker` agent fetches the current policy and eval state on every contribution and tags each fact SETTLED, DRAFT, or DISCUSSION, and the eval gate degrades gracefully when the schema changes rather than hard-pinning it. No policy text is hard-coded here; as `ai_best_practices` evolves, the plugin follows without needing a release.

## Relationship to ai-dev-assistant

A contribution *is* an [ai-dev-assistant](../ai-dev-assistant/README.md) task. That framework owns the phase lifecycle and its phase gates. `drupal-ai-contrib` is a separate layer outside the framework: it adds contribution-quality commands and gates on top, without forking or modifying it. More in [docs/usage.md](docs/usage.md#where-it-fits).

## More

- **Deeper how-to:** [docs/usage.md](docs/usage.md). What it does, when to reach for it, prerequisites, "it's working if", and where it fits with the rest of the marketplace.
- **Philosophy:** [PHILOSOPHY.md](../PHILOSOPHY.md). Why the marketplace's plugins enforce instead of just advising.
- **Changelog:** [CHANGELOG.md](./CHANGELOG.md).

## License

MIT
