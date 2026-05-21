---
name: drupal-ai-contrib
description: "Routes Drupal contribution work to the right contribution-quality stage and supplies the contribution knowledge layer. Use when user says 'contribute to Drupal', 'Drupal contribution', 'submit a Drupal patch', 'Drupal merge request', 'fix a Drupal core issue', 'contribute a module', 'AI-assisted Drupal contribution', or works a drupal.org / GitLab Drupal issue. Use PROACTIVELY whenever AI-assisted code is headed for a Drupal contribution — drupalci and maintainer review are unforgiving."
version: 0.1.0
model: sonnet
user-invocable: false
---

# Drupal AI Contribution — Umbrella & Router

Make AI a trusted, good-practice way to contribute to Drupal: AI-assisted code that
passes drupalci, survives maintainer review on the first or second round, follows
Drupal + PHP best practices, and follows the Code of Conduct and the adopted
AI-contribution policy.

This skill **routes** a contribution request to the right stage and supplies the
**knowledge layer**. It does not run the stages itself — each stage is a worker skill.

## Core principle — evidence over assertion

Every gate passes **only on a produced artifact**: a command's output, a file diff, a
live API response, a real pipeline result. Never on the model stating "done", "passes",
or "should work". The cross-cutting discipline lives in the `contribution-guardrails`
skill — invoke it during any development between `issue` and `verify`.

## The contribution arc — detect-driven, not a forced sequence

Six stages. Each checks the state it needs and runs regardless of whether earlier
stages ran. A contributor can enter at `issue` (environment ready) or even at `verify`
(work underway). A stage that finds a real gap points at `setup` for *that gap only*;
it never refuses to run. `setup` is the on-ramp, never a prerequisite.

| Stage | Command | Worker skill |
|-------|---------|--------------|
| 1. Onboard the environment | `/drupal-ai-contrib:setup` | `contribution-setup` |
| 2. Work the issue | `/drupal-ai-contrib:issue` | `contribution-issue` |
| 3. Verify locally (the inner loop) | `/drupal-ai-contrib:verify` | `contribution-verify` |
| 4. Honest review | `/drupal-ai-contrib:review` | `contribution-review` |
| 5. Submit the MR | `/drupal-ai-contrib:submit` | `contribution-submit` |
| 6. Confirm the real pipeline | `/drupal-ai-contrib:pipeline` | `contribution-pipeline` |

## Routing

When a contribution request arrives without a specific command, route it:

| The contributor wants to… | Route to |
|---------------------------|----------|
| Stand up a DDEV environment, scaffold CI config, install Drupal AI skills | `contribution-setup` |
| Find / create / claim an issue, check out an issue fork + branch | `contribution-issue` |
| Run the local drupalci-parity / AI-policy / eval gates | `contribution-verify` |
| Get an honest, fresh-context review of the work | `contribution-review` |
| Create or update the merge request, write the AI-disclosure comment | `contribution-submit` |
| Check the authoritative real GitLab MR pipeline | `contribution-pipeline` |
| Develop code safely between `issue` and `verify` | `contribution-guardrails` |

Ambiguous request → ask which stage; do not guess.

## The knowledge layer — dev-guides

Technical how-to (writing the code correctly, the contribution mechanics, coding
standards, the drupalci pipeline) comes from the `camoa/dev-guides` contribution
guides, **not** from this plugin. Load them via the `dev-guides-navigator` skill —
never fetch `llms.txt` or dev-guides URLs directly.

`references/dev-guides-index.md` maps each contribution stage to the dev-guide slugs to
load. Worker skills cite those slugs. A guide that is not yet authored simply will not
resolve — the navigator degrades gracefully; never block on a missing guide.

## The governance layer — ai_best_practices

AI-policy + compliance + evals anchor on `ai_best_practices` (the canonical Drupal AI
source of truth) and the adopted *Policy on the use of AI when contributing to Drupal*.
Both are fetched **live** per contribution by the `ai-policy-checker` agent — never
hard-coded, never assumed; this is the fastest-moving area.

## Relationship to drupal-dev-framework

A contribution **is** a `drupal-dev-framework` (DDF) task. DDF owns the phase lifecycle
(research → architecture → implement → review → complete) and its phase gates. This
plugin is a separate layer **outside** DDF — it adds contribution-quality commands and
gates on top. It does not fork or modify DDF. Run the contribution as a DDF task and
use this plugin's commands alongside it.

## Interop — delegate, never reinvent

| Need | Delegate to |
|------|-------------|
| Phase lifecycle + phase gates | `drupal-dev-framework` |
| Philosophy / standards review (SOLID, DRY) | `code-quality-tools` |
| Paper-testing before submission | `code-paper-test` |
| Issue / MR / pipeline CLI | `drupalorg-cli` (wrapped by `issue` / `submit` / `pipeline`) |
| Drupal AI skill install | `drupal_devkit` |

## Examples

### Example 1: natural-language entry, no command
**User says:** "I want to contribute a fix to the Pathauto module."
**Actions:**
1. Recognize a Drupal contribution request with no specific stage named.
2. There is no environment context yet → route to `contribution-setup` to detect the
   workflow (someone else's contrib) and environment, then `contribution-issue`.
**Result:** The contributor is on-ramped at the right stage without guessing.

### Example 2: mid-arc entry
**User says:** "Check my Drupal contribution before I submit it."
**Actions:**
1. Work is already underway → skip `setup`/`issue`.
2. Route to `contribution-verify` (gates), then `contribution-review` (honest review).
**Result:** Entry at `verify` — earlier stages are not forced.

## Troubleshooting

| Situation | Handling |
|-----------|----------|
| Request could be two stages | Ask which stage; never guess the route. |
| A dev-guide slug does not resolve | The navigator degrades gracefully — proceed without it; never block. |
| Contributor asks to skip a stage | Allowed — the arc is detect-driven. Surface what evidence the skipped stage would have produced. |
| Request is Drupal dev but not contribution | Out of scope — this is contribution quality, not general Drupal dev. Defer to `drupal-dev-framework`. |

## References

- `references/dev-guides-index.md` — contribution stage → dev-guide slugs to load
