# Using drupal-ai-contrib

The [README](../README.md) is the shop window. This is the how: what the plugin does, when to reach for it, what it needs, how you know it is working, and where it fits with the rest of the marketplace.

## What it does

It runs a Drupal.org contribution through six detect-driven stages instead of a forced sequence: `setup` (onboard and environment-match to the CI-target core), `issue` (work the issue lifecycle, reviewing prior work first so the contribution is not a duplicate), `verify` (mirror the drupalci job set locally at CI strictness, plus the AI-policy gate and the eval gate), `review` (a fresh-context agent checks the diff against scope, standards, and security with no build narrative), `submit` (open or update the merge request with the AI-disclosure comment the policy requires), and `pipeline` (fetch the real GitLab pipeline, the authoritative final check). Each command checks the state it needs and runs regardless of whether earlier commands ran; a command that finds a real gap points at `setup` for that gap only, it never refuses to run.

The rule underneath all six stages is evidence over assertion: a gate passes only on a produced artifact (a command's output, a file diff, a live API response, a real pipeline result), never on the model stating "done" or "should work". A `PostToolUse` hook keeps a re-verification ledger, so an edit made after `verify` last passed re-fires the affected gate, and `submit` / `review` can flag a green `verify` that a later edit invalidated.

## When to reach for it

Reach for it whenever you are preparing a contribution to a Drupal.org project: a bug fix, a feature, a security patch, or a documentation change to a module, theme, or core, whether you are writing it by hand or an AI agent is doing most of the typing. It applies equally to a first-time contributor and a maintainer doing routine patch work; the gates exist because a merge request is reviewed on someone else's time, and the plugin's job is to catch what that reviewer would otherwise have to.

It is not needed for code that never leaves your own site: a client build, a private module, a one-off script written for one project. Within the marketplace, a contribution *is* an [ai-dev-assistant](../../ai-dev-assistant/README.md) task, so on a project already running that framework's phase lifecycle, this plugin adds the contribution-specific commands and gates on top rather than replacing anything.

## Prerequisites

- A **drupal.org account with GitLab access**, and an SSH key registered for it. `setup` checks this and names it as the first next step if it is missing.
- **`mglaman/drupalorg-cli`** (executable `drupalorg`) for issue, MR, and pipeline operations. Install the PHAR per `skills/drupal-ai-contrib/references/drupalorg-cli.md`.
- **`glab`**, installed and authenticated for `git.drupalcode.org`, for GitLab operations.
- **DDEV** as the local environment, so `verify` can environment-match to the CI-target core.
- **`dev-guides-navigator`** (companion) supplies the contribution how-to guides; the worker skills cite guides by slug rather than embedding guide content.
- None of these are hard prerequisites for the plugin to load. `setup` detects what is missing and points at the gap; a contributor with a ready environment can skip straight to `issue`, or even enter at `verify` with work already underway.

## It's working if

- `/drupal-ai-contrib:setup` reports the detected workflow, the environment-match result, and the status of `drupalorg`, `glab`, and your SSH key, rather than silently doing nothing.
- `/drupal-ai-contrib:issue <id>` reports what prior work it found on the issue before it creates, comments, or claims anything.
- `/drupal-ai-contrib:verify` prints a per-gate table (PASS / FAIL / UNRUN) with a captured artifact behind each result, not a bare "all good". An edit made after a passing run causes the affected gate to re-fire on the next `verify`.
- `/drupal-ai-contrib:review` returns findings with a file:line location and a concrete fix, plus a plain verdict: ready for `submit`, or another pass needed.
- `/drupal-ai-contrib:submit` reports the MR URL, the target branch, and the AI-disclosure decision (posted or not, and why).
- `/drupal-ai-contrib:pipeline` reports each job's real status, distinguishing blocking failures from `allow_failure` and manual jobs, and states plainly whether the contribution is done.

If a command reports a gap instead of running its gate, that is the plugin working as designed: it names the gap and points at `setup`, rather than pretending the gate passed.

## Where it fits

- **[ai-dev-assistant](../../ai-dev-assistant/README.md)** owns the phase lifecycle (research, architecture, implementation, review) that a contribution runs through as a task. `drupal-ai-contrib` sits outside that framework as a separate layer, adding contribution-specific commands and gates on top, without forking or modifying it.
- **[dev-guides-navigator](../../dev-guides-navigator/README.md)** supplies the contribution how-to guides (`drupal/contributing/` and `drupal/contributing-with-ai/`), loaded by the worker skills by slug.
- **[code-quality-tools](../../code-quality-tools/README.md)** backs the philosophy and standards portion of the `review` gate (SOLID / DRY checks), delegated to rather than reimplemented here.
- **[code-paper-test](../../code-paper-test/README.md)** is available for paper-testing the contribution's logic as a complementary check.
- **`ai_best_practices`** (the drupal.org project, not a plugin) is the canonical source for the AI-contribution policy and the eval suite this plugin tracks live rather than hard-codes.
- **`security-guidance`** (a separate, official plugin) is a complementary in-session layer that auto-reviews Claude's own edits as they happen. It does not replace the fresh-context contribution review this plugin runs at the `review` stage; install it separately if you want both.
