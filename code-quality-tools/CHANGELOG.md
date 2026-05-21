# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.6.1] - 2026-05-20

### Fixed

- **`README.md` and `commands/setup.md` no longer install the abandoned `sebastian/phpcpd`.** Both manual-install / Quick Install blocks listed `sebastian/phpcpd`, which is marked **abandoned** on Packagist (Sebastian Bergmann archived phpcpd) — so following the README or running `/code-quality:setup` Quick Install produced a Composer deprecation warning. Switched both to the maintained community fork `systemsdk/phpcpd`, which the plugin's own `scripts/core/install-tools.sh`, `scripts/drupal/dry-check.sh`, CI template, and `references/dry-detection.md` already use. The fork is a drop-in replacement — same `vendor/bin/phpcpd` binary and CLI flags — so no script or command logic changed.

Marketplace metadata bumped 1.14.54 → 1.14.55.

## [3.6.0] - 2026-05-20

### References & loose ends

Final release of the modernization roadmap — the LOW-priority gaps and ride-along capability items from the 2026-05-12 deep dives. All doc-currency edits; no behavior change to scripts, hooks, or audit logic.

### Changed

- **Hook exec form** — the skill-scoped `FileChanged` hook (`SKILL.md` frontmatter) and the worked-example snippet in `references/post-batch-aggregation.md` migrated to exec form (`"args": []`), completing deep-dive item 2.1 begun in v3.5.0 (`PreCompact`).
- **`references/post-batch-aggregation.md`** — the `if`-Bash footnote refreshed against the current Hooks Reference: the rule matches each subcommand after leading `VAR=value` assignments are stripped, and the hook always runs when the command is too complex to parse. Semantics verified unchanged; stale date attribution dropped.
- **`references/scheduled-sweeps.md`** — new "Autonomous & headless runs" section: the built-in **Proactive** output style suits `/goal`-driven loops (mirrors auto mode without changing permission mode; the plugin ships no output style of its own); and a `--dangerously-skip-permissions` advisory — it activates `bypassPermissions`, which skips all prompts including writes to `.git`/`.claude`/`.vscode`/`.idea`/`.husky` (root/home removals still circuit-break), disableable via `permissions.disableBypassPermissionsMode`.
- **`commands/audit.md`, `commands/security.md`** — "run in the background" notes: `claude --bg`, monitor with `claude agents`, pull output with `claude logs <id>`.
- **`commands/security-debate.md`, `commands/architecture-debate.md`** — "Teammate model & monitoring" note: `teammateDefaultModel` is the global lever (per-spawn `Model:` overrides it); watch teammates with `claude agents` / `/tasks`; do not background a whole debate (`claude --bg`) — the worktree-of-worktrees + permission-auto-deny interaction is untested, run debates in the foreground.
- **`commands/ultrareview.md`, `commands/review.md`** — See-also entry for `claude --from-pr <number>` (resumes the Claude Code session linked to a PR; distinct from `/ultrareview <PR>`, which clones a PR fresh).
- **`README.md`** — note that plugin command/skill visibility is managed via `/plugin`; plugin skills are not affected by the `skillOverrides` setting, and slash commands are not skills.
- **`CONVENTIONS.md`** — Skills checklist gains the `maxSkillDescriptionChars` (1,536 default) cap; Agent Frontmatter Limitations gains the Subagents-guide detail (`name` → `agent_type` for hooks; `permissionMode`/`hooks` ignored for plugin subagents; "what loads at startup"); the `/loop` section gains a `/goal` condition-checked-loop pointer.

### Not done (intentional)

- `agentProgressSummaries` (capability item 4) — not documented in any cached Claude Code guide; dropped rather than guessed. `teammateDefaultModel` (a confirmed setting) and Agent View monitoring cover the same need.
- `SKILL.md` body trim — at 303 lines it trips the validator's S10 hub-skill nudge (an accepted carve-out, not a defect; shipped at 286–303 since v3.3.0). Trimming is outside the roadmap's scope for this release; left as an optional future follow-up.

Marketplace metadata bumped 1.14.53 → 1.14.54. This completes the v3.3.0 → v3.6.0 modernization roadmap.

## [3.5.0] - 2026-05-20

### Adaptive depth & autonomous remediation

Third release of the modernization roadmap. Three additive items — effort-scaled audit depth, `/goal`-driven autonomous loops, and a `Setup`-hook CI-bootstrap reference. No behavior change to scripts, hooks, or audit logic.

### Added

- **Adaptive audit depth (`${CLAUDE_EFFORT}`)** — `skills/code-quality-audit/SKILL.md` gains an "Adaptive Audit Depth" section that scales the audit to the session effort level: `low` → fast lint only, `medium` → lint + coverage + SOLID/DRY, `high` → full audit (the effective default), `xhigh`/`max` → full audit + a `/code-quality:security-debate` offer. An unset/unrecognized level falls back to `high` — depth never silently drops because the level could not be read. `commands/audit.md` carries a prose "Adaptive Depth" pointer to the ladder. **Pilot scope (v3.5.0):** wired into the audit flow only — `lint-changed.sh` and per-command effort gates are deliberately left for a later "broaden" cycle once the pilot is observed. *Grounding note:* the cached Skills guide documents `${CLAUDE_EFFORT}` strictly as a **skill-content** string substitution; it is therefore placed in `SKILL.md` (skill content), and `audit.md` uses a plain-prose behavioral instruction rather than the literal token, which the guides do not support inside slash-command bodies.
- **`/goal` autonomous loops** — `commands/tdd.md` gains a "Drive the GREEN phase with `/goal`" subsection (worked condition, transcript-checkable end-state rule, trust/`disableAllHooks`/`allowManagedHooksOnly` requirements); `commands/audit.md` gains an "Autonomous remediation with `/goal`" subsection (fix-verify-fix loop paired with `--json` as the proof step). Both state plainly that `/goal` is an interactive / headless-`-p` convenience and **not** a CI gate — the CI primitives remain `audit --json` and `claude ultrareview --json`.
- **`skills/code-quality-audit/references/setup-hook-pattern.md`** — new reference documenting the `Setup` hook event (fires on `--init-only` / `--init -p` / `--maintenance -p`; `init`/`maintenance` matcher; `trigger` field; cannot block; `command`/`mcp_tool` handlers only) as the one-time CI tool-bootstrap pattern. Exec form (`args` array). Opt-in, **not shipped** — honest about the Hooks Reference caveat that `Setup` never fires on a normal launch (first-use detection stays the fallback) and that `${CLAUDE_PLUGIN_ROOT}` resolves only in plugin-shipped hooks, not a project's own `settings.json`. Corrects the capability-analysis `args: ["--ci"]` example — `install-tools.sh` takes no positional arguments (it is env-var driven).

### Changed

- **`skills/code-quality-audit/references/scheduled-sweeps.md`** — the `/loop` section now distinguishes `/loop` (time-interval re-run) from `/goal` (condition-checked re-run); neither is a CI primitive.
- **`skills/code-quality-audit/SKILL.md`** — `setup-hook-pattern.md` added to the References list; skill `version` 3.4.0 → 3.5.0.
- **`hooks/hooks.json`** — the `PreCompact` command hook migrated to exec form (`"args": []`), the Hooks Reference's preferred form for any hook referencing a `${CLAUDE_PLUGIN_ROOT}` path placeholder. Surfaced as a validator H05 warning; fixed here to keep the release gate clean. (The skill-scoped `FileChanged` hook and the `post-batch-aggregation.md` example snippet — the rest of deep-dive item 2.1 — remain queued for v3.6.0.)

Marketplace metadata bumped 1.14.52 → 1.14.53.

## [3.4.0] - 2026-05-20

### LSP code intelligence

Marquee release of the modernization roadmap: the SOLID, DRY, and review commands can now use Claude Code's built-in **LSP tool** for language-server semantics instead of grep heuristics — converting the plugin's biggest documented weakness (grep blindness on inherited, interface-wired, and config-wired relationships) into a strength, while reducing token cost (no more full-file reads as the default). Ships **recommended-not-required**: every command degrades cleanly to the existing full-file-read Type-B pass when no code-intelligence plugin is present.

### Added

- **`skills/code-quality-audit/references/code-intelligence.md`** — new reference: what the LSP tool provides (definitions, references, find-implementations, call-hierarchy, list-symbols, automatic post-edit diagnostics), how to enable it (`php-lsp`→`intelephense`, `typescript-lsp`→`typescript-language-server`, installed from the official marketplace), per-command leverage, and the honest caveats — LSP availability varies by language/environment, Drupal `.module`/`.inc`/`.theme` files carry non-`.php` extensions that `intelephense` may not index by default (the grep-free full-read pass stays the guaranteed floor there), plus large-project memory and monorepo false-positive notes.

### Changed

- **`commands/solid.md`, `commands/dry.md`, `commands/review.md`** — each gains an "LSP Code Intelligence (recommended)" section: `solid` uses `find-implementations` for genuine Liskov/ISP checks, `find-references` for Dependency Inversion, and `call-hierarchy` for Single Responsibility fan-in/fan-out; `dry` uses `find-references` to catch semantic duplication that textual clone detectors (PHPCPD/jscpd) miss; `review` uses `call-hierarchy` and reference resolution to ground the *Separation of concerns* and *Testability* rubric categories in evidence. Each block instructs an explicit fall-back to the full-file-read pass when no LSP plugin is installed.
- **`commands/setup.md`** — new "Code Intelligence Plugins (recommended)" section with the plugin/binary install table; code intelligence added to the Tool Categories list.
- **`skills/code-quality-audit/SKILL.md`** — the reading-strategy note now points at the LSP tool for inherited/wired relationship questions; `references/code-intelligence.md` added to the References list. Skill `version` 3.0.0 → 3.4.0.
- **`README.md`** — optional code-intelligence install note added under First-Time Setup.
- **`plugin.json` / `marketplace.json` descriptions** — added "optional LSP code-intelligence" to the capability summary (still under the 600-char cap).

The `LSP` tool is **not** added to any command or skill `allowed-tools` — it requires no permission and is inert without a code-intelligence plugin, so listing it would imply a hard dependency that does not exist. Shipping `lspServers` in the plugin manifest is intentionally out of scope (a future consideration, not a currency item). `architecture-debate.md` is unchanged this release. No behavior change to scripts, hooks, or audit logic.

Marketplace metadata bumped 1.14.51 → 1.14.52.

## [3.3.0] - 2026-05-20

### Validator hygiene & the ultrareview CLI gap

Currency + correctness pass: makes the plugin pass the `plugin-creation-tools` v3.7.x validator clean and closes the one HIGH gap from the 2026-05-12 deep dive — the non-interactive `claude ultrareview` subcommand.

### Fixed (validator FM01 errors — pre-existing breakage)

- **`commands/audit.md`, `commands/security.md`, `commands/review.md`** — the `argument-hint` values contained unquoted `[...]` / `<...>` brackets, which broke the **entire** YAML frontmatter block. Each command was loading with **no `description` and no `allowed-tools`** at runtime. Quoted all three values. Surfaced by `/plugin-creation-tools:validate`.

### Changed

- **`commands/ultrareview.md`** — new "CI / Headless Mode" section documenting the `claude ultrareview` CLI subcommand: no-arg / PR-number / base-branch invocation forms, `--json` and `--timeout` flags, the exit-code contract (`0` complete, `1` failure/timeout, `130` interrupt), stdout/stderr split, a CI gating snippet, and cost discipline (a failed or stopped run still consumes a free run — reserve for release branches). Step 4's "a command body cannot invoke another slash command" note is corrected: it holds for the *slash* command, but the CLI subcommand is Bash-invokable. Grounded in the Ultrareview guide §"Run ultrareview non-interactively".
- **`commands/ultrareview.md`** — `/extra-usage` renamed to `/usage-credits` (upstream rename, v2.1.144); `argument-hint` quoted.
- **`commands/audit.md`** "Wire to CI" — cross-references the headless `claude ultrareview --json` release-gate path alongside the local `audit --json` per-push gate.
- **`skills/code-quality-audit/references/premerge-gate-routine.md`** — "See also" cross-references the `claude ultrareview` CLI subcommand as a routine-free verified-findings gate.
- **Plugin-root `CLAUDE.md` → `CONVENTIONS.md`** (validator rule ST03) — a plugin-root `CLAUDE.md` is not loaded as end-user context and trips both `claude plugin validate` and the v3.7.x validator. Content unchanged; only the filename changed. The one internal pointer (`post-batch-aggregation.md`) was updated. Matches the drupal-dev-framework v4.6.0 precedent.
- **`plugin.json` and `marketplace.json` descriptions** — replaced the multi-version changelog narrative (~1,800 / 1,858 chars) with a stable ~450-char capability summary (validator rule X02; marketplace cap is 600 chars). Version history stays here in `CHANGELOG.md`.
- **`plugin.json`** — added the `$schema` field (`https://json.schemastore.org/claude-code-plugin-manifest.json`) for editor autocomplete; ignored by Claude Code at load time.

Marketplace metadata bumped 1.14.50 → 1.14.51. No behavior change to scripts, hooks, or audit logic.

## [3.2.1] - 2026-05-19

### Paper-test fixes for `github-drupal-pr.yml`

Five bugs surfaced by an inline paper-test of the v3.2.0 PR workflow. All in `skills/code-quality-audit/templates/ci/github-drupal-pr.yml`; no other files changed.

- **CRITICAL: Backtick command substitution in PR-comment footer.** The footer line `echo "_… see \`.reports/\` for raw JSON._"` was double-quoted, so bash interpreted the backticks as command substitution and tried to execute `.reports/` as a command. The footer rendered as `… see  for raw JSON.` plus a stderr line in Actions logs. Switched to single-quoted echo with literal markdown backticks.
- **CRITICAL: Semgrep step was unscoped.** The previous step used `semgrep/semgrep-action@v1` with `SEMGREP_TARGETS_FILE` and `SEMGREP_JSON_OUTPUT` env vars — neither of which the action honors. Semgrep was silently scanning the entire repo, but its output went to the action's own location, not `.reports/semgrep.json`, so the synthesis step's jq fallback returned 0 for every PR and the security gate was a no-op. Replaced with a direct `semgrep` CLI invocation (installed via `pip install semgrep`) that takes the changed-file list as positional args and writes JSON to the expected path.
- **HIGH: xargs multi-batch overwrite in phpcs/phpstan.** Large PRs (100+ files) could push `xargs` past `ARG_MAX`, triggering multiple command invocations. For phpcs, each invocation's `--report-file=.reports/phpcs.json` overwrote the previous batch's results → only the last batch's findings survived. For phpstan, concatenated JSON documents on stdout produced invalid JSON downstream. Switched both to single invocations via `$(cat .changed-files.txt)`; documented the shellcheck SC2046 suppression.
- **HIGH: `composer require --dev` ran on every PR.** Previous step installed phpstan/phpstan-drupal/extension-installer/drupal/coder on every PR run, wasting 30-60s of CI per run and risking transient resolver conflicts. Replaced with a comment instructing users to add these tools to `composer.json` as dev dependencies once locally.
- **MEDIUM: PHPCS jq counts now read `.totals`.** Switched `.files[]?.errors`/`.warnings` array-sums to `.totals.errors` and `.totals.warnings` — phpcs already aggregates at the totals level, simpler and more robust to shape changes. Also fixed `(.results | length) // 0` precedence in the Semgrep total count.

No behavior change to `github-drupal.yml`, `grumphp.yml`, or `commands/setup.md`. Marketplace metadata bumped 1.14.36 → 1.14.37.

## [3.2.0] - 2026-05-19

### PR-time review surfaces (CI workflow split + optional pre-commit hook)

Two new opt-in surfaces for reviewing code at PR time without adding noise to existing audits. All three CI/hook surfaces (the existing full-tree workflow, the new PR workflow, and the new pre-commit hook) are independently opt-in — install whichever fit the team.

**New: `skills/code-quality-audit/templates/ci/github-drupal-pr.yml`** — GitHub Actions workflow scoped to `pull_request` only. Computes changed PHP files via `git diff --diff-filter=ACMR base...head` (excludes `vendor/`, `node_modules/`, `web/core/`, contrib), then runs phpcs + phpstan + Semgrep against the changed list only. Builds a /50 rubric score, posts a **sticky PR comment** (`marocchino/sticky-pull-request-comment@v2`) with synthesis table + gate verdict, and uploads raw JSON as an artifact. Soft-nudge gate by default; repo Variable `FAIL_ON_GATE=true` enforces hard fail on rubric < 35 OR any high/critical Semgrep finding. Sibling to the existing `github-drupal.yml` (full-tree on push/PR), which is unchanged.

**New: `skills/code-quality-audit/templates/grumphp.yml`** — pre-commit hook template. phpcs (Drupal,DrupalPractice) + phpstan, both `context: git-staged-files`, so the hook only checks files staged for the current commit. Intentionally excludes phpcpd (directory-scoped, slow), phpunit (full suite — keep in CI), phpmd (noisy on legacy code; opt-in via template edit).

**Updated: `commands/setup.md`** — wizard now prompts "Install GrumPHP git hooks to lint staged files on every commit? [y/N]" (default No). On yes: runs `ddev composer require --dev phpro/grumphp`, copies the template, runs `vendor/bin/grumphp git:init`, and verifies with an empty commit. Re-runs of `/code-quality:setup` only re-ask when hooks aren't already installed. Setup also now documents the two GitHub Actions templates as the CI alternative.

**Updated: `README.md`** — new "CI & Git Hooks (opt-in)" section above "Watch-mode & Scheduled Sweeps" with a comparison table for the two workflow templates, the `FAIL_ON_GATE` env var, and manual install steps for GrumPHP.

No behavior change to existing commands or hooks. Existing `templates/ci/github-drupal.yml` is unchanged.

## [3.1.1] - 2026-04-27

### Skill visibility hygiene (Tier 2 of multi-plugin command-naming research)

Set `user-invocable: false` on `skills/code-quality-audit/SKILL.md` (was explicit `true`). The umbrella skill was substring-matching `/audit` and `/code` in the typeahead, but the user-facing entry points are the slash commands (`/code-quality:audit`, `:review`, `:security`, `:solid`, `:dry`, `:tdd`, etc.) — the skill itself is plugin-internal context.

Per `Comprehensive Guide Skills in Claude Code.md` line 290 + 496: `user-invocable: false` controls menu visibility only; Claude can still invoke the skill autonomously, and parent commands can still load it via the Skill tool. No behavior change.

## [3.1.0] - 2026-04-27

### 2026-04-25 doc-refresh deltas

Closes the 2026-04-25 Claude Code doc-refresh deltas affecting this plugin (snapshot pinned at upstream commit `c142d14`, covers Claude Code releases 2.1.116–2.1.119). Additive throughout — no behavior change to existing audits, commands, or hooks.

### Added
- **`PostToolBatch` aggregation pattern reference** — new `skills/code-quality-audit/references/post-batch-aggregation.md` documents how to aggregate findings across a batch of parallel lint/audit tool calls into a single summary using the new `PostToolBatch` hook (Claude Code 2.1.118+, Hooks Reference). Includes worked example with a project-local `hooks.json` snippet + aggregator script. Plugin does **not** ship the hook by default — `PostToolBatch` lacks skill-scoping and a matcher field, so a plugin-scoped hook would fire across every conversation. Users copy the snippet into their own project's `hooks.json` if they want it. Tracked as a future avenue if upstream gains skill-scoping.
- **Reading-strategy callouts** in `commands/audit.md`, `commands/review.md`, `commands/security.md`, `commands/solid.md`, `commands/dry.md` and the skill body (`skills/code-quality-audit/SKILL.md`) — explicit Type-B (full-read, no grep-first) discipline citing `https://camoa.github.io/dev-guides/development/reading-strategy/` via `dev-guides-navigator`. Inherited methods, annotations, and config-wired classes are invisible to grep — audit/review/security/SOLID/DRY commands must read full files.
- **Debug Your Config cross-link** in `skills/code-quality-audit/references/troubleshooting.md` — symptom-first reference to upstream `/context`, `/memory`, `/doctor`, `/hooks`, `/mcp`, `/skills`, `/permissions`, `/status` slash commands for diagnosing plugin/hook/MCP load issues. Plugin's own troubleshooting handles tool-installation issues; platform-level issues route upstream.
- **`if`-Bash subcommand clarification** documented inline in `post-batch-aggregation.md` — `Bash(rm *)` matches `FOO=bar rm file` and `npm test && rm file` (per Hooks Reference 2026-04-25 clarification). There is no `&&`/`||` in `if` — register separate handlers for compound conditions.

### Changed
- `skills/code-quality-audit/SKILL.md` line count remains under the 500-line soft cap.

### Out of scope (deferred)
- **OTEL span instrumentation** — no current OTEL surface in this plugin. The 2026-04-25 Monitoring docs added a full span-attribute schema (gated behind `ENABLE_BETA_TRACING_DETAILED=1`); evaluating an instrumentation pass for `/code-quality:audit` and `/code-quality:security` deferred to a later cycle.
- **JSON schema v2** — existing v1 contracts are stable; no breaking changes warranted by the doc refresh.
- **Default-on `PostToolBatch` hook** — until upstream adds skill-scoping or a matcher field, plugin-scoped is too noisy. Documented optional pattern only.

## [3.0.0] - 2026-04-20

### Added
- **REVIEW.md v2 injection-model generator** — `/code-quality:generate-review-md` now emits the injection-model structure (severity overrides, nit caps, skip directives, mandatory-check lists, verification bar, summary-format directives). Starter templates for Drupal and Next.js in `references/review-md-v2.md`.
- **`/code-quality:ultrareview` command** — wrapper around the built-in `/ultrareview` with pre-flight platform compatibility check (fails cleanly on Bedrock/Vertex/Foundry/ZDR), cost transparency notice (Pro/Max 3 free one-time then $5–$20 per run; Team/Enterprise all paid as extra usage), and GitHub remote check for PR mode.
- **Skill-scoped `FileChanged` hook** — watch-mode linting runs only when the `code-quality-audit` skill is active. Matcher covers common linter-config files (composer.json, package.json, phpstan.neon*, psalm.xml, eslint.config.*, tsconfig.json). Dispatches to `hooks/lint-changed.sh` which runs PHPStan (via DDEV) or ESLint per project type. Force-disable mid-session with `CLAUDE_CODE_QUALITY_WATCH=0`.
- **Skill-scoped `PermissionDenied` hook** — returns `{retry: true}` scoped to `Read|Grep|Glob` (non-destructive) so audit flows don't stall on auto-mode classifier denials for read-only tools.
- **Scheduled quality sweep templates** — Desktop Scheduled Task template (primary, local files + DDEV access, 1-min interval) in `references/desktop-sweep-template.md`; Cloud Routine fallback with full footgun list in `references/cloud-routine-sweep.md`; surface comparison with decision tree in `references/scheduled-sweeps.md`.
- **API-triggered pre-merge gate** — Cloud Routine template with `curl` example, GitHub Actions and GitLab CI snippets, bearer-token lifecycle and daily-cap guidance in `references/premerge-gate-routine.md`.
- **Check-run JSON consumption** — `gh`+`jq` parsing pattern with a starter GitHub Actions quality-gate workflow that fails merge when `normal > 0`. Documents that the JSON `normal` key corresponds to the UI's "Important" severity (backwards compat). See `references/check-run-json.md`.
- **`--json` CI mode** on `/code-quality:audit`, `/code-quality:review`, and `/code-quality:security` — emits a stable schema v1.0 JSON document on stdout for CI gating. Schemas documented in `references/json-schemas.md`. Scoped to these three commands only; `/lint`, `/coverage` already emit tool-native JSON, `/solid`, `/dry`, `/tdd` are interactive.

### Changed
- **Severity label** — Code Review's human-facing "Normal" renamed to **"Important"** across `/review` and related docs. JSON key stays `normal` for backwards compatibility.
- **`REVIEW.md` authoring model** — REVIEW.md is now the highest-priority system-prompt injection block, not additive guidance. The generator output structure has been rewritten; the previous additive format is semantically dead.
- **SKILL.md `model: sonnet`** declared explicitly in frontmatter.
- **Version drift fixed** — `skills/code-quality-audit/SKILL.md` was at 2.7.0 while `plugin.json` was at 2.10.0; both now at 3.0.0 along with marketplace.json.

### Hardened (from cold-agent paper test — Happy Path + Edge Case + Red Team)
- `hooks/lint-changed.sh` tolerant of malformed JSON and missing `jq` (dropped `set -e`; explicit fallbacks). Refuses to lint absolute paths outside `$cwd`.
- `FileChanged` matcher expanded to common real-world variants (`phpstan.dist.neon`, `phpcs.xml*`, `.eslintrc.{js,yml,yaml}`, `eslint.config.cjs`, `psalm.xml.dist`) — matcher is literal per Hooks Reference, so unlisted variants silently failed to fire.
- `/ultrareview` pre-flight uses `is_truthy` helper; explicit documentation that Foundry / ZDR / API-only auth are not locally detectable and fail at session launch.
- `check-run-json.md` parser uses `split(…) | last` (not `[1]`) to defend against fake `bughunter-severity:` markers echoed earlier in check-run text. Workflow blocks merge on missing or malformed marker instead of failing-open.
- `json-schemas.md` declares four CI invariants: `findings` always `[]` on zero findings; `status` is `warning` (never `pass`) when no tools ran; `schema_version` follows semver; string fields JSON-escaped.
- `commands/audit.md` and `commands/security.md` use `${CLAUDE_PLUGIN_ROOT}` for script paths (CWD-independent).
- `premerge-gate-routine.md` treats POST-body `text` as untrusted data (extract-digits-or-abort); shell snippets use `jq -nc --arg` to build request body safely; HTTP error-code recovery table added (429/401/404/5xx).
- `generate-review-md.md` documents the REVIEW.md trust boundary — CLAUDE.md / rules files may come from hostile clones; never paste verbatim.
- `desktop-sweep-template.md` flags `Ask` permission mode as a stall risk for scheduled runs.
- `cloud-routine-sweep.md` prompt adds Gitleaks secret-redaction before Slack posting.

## [2.10.0] - 2026-04-08

### Changed
- **PreCompact hook** — No longer dumps audit report content into compaction. Now outputs instructions for Claude to read `.reports/` files on demand, reducing compaction bloat.

## [2.9.0] - 2026-03-20

### Added
- **`/code-quality:generate-review-md` command** — Analyzes codebase patterns (linter configs, CLAUDE.md rules, CI config, git history) and generates a `REVIEW.md` for Claude Code's managed Code Review service. Supports Drupal, Next.js, React, Python, and general projects. Detects existing conventions to avoid duplication. Produces Always Check, Style, Security, and Skip sections.
- **`/loop` patterns documented** in CLAUDE.md — Shows how to use Claude Code's built-in `/loop` for recurring quality checks: `/loop 30m /code-quality:lint`, `/loop 1h /code-quality:security`. Session-scoped, 3-day auto-expiry.
- **SKILL.md** updated with `/code-quality:generate-review-md` in Quick Commands list.

## [2.8.0] - 2026-03-20

### Added
- **`/simplify` distinction note** in SKILL.md: Documents how Claude Code's built-in `/simplify` differs from `/code-quality:review` (rubric scoring, quality gate, persisted report vs quick ad-hoc feedback)
- **`effort: high` on all debate agents**: All 6 agent spawn prompts in `security-debate.md` and `architecture-debate.md` now declare `effort: high` for deeper analysis
- **`StopFailure` hook guidance** in CLAUDE.md: Documents how users can configure the `StopFailure` event in their project's `.claude/hooks.json` for CI failure alerting (e.g., Slack webhook on audit failure)
- **`REVIEW.md` convention** in `commands/review.md`: Documents that a `REVIEW.md` file at project root customizes Claude's review behavior, consistent with Claude Code's Code Review feature
- **Sandbox path whitelisting note** in SKILL.md: Guidance for users with sandbox mode enabled — linter binaries (PHPStan, ESLint, Semgrep, Trivy, Gitleaks) must be whitelisted; DDEV-proxied commands are unaffected
- **Agent frontmatter limitations note** in CLAUDE.md: Clarifies that `hooks`, `mcpServers`, and `permissionMode` are not valid in agent spawn prompt blocks and will be silently ignored

## [2.7.1] - 2026-03-15

### Added
- **PreCompact hook**: Preserves audit context (report paths, synthesis, review scores, debate results) before conversation compaction

## [2.7.0] - 2026-03-13

### Added

**Track A — Approach Improvements**
- **`/code-quality:review`** — Rubric-scored code review with 10-category assessment (Content + Structure), /50 scale, quality gate (PASS 35+/FAIL)
- **`/code-quality:architecture-debate`** — 3-agent architecture debate (Pragmatist + Purist + Maintainer) with isolated worktrees and quality gate enforcement
- **Cross-audit synthesis** in `/audit` — correlates findings across tools into hot spots, cross-category risks, and prioritized action plan (`.reports/audit-synthesis.md`)

**Track B — Agent Team Enhancement**
- `maxTurns: 10` on all security-debate agents (cost control)
- `isolation: worktree` on all security-debate agents (independent analysis)
- Scoped tool access per agent (Defender: read-only, Red Team: +WebSearch, Compliance: +WebFetch)
- Quality gate enforcement on debate agents (must address ALL findings)

### Changed
- Removed experimental agent teams flag — agent teams are now GA
- SKILL.md version 2.5.0 → 2.7.0 (aligned with plugin), added `allowed-tools`, `user-invocable`
- Pushy descriptions with comprehensive trigger phrases on skill and all 11 commands
- `/setup` implementation note updated (Claude-driven, no external script dependency)
- CLAUDE.md expanded with capabilities list and updated conventions

---

## [2.6.0] - 2026-02-16

### Changed
- **Dev-guides integration v2**: Replaced 45-entry keyword→URL mapping table in SKILL.md with lightweight `llms.txt` discovery + topic hints
- **CLAUDE.md**: Added Online Dev-Guides section with `llms.txt` index URL and topic hints for session-wide awareness

## [2.5.0] - 2026-02-15

### Added
- Online dev-guides integration for Drupal domain knowledge (SOLID, DRY, security, testing, TDD)
  - SKILL.md: 45-entry keyword→URL mapping table for WebFetch from https://camoa.github.io/dev-guides/
  - Topics: SOLID principles (19 guides), DRY principles (16 guides), Security (20 guides), Testing (11 guides), TDD (25 guides), JS testing/security, CI/CD
- Security debate enrichment: Step 3b fetches relevant online security guides (OWASP, XSS, SQLi, CSRF, access control) before spawning debate team
- "See also" pointers in solid-detection.md, dry-detection.md, drupal-security.md, tdd-workflow.md, coverage-metrics.md, test-type-selection.md, quality-audit-checklist.md linking to online guides

### Changed
- Security debate spawn prompts now include `security-context.md` path for enriched Drupal context

---

## [2.4.0] - 2026-02-11

### Added
- `/code-quality:security-debate` command — multi-perspective security debate using agent teams
  - Defender agent validates findings, identifies false positives and exploitability
  - Red Team agent constructs attack scenarios, finds gaps audit missed
  - Compliance Checker agent maps to OWASP Top 10 / CWE standards with coverage matrix
  - Cross-challenge debate phase resolves severity disagreements
  - Synthesized output: `.reports/security-debate.md`
- Agent team command convention in CLAUDE.md and command-conventions.md

### Fixed
- `commands/security.md` — corrected report filename from `.reports/security.json` to `.reports/security-report.json`
- `commands/security.md` — added discoverability link to `/code-quality:security-debate`

---

## [2.3.0] - 2026-02-09

### Added
- `model: sonnet` routing on code-quality-audit skill for cost optimization
- `CLAUDE.md` plugin conventions file
- `.claude/rules/skill-conventions.md` for path-scoped skill standards
- `.claude/rules/command-conventions.md` for path-scoped command standards

### Changed
- Aligned with camoa-skills plugin standards (model routing, rules, conventions)
- Version bumped to 2.3.0 across plugin.json, marketplace.json, SKILL.md

---

## [2.2.0] - 2026-01-15

### Added
- **8 Slash Commands** for direct operation access
  - `/code-quality:setup` - Install and configure tools
  - `/code-quality:audit` - Run full audit (all 22 operations)
  - `/code-quality:coverage` - Test coverage analysis
  - `/code-quality:security` - Security scan (10 Drupal layers, 7 Next.js layers)
  - `/code-quality:lint` - Code standards check
  - `/code-quality:solid` - SOLID principles check
  - `/code-quality:dry` - Code duplication detection
  - `/code-quality:tdd` - TDD workflow (test watcher mode)
- **Project Auto-Detection** - Automatically detects Drupal vs Next.js projects
- **Intelligent Error Handling** - Contextual error messages with recovery guidance
- **Troubleshooting Guide** - Common issues and solutions (`references/troubleshooting.md`)
- **marketplace.json** - Enable marketplace distribution

### Changed
- **SKILL.md** - Enhanced description for better auto-discovery
- **SKILL.md** - Added "Quick Commands" section referencing slash commands
- **SKILL.md** - Version updated to 2.2.0
- **README.md** - Added "Quick Start" section with installation and commands table
- **plugin.json** - Version updated to 2.2.0, registered commands directory

### Fixed
- **Discoverability Issue** - Users can now invoke operations via commands without relying on skill auto-discovery
- **Setup Clarity** - Clear installation instructions in README Quick Start section

### Technical
- New scripts: `detect-project.sh`, `error-handler.sh`
- Commands registered in `plugin.json`
- All changes non-breaking - v2.1.0 workflows continue unchanged

## [2.1.0] - 2025-12-19

### Added
- **Operation 22: DAST Tools (Optional)** - Dynamic Application Security Testing
- `references/operations/dast-tools.md` - Complete DAST documentation (585 lines)
- **OWASP ZAP** integration - Full DAST scanner for pre-production
  - Active scanning (SQL injection, XSS, command injection)
  - Passive scanning (security headers, sensitive data)
  - Spider/crawler for endpoint discovery
  - Authentication testing support
- **Nuclei** integration - Template-based CVE scanning
  - 1000+ vulnerability templates
  - CVE detection (2015-2025)
  - Misconfiguration detection
  - Exposed panel detection
- CI/CD integration examples (GitHub Actions, GitLab CI)
- Pre-release security checklist script
- Docker-based installation instructions

### Documentation
- SAST vs DAST comparison guide
- When to use DAST (staging, pre-production, security audits)
- Installation guides (Docker, direct install, package managers)
- Usage examples for both tools
- Report interpretation guidelines
- Best practices and troubleshooting

## [2.0.0] - 2025-12-19

### Major Refactoring
- **Progressive Disclosure**: SKILL.md reduced from 632 to 234 lines (63% reduction)
- Created 9 reference files with comprehensive documentation
- Achieved plugin-creation-tools compliance (16/16 criteria)
- Operations reorganized by stack (Drupal: 1-8, 10-12, 20; Next.js: 13-19, 21)

### Added - Phase 1: Cross-Stack Security Tools
- **Semgrep SAST** - Multi-language static analysis
  - 20,000+ security rules for PHP, React, JS, TS
  - OWASP Top 10 coverage
  - Auto-updating rule sets
- **Trivy Scanner** - Comprehensive vulnerability scanner
  - Package vulnerabilities (npm + Composer)
  - Container/IaC misconfigurations
  - Secret detection (800+ patterns)
- **Gitleaks** - Dedicated secret detection
  - 800+ secret patterns
  - Entropy analysis for custom secrets
  - No git required (`--no-git` flag)

### Added - Phase 2: Enhancement Tools
- **Roave Security Advisories** (Drupal)
  - Composer prevention layer
  - Blocks installation of vulnerable packages
  - Integrated into `install-tools.sh` and `security-check.sh`
- **Socket CLI** (Next.js)
  - Supply chain attack detection
  - Malicious package detection
  - Install script analysis
  - Integrated into `install-tools.sh` and `security-check.sh`

### Changed
- **Security Coverage Expanded**:
  - Drupal: 40% → 90% (6 → 10 security layers)
  - Next.js: 0% → 85% (0 → 7 security layers, NEW!)
- **Drupal Security Layers** (10 total):
  1. Drush pm:security
  2. Composer audit
  3. yousha/php-security-linter
  4. Psalm taint analysis
  5. Custom Drupal patterns
  6. Security Review module (optional)
  7. Semgrep SAST
  8. Trivy scanner
  9. Gitleaks
  10. Roave Security Advisories
- **Next.js Security Layers** (7 total):
  1. npm audit
  2. ESLint security plugins
  3. Semgrep SAST
  4. Trivy scanner
  5. Gitleaks
  6. Custom React/Next.js patterns
  7. Socket CLI
- Updated `install-tools.sh`:
  - Drupal: 13 steps (added Roave)
  - Next.js: 11 steps (added Socket CLI)
- Updated security-check.sh scripts with new tools
- plugin.json and marketplace.json descriptions updated

### Documentation
- Created `references/operations/` directory structure
- Split into operation-specific files:
  - drupal-setup.md, drupal-audits.md, drupal-security.md, drupal-tdd.md
  - nextjs-setup.md, nextjs-audits.md, nextjs-security.md, nextjs-tdd.md
- Added `references/scope-targeting.md` (env vars + cd approach)
- All reference files include TOC and cross-references
- Updated SKILL.md with progressive disclosure structure

## [1.8.0] - 2025-12-18

### Added
- **Cross-Stack Security Tools** for both Drupal and Next.js:
  - Semgrep SAST (20,000+ security rules)
  - Trivy scanner (dependency/container/secret scanner)
  - Gitleaks (secret detection with 800+ patterns)
- Integration into security-check.sh for both stacks
- Installation via install-tools.sh

### Documentation
- Added cross-stack tools to SKILL.md
- Updated security documentation for both stacks

## [1.7.0] - 2025-12-18

### Added
- **Operation 20: Security Audit (Drupal)** - Comprehensive OWASP + Drupal security scanning
- `scripts/drupal/security-check.sh` - Multi-tool security audit script
- **Modern Security Stack (2024-2025)**:
  - `yousha/php-security-linter` (PHPCS security - actively maintained Dec 2025)
  - `vimeo/psalm` taint analysis (XSS/SQLi dataflow detection)
  - `drupal/security_review` module integration (v3.1.1)
  - Built-in Drush pm:security (Drupal advisories)
  - Built-in Composer audit (package vulnerabilities)
  - Custom Drupal pattern checks (SQL injection, XSS, deserialization)
- Security report with OWASP 2021 category mapping
- 6-layer security audit approach

### Changed
- Replaced abandoned `pheromone/phpcs-security-audit` (2020) with `yousha/php-security-linter` (2025)
- SKILL.md updated with modern security tools and why old tools are deprecated
- Added security audit to Quick Reference

### Documentation
- Added "Why NOT pheromone/phpcs-security-audit?" section
- Documented modern security stack maintenance status
- Added installation and usage examples for security tools

## [1.6.0] - 2025-12-13 (Not fully tested)

### Added
- **SOLID check for Next.js** with madge circular dependency detection
- Operation 19: SOLID Check (Next.js) - circular deps, complexity, large files, TypeScript strict mode
- `scripts/nextjs/solid-check.sh` - Full SOLID principles analysis
- `madge` npm package for circular dependency detection
- Per-principle status reporting (SRP, OCP, LSP, ISP, DIP)

### Changed
- `full-audit.sh` now runs dedicated SOLID check for Next.js projects (not just lint)
- `install-tools.sh` now installs madge for Next.js projects
- Next.js full audit now runs: coverage → SOLID → lint → DRY (4 checks)
- Added `lint_score` to audit summary for Next.js projects
- `report-processor.sh` now includes Lint Analysis section for Next.js
- SOLID violations now use array format compatible with Markdown generator

## [1.5.0] - 2025-12-12

### Added
- **Full Next.js support** with ESLint, Jest, jscpd tooling
- Operation 11: Lint Check (Drupal) - explicit phpcs operation with `--fix` mode
- Operation 12: Rector Fix (Drupal) - auto-fix deprecations with drupal-rector
- Operations 13-18: Next.js operations (Setup, Full Audit, Lint, Coverage, DRY, TDD)
- Next.js scripts: `scripts/nextjs/lint-check.sh`, `coverage-report.sh`, `dry-check.sh`, `tdd-workflow.sh`
- Next.js templates: `eslint.config.js` (ESLint v9 flat config), `jest.config.js`, `jest.setup.js`, `.prettierrc`
- drupal-rector integration for automated deprecation fixing
- jq dependency check in all scripts

### Changed
- **BREAKING**: Report directory standardized to `.reports/` (was `./reports/quality`)
- `full-audit.sh` now auto-routes to Drupal or Next.js scripts based on project type
- `install-tools.sh` now installs Next.js tools for Next.js projects
- `install-tools.sh` now installs drupal-rector for Drupal projects
- `solid-check.sh` no longer references deprecated drupal-check (PHPStan handles deprecations)
- All 18 operations documented in SKILL.md

### Fixed
- Report directory inconsistency across scripts
- Missing drupal-check in install-tools.sh (replaced with drupal-rector)
- solid-check.sh drupal-check references that would fail

## [1.4.0] - 2025-12-06

### Added
- Operation 10: TDD Workflow with RED-GREEN-REFACTOR guidance using `scripts/drupal/tdd-workflow.sh`
- "When to Run What" section (pre-commit vs pre-push vs pre-merge)
- Coverage targets by code type (services 90%, security 95%, API 85%)
- Rule of Three evaluation in DRY check
- JSON schema enforcement for all reports

### Changed
- **Complete SKILL.md rewrite** in imperative voice (instructions for Claude, not documentation)
- All operations now reference their corresponding scripts
- DRY check includes knowledge vs coincidence evaluation
- Test type selection integrated with decision guide reference
- Composer scripts display is now mandatory

### Fixed
- Scripts were not referenced in operations (Gap 8)
- References and decision guides now integrated inline, not just listed
- JSON schema (`schemas/audit-report.schema.json`) now enforced in all report operations

## [1.3.0] - 2025-12-06

### Added
- Coverage driver preference question in Operation 1 (PCOV vs Xdebug)
- "When to Choose Each" and "Performance When Disabled" sections to coverage-metrics.md
- PHPStan 2.x compatibility note in SKILL.md

### Changed
- **BREAKING**: Updated `phpstan.neon` template for PHPStan 2.x compatibility
  - Removed deprecated `memoryLimit`, `checkMissingIterableValueType`, `checkGenericClassInNonGenericObjectType` parameters
  - Removed `includes:` block (extension-installer auto-loads extensions)
- Fixed `phpmd.xml` template - removed XML comment block that caused parser errors
- Fixed PCOV installation instructions - use version-specific package name (e.g., `php8.3-pcov`)

### Fixed
- PHPStan "files included multiple times" error with extension-installer
- PHPMD "Double hyphen within comment" XML parser error
- PCOV installation failure in DDEV (package name format)

## [1.2.0] - 2025-12-06

### Added
- Operation 7: Add Composer Scripts - adds test/quality scripts to `composer.json`
- New triggers: "Add test scripts to composer", "Add composer scripts", "Setup composer quality scripts"
- Scripts include: test, test:unit, test:kernel, test:coverage, quality:phpstan, quality:phpmd, quality:dry, quality:cs, quality:all, quality:fix

### Changed
- Renumbered operations (CI Integration is now Operation 8, Markdown Report is Operation 9)
- Now 9 operations total (was 8)
- **BREAKING**: Replaced deprecated `mglaman/drupal-check` with `phpstan/phpstan-deprecation-rules`
- Updated all references, scripts, and documentation to use phpstan-deprecation-rules
- Install script now installs 5 tools instead of 6

## [1.1.0] - 2025-12-06

### Added
- `.reports/` directory for all JSON output (git-ignored)
- Operation 8: Generate Markdown Report from JSON
- New reference: `composer-scripts.md` with recommended scripts
- New reference: `json-schemas.md` documenting report structures
- More trigger phrases ("Install testing tools", etc.)

### Changed
- SKILL.md rewritten as Claude instructions (not documentation)
- Each operation now saves JSON reports independently
- Console shows summary, detailed reports saved to files
- Reduced SKILL.md from 612 to 231 lines (moved content to references)

### Fixed
- Skill now properly guides Claude through each operation step-by-step
- Clear separation between setup, individual checks, and full audit

## [1.0.0] - 2025-12-06

### Added
- Initial release of code-quality-audit skill
- Core scripts: detect-environment, install-tools, full-audit, report-processor
- Drupal scripts: coverage-report, solid-check, dry-check, tdd-workflow
- JSON report schema with Markdown conversion
- Templates: phpunit.xml, phpstan.neon, phpmd.xml, GitHub Actions workflow
- References: TDD workflow, SOLID detection, DRY detection, coverage metrics
- Decision guides: test type selection, quality audit checklist
- DDEV integration for all PHP tools
- Environment variable support for threshold customization
