# Changelog

All notable changes to this project will be documented in this file.

## [0.2.0] - 2026-06-16

BUG-1 (model-pin overflow footgun) plus Claude Code hardening. No gate logic, no
drupalci-parity, no AI-policy/eval behavior changed — this wave is frontmatter + advisory
guidance only.

### Fixed

- **BUG-1 / S14 — inline model-pin overflow.** All 8 SKILL.md files pinned
  `model: sonnet`. A skill `model:` is an inline, current-turn override with no context
  isolation, so a sub-1M pin overflows when the skill activates from a large conversation.
  Changed to `model: inherit` on every skill (`contribution-guardrails`, `-issue`,
  `-pipeline`, `-review`, `-setup`, `-submit`, `-verify`, and the `drupal-ai-contrib`
  umbrella). The 3 agents keep `model: sonnet` — they run in fresh subagent contexts and
  are S14-exempt.

### Added

- **Read-only tool restriction.** `disallowed-tools: Edit, Write` (kebab-case skill field)
  on the 4 read-only worker skills: `contribution-review` (dispatches agents),
  `contribution-verify` (runs gates, captures artifacts), `contribution-pipeline` (reads
  status), `contribution-guardrails` (enforces discipline). `-setup`, `-issue`, `-submit`,
  and the umbrella keep full access (they scaffold / run git ops / create MRs).
- **Sandbox guidance for untrusted code execution** (`contribution-verify`). `verify`
  runs the contributor's own `composer install` / `phpunit` / `eslint` at CI strictness —
  untrusted code. Added a note recommending the process-level `@anthropic-ai/sandbox-runtime`
  (constrains the whole process — Bash, file tools, MCP, hooks — not only Bash) for
  unreviewed contributions, with a VM / Claude Code on the web pointer for fully untrusted
  repos.
- **Large-codebase scoping note** (`contribution-verify`) — for core / large-suite
  contributions, scope `verify` to the changed subtree; cites the Large Codebases and
  Monorepos guide.
- **Complementary security layer** (`contribution-review` + `README.md`) — documents that
  the `security-guidance` plugin (auto, watches Claude's own in-session edits) is a
  complementary defense-in-depth layer to the per-contribution, explicitly-dispatched
  `fresh-context-reviewer` agent — different scopes, never a replacement. Install pointer
  included.

### Changed

- **`CONVENTIONS.md` release hygiene** — documents `/plugin-creation-tools:validate --strict`
  as a required pre-release gate (promotes S14 to an error so the overflow footgun cannot
  ship as a tolerated warning), plus the model / `disallowed-tools` skill conventions.
- **`.claude/rules/skill-conventions.md`** — corrected the optional-frontmatter guidance
  that recommended `sonnet` on skills (the S14 root cause) to mandate `inherit` on inline
  skills and document the `disallowed-tools` field.

### Notes

- `capabilities: [...]` on the 3 agents was checked against `--strict`: **not flagged**
  (the validator tolerates extra YAML keys), so per the rollout decision rule it was left
  in place. It is harmless prose, though not a documented agent frontmatter field.

### Bumped

- Plugin `0.1.2` → `0.2.0`. All 8 skill versions unchanged at this layer (frontmatter-only
  change). Root `marketplace.json` entry `0.1.2` → `0.2.0` and `metadata.version`
  `1.15.19` → `1.15.20`.

## [0.1.2] - 2026-06-13

Prose patch — track the `drupal-dev-framework` → `ai-dev-assistant` rename.

### Changed
- Namespace references updated: "a contribution **is** a `drupal-dev-framework` (DDF)
  task" → "an `ai-dev-assistant` task"; the DDF nickname → "the framework"; interop +
  troubleshooting table cells and the `CONVENTIONS.md` delegate line now name
  `ai-dev-assistant`. No functional change — this plugin never invoked
  `/drupal-dev-framework:*`; it stays Drupal-domain, layered on the (now stack-neutral)
  ai-dev-assistant lifecycle.

## [0.1.1] - 2026-05-22

First post-release bug-fix patch. Five gaps surfaced by the first live `setup`→`issue`
flow, all in how the plugin explained the `mglaman/drupalorg-cli` toolchain and its
prerequisites. Bundled into one patch because they share the same files.

### Fixed

- **B1 — `drupalorg-cli` was unexplained.** Three skills wrapped the tool but the
  plugin never said what it is or how to install it. Added
  `skills/drupal-ai-contrib/references/drupalorg-cli.md` as the single source of truth
  (what it is, PHAR install, Composer-global path + `PATH` note, authentication, what
  the CLI can and cannot do). `setup` / `issue` / `submit` cite it; the umbrella skill
  lists it.
- **B2 — Executable named wrong.** Skills said *"wrap `drupalorg-cli`"* but the binary
  on `PATH` is `drupalorg` (`drupalorg-cli` is only the package name). All wrap sites,
  troubleshooting rows, and README/CONVENTIONS now name `drupalorg` as the executable.
- **B3 — `submit` overstated CLI capability.** §4 was titled "Create or update the MR
  — via drupalorg-cli", but there is no `mr:create`. Rewritten to state the real flow:
  on GitLab, MRs are created by pushing the issue-fork branch; `submit` uses
  `mr:list` / `mr:status` to confirm and report.
- **B4 — `setup` never guided on auth.** New `contribution-setup` §5 "Check
  contribution credentials" — detects the drupal.org SSH key
  (`ssh -T git@git.drupal.org`), explains plainly that `git push` to issue forks and
  `/do:` bot commands need a key registered on the contributor's account, distinguishes
  read ops (public APIs) from write ops, guides registration at *drupal.org → My
  account → SSH keys*, and reports status — never blocks. §7 Report now states
  ready vs. needs-action per item. `issue` and `submit` gained matching troubleshooting
  rows for push-rejected.
- **B5 — `issue` claimed it could create issues.** `drupalorg-cli` has no
  `issue:create` (verified against repo source — all 19 `Issue/*` command classes
  operate on existing issues). `issue` §3 now states this explicitly: the skill drafts
  the issue and guides the contributor to file it in the web UI (Drupal.org queue or
  GitLab), then resumes with the new issue ID.
- **Reference subcommand list de-brittled.** The initial hand-enumerated table had
  already missed `issue:fork`. Replaced with command-*groups* + verified negatives
  (no `issue:create`, no `mr:create`) + a `drupalorg list` pointer — evidence over
  assertion.

### Verified

- drupalorg-cli command set verified against the live repo source
  (`gh api repos/mglaman/drupalorg-cli/contents/src/Cli/Command/*`): 19 `Issue/*`
  classes (all on existing issues — no `Create`); 5 `MergeRequest/*` classes
  (no `Create`). Confirms B3 + B5.

### Bumped

- Plugin `0.1.0` → `0.1.1`. Skill versions for the four edited skills
  (`contribution-setup`, `contribution-issue`, `contribution-submit`, umbrella
  `drupal-ai-contrib`) `0.1.0` → `0.1.1`. Root `marketplace.json` `metadata.version`
  `1.15.2` → `1.15.3`.

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
