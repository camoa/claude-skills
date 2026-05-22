# Contribution Knowledge Layer — dev-guide slugs

The plugin's technical how-to is the `camoa/dev-guides` contribution guides. They are
**already authored** in two topics: `drupal/contributing/` (10 guides) and
`drupal/contributing-with-ai/` (20 guides).

**How to load:** invoke the `dev-guides-navigator` skill with the slug or its keywords.
Never fetch `llms.txt` or dev-guides URLs directly — the navigator owns caching and
disambiguation. If a guide does not resolve, degrade gracefully; never block.

A slug is `<topic>/<guide-name>` — e.g. `drupal/contributing/drupalci-pipeline-gitlab-templates`.

## Stage → guides to load

### `contribution-setup`
- `drupal/contributing/ddev-contribution-environment` — DDEV + the workflow-matched add-on
- `drupal/contributing/contrib-project-scaffolding` — `info.yml`, `composer.json`, `.gitignore`, CI config files
- `drupal/contributing/three-contribution-workflows-compared` — core / own-contrib / others'
- `drupal/contributing-with-ai/ai-toolchain-for-contribution` — Drupal AI skills, guarded dev setup

### `contribution-issue`
- `drupal/contributing/drupal-issue-lifecycle` — status workflow, drupal.org + GitLab dual-mode
- `drupal/contributing/issue-forks-merge-requests` — fork/branch mechanics, branch naming, `drupalorg-cli`
- `drupal/contributing/contribution-etiquette-rtbc-credit` — etiquette, RTBC, the credit system
- `drupal/contributing-with-ai/issue-creation` — creating an issue with AI disclosure

### `contribution-verify`
- `drupal/contributing/drupalci-pipeline-gitlab-templates` — the job set, `_TARGET_*` / `SKIP_*` / `OPT_IN_TEST_*`, `allow_failure`
- `drupal/contributing/drupal-coding-standards-ci-parity` — `phpcs` / `phpstan` at CI strictness
- `drupal/contributing/reproducing-drupalci-failures-locally` — per-job local reproduction
- `drupal/contributing/contrib-project-scaffolding` — `phpunit.xml.dist` version-correct schema
- `drupal/contributing-with-ai/coding-standards` — coding-standard mistakes AI commonly makes
- `drupal/contributing-with-ai/testing-ai-code` — testing AI-generated contributions
- `drupal/contributing-with-ai/drupal-ai-policy` — the adopted AI-contribution policy (the AI-policy gate)
- `drupal/contributing-with-ai/disclosure-checkboxes` — the "significant portion" disclosure threshold
- `drupal/contributing-with-ai/ai-best-practices-and-evals` — `ai_best_practices` + the eval landscape

### `contribution-review`
- `drupal/contributing-with-ai/ai-code-review-checklist` — pre-submission checklist
- `drupal/contributing-with-ai/human-review-requirements` — what "human review" actually requires
- `drupal/contributing-with-ai/security-considerations` — AI-specific security risks
- `drupal/contributing-with-ai/issue-review-guidelines` — how maintainers evaluate AI-flagged issues

### `contribution-submit`
- `drupal/contributing-with-ai/merge-request-workflow` — MR workflow with AI disclosure
- `drupal/contributing/issue-forks-merge-requests` — draft/ready, target-branch rule
- `drupal/contributing-with-ai/commit-messages` — AI attribution in commit messages
- `drupal/contributing-with-ai/disclosure-checkboxes` — the disclosure checkboxes + `AI-Generated: Yes (...)`
- `drupal/contributing/contribution-etiquette-rtbc-credit` — RTBC discipline, credit

### `contribution-pipeline`
- `drupal/contributing/drupalci-pipeline-gitlab-templates` — reading a pipeline (a green pipeline can hide red `allow_failure` + un-run manual jobs)
- `drupal/contributing/reproducing-drupalci-failures-locally` — diagnosing a real failure

### `contribution-guardrails` (cross-cutting development discipline)
- `drupal/contributing-with-ai/evidence-over-assertion` — gates pass on artifacts, not AI claims
- `drupal/contributing-with-ai/supervised-ai-workflow` — why unsupervised AI fails; building guardrails
- `drupal/contributing-with-ai/human-review-requirements` — the honest-review minimum

### `module-theme-maintainer` topic (surfaced by `setup` in new-module / maintainer mode)
- `drupal/contributing/module-theme-maintainer` — owning & maintaining the CI config
