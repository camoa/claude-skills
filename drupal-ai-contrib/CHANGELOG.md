# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-05-21

Initial release — AI-assisted Drupal contribution quality, built per the
`drupal_contrib_workflow` epic architecture. Core principle: **evidence over assertion**
— every gate passes only on a produced, captured artifact, never on an AI assertion.

### Added

- **6 commands** — the detect-driven contribution arc: `setup`, `issue`, `verify`,
  `review`, `submit`, `pipeline`. Thin entry points, each backed by a worker skill.
- **8 skills** — the `drupal-ai-contrib` umbrella & router (supplies the dev-guides
  knowledge layer); six worker skills, one per command; and `contribution-guardrails`,
  the cross-cutting development discipline (no-guessing rule, verification-gate
  artifact contracts). The umbrella and the six workers are `user-invocable: false`.
- **3 read-only agents** — `fresh-context-reviewer` (honest review with no build
  narrative), `external-fact-verifier` (verify an external fact against source or a
  live probe), `ai-policy-checker` (live-fetch the AI-policy + eval state,
  maturity-tagged). All carry `disallowedTools: Edit, Write`.
- **2 hooks** — a `PostToolUse` re-verification ledger (`hooks/reverify-mark.sh` +
  `scripts/reverify-list.sh`) so `verify` re-fires the gate for any path edited after
  it passed; and a context-aware `SessionStart` reminder that speaks only inside a
  contribution workspace.
- **The drupalci-parity gate set** inside `verify` — `composer` / `phpcs` / `phpstan` /
  `phpunit` / `cspell` / `eslint` / `stylelint`, environment-matched to the CI-target
  core, mirroring each enabled `gitlab_templates` job at its real strictness and
  reporting its real blocking status; plus the AI-policy gate (every contribution) and
  the best-effort eval gate.
- **The contribution knowledge layer** — worker skills cite the `camoa/dev-guides`
  contribution guides (`drupal/contributing/`, `drupal/contributing-with-ai/`) by slug,
  loaded via `dev-guides-navigator`.
