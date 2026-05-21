---
name: code-quality-audit
description: Use when checking code quality, running security audits, testing coverage, finding SOLID/DRY violations, or setting up quality tools. Use when user says "audit this code", "check security", "run PHPStan", "code quality", "find violations", "SOLID check", "DRY check", "test coverage", "lint this", "security review", "is this production ready", "check for vulnerabilities", "code review", "grade this code", "watch mode lint", "deep review", "ultrareview", "schedule quality sweep". Supports Drupal (PHPStan, PHPMD, Psalm, Semgrep, Trivy, Gitleaks via DDEV) and Next.js (ESLint, Jest, Semgrep, Trivy, Gitleaks). Use proactively before deployment or after significant code changes.
version: 3.5.0
model: sonnet
allowed-tools: Read, Bash, Grep, Glob
user-invocable: false
hooks:
  FileChanged:
    - matcher: "composer.json|package.json|phpstan.neon|phpstan.neon.dist|phpstan.dist.neon|phpcs.xml|phpcs.xml.dist|.phpcs.xml|psalm.xml|psalm.xml.dist|eslint.config.js|eslint.config.mjs|eslint.config.cjs|.eslintrc.js|.eslintrc.json|.eslintrc.yml|.eslintrc.yaml|tsconfig.json"
      hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/hooks/lint-changed.sh"
          timeout: 30
  PermissionDenied:
    - matcher: "Read|Grep|Glob"
      hooks:
        - type: command
          command: "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionDenied\",\"retry\":true}}'"
          timeout: 2
---

# Code Quality Audit

Run quality and security audits for **Drupal** and **Next.js** projects with consistent tooling and reporting.

> **Reading strategy:** Audit, review, security, SOLID, and DRY commands are **Type B** work (audit / review / architecture analysis) — agents must read full source and config files. Do NOT grep-first these flows. Inherited methods, annotations, and config-wired classes are invisible to a grep-first pass. See `https://camoa.github.io/dev-guides/development/reading-strategy/` via `dev-guides-navigator`. When a code-intelligence plugin is installed, the **LSP tool** resolves those inherited and config-wired relationships semantically — prefer it for SOLID/DRY/review relationship questions, and fall back to the full-read pass when it is unavailable. See `references/code-intelligence.md`.

## Quick Commands

**For direct access, use these commands:**
- `/code-quality:setup` - First-time setup wizard (install and configure tools)
- `/code-quality:audit` - Run full audit (all 22 operations)
- `/code-quality:coverage` - Check test coverage
- `/code-quality:security` - Security scan (10 layers for Drupal, 7 for Next.js)
- `/code-quality:lint` - Code standards check
- `/code-quality:solid` - Architecture and SOLID principles check
- `/code-quality:dry` - Find code duplication
- `/code-quality:tdd` - Start TDD workflow (test watcher mode)
- `/code-quality:review` - Rubric-scored code review (/50 scale with quality gate)
- `/code-quality:ultrareview` - Cloud multi-agent deep review with pre-flight checks (5-10min, paid after free quota)
- `/code-quality:generate-review-md` - Generate v2 REVIEW.md for Claude Code's managed Code Review
- `/code-quality:architecture-debate` - Architecture debate (Pragmatist + Purist + Maintainer)
- `/code-quality:security-debate` - Security debate (Defender + Red Team + Compliance)

**For conversational workflows, continue reading...**

## Watch-mode Linting (skill-scoped)

This skill declares two skill-scoped hooks in its frontmatter — active ONLY while the skill is loaded, NOT plugin-wide:

| Event | When | What |
|---|---|---|
| `FileChanged` | Linter config changes — exact filenames for common variants: `composer.json`, `package.json`, `phpstan.neon*` (3 variants), `phpcs.xml*` (3 variants), `psalm.xml*` (2 variants), `eslint.config.{js,mjs,cjs}`, `.eslintrc.{js,json,yml,yaml}`, `tsconfig.json` | Runs `hooks/lint-changed.sh` — re-lints on config change; lints single file on source-file change when watchPaths include it |
| `PermissionDenied` | `Read`, `Grep`, `Glob` denied in auto mode | Returns `{retry: true}` — retries non-destructive classifier denials during audits |

**Scope discipline:** both hooks auto-disable when the skill isn't active. A `FileChanged` handler at plugin scope would fire on every file change across every conversation — noise, not value. Audit-contextual behaviors belong here.

**FileChanged matcher is literal, not glob.** Per the Hooks Reference, `FileChanged` matcher values are split on `|` and registered as **literal filenames** — not globs. To watch arbitrary source files (`*.php`, `*.tsx`), populate `watchPaths` dynamically from a `CwdChanged` hook, or add specific absolute paths to your project's `.claude/settings.json`. The default watch list here covers linter-config churn; broaden it in your settings if you want per-file watch on source edits.

**Force-disable mid-session:**

```bash
export CLAUDE_CODE_QUALITY_WATCH=0
```

Unset the variable (or set to anything other than `0`) to re-enable.

**Why this isn't in `hooks/hooks.json`:** session-global hooks stay at plugin scope (only `PreCompact` there). Audit behaviors scoped to skill-active sessions avoid polluting unrelated work.

### Known limitations

- **`npx` inside a hostile clone.** If you load the skill in an attacker-controlled `package.json` repo and then edit a config file, the watch-mode dispatcher runs `npx --no-install eslint` from that tree. A trojaned `node_modules/.bin/eslint` would execute. Mitigation: the containment guard in `lint-changed.sh` refuses paths outside `cwd`, but cannot sandbox the linter itself. Don't load this skill in untrusted checkouts.
- **`PermissionDenied` retry fires unconditionally for `Read|Grep|Glob`.** The matcher is the tightest available mechanism — there's no finer-grained filter on "only during audit tool invocations." Noise on unrelated read-only denials while the skill is loaded is accepted.
- **`--json` output is model-generated.** The schema documents required shape + JSON-escape (`invariant 4` in `references/json-schemas.md`) but enforcement relies on the model following the contract. Consumers should `jq .` before trusting the document.
- **`FileChanged` matcher is literal-filename.** Unlisted variants (e.g., `phpstan.local.neon`, custom names) won't fire — populate `watchPaths` dynamically from a `CwdChanged` hook if you need broader source-file watching.

> **Note — Claude Code's built-in `/simplify`:** Claude Code ships a built-in `/simplify` skill for quick single-pass code review. `/code-quality:review` is different: it runs automated tools (PHPStan/ESLint), scores across 10 rubric categories with a /50 scale, enforces a quality gate (PASS 35+/FAIL), and writes a persisted report. Use `/simplify` for fast ad-hoc feedback; use `/code-quality:review` when you need a structured, scored, and documented assessment.

## When to Use

**Drupal projects:**
- "Setup quality tools" / "Install PHPStan"
- "Run code audit" / "Check code quality"
- "Check coverage" / "What's my coverage?"
- "Find SOLID violations" / "Check complexity"
- "Check duplication" / "DRY check"
- "Lint code" / "Check coding standards"
- "Fix deprecations" / "Run rector"
- "Start TDD" / "RED-GREEN-REFACTOR"
- "Check security" / "Find vulnerabilities" / "OWASP audit"

**Next.js projects:**
- "Setup quality tools" / "Install ESLint"
- "Run code audit" / "Check code quality"
- "Check coverage" / "Run Jest coverage"
- "Find SOLID violations" / "Check complexity" / "Check circular deps"
- "Lint code" / "Run ESLint"
- "Check duplication" / "DRY check"
- "Start TDD" / "Jest watch mode"
- "Check security" / "Find vulnerabilities" / "OWASP audit"

## Quick Reference

### Drupal Scripts
| Task | Script | Details |
|------|--------|---------|
| Setup tools | `scripts/core/install-tools.sh` | See [Drupal Setup](references/operations/drupal-setup.md#operation-1-setup-tools) |
| Full audit | `scripts/core/full-audit.sh` | See [Full Audit](references/operations/drupal-audits.md#operation-2-full-audit) |
| Coverage | `scripts/drupal/coverage-report.sh` | See [Coverage Check](references/operations/drupal-audits.md#operation-3-coverage-check) |
| SOLID check | `scripts/drupal/solid-check.sh` | See [SOLID Check](references/operations/drupal-audits.md#operation-4-solid-check) |
| DRY check | `scripts/drupal/dry-check.sh` | See [DRY Check](references/operations/drupal-audits.md#operation-5-dry-check) |
| Lint check | `scripts/drupal/lint-check.sh` | See [Lint Check](references/operations/drupal-audits.md#operation-11-lint-check) |
| Fix deprecations | `scripts/drupal/rector-fix.sh` | See [Rector Fix](references/operations/drupal-audits.md#operation-12-rector-fix) |
| TDD cycle | `scripts/drupal/tdd-workflow.sh` | See [TDD Workflow](references/operations/drupal-tdd.md) |
| Security audit | `scripts/drupal/security-check.sh` | See [Security Audit](references/operations/drupal-security.md) (10 layers) |

### Next.js Scripts
| Task | Script | Details |
|------|--------|---------|
| Setup tools | `scripts/core/install-tools.sh` | See [Next.js Setup](references/operations/nextjs-setup.md) |
| Full audit | `scripts/core/full-audit.sh` | See [Full Audit](references/operations/nextjs-audits.md#operation-14-full-audit) |
| Coverage | `scripts/nextjs/coverage-report.sh` | See [Coverage Check](references/operations/nextjs-audits.md#operation-16-coverage-check) |
| SOLID check | `scripts/nextjs/solid-check.sh` | See [SOLID Check](references/operations/nextjs-audits.md#operation-19-solid-check) |
| Lint check | `scripts/nextjs/lint-check.sh` | See [Lint Check](references/operations/nextjs-audits.md#operation-15-lint-check) |
| DRY check | `scripts/nextjs/dry-check.sh` | See [DRY Check](references/operations/nextjs-audits.md#operation-17-dry-check) |
| TDD cycle | `scripts/nextjs/tdd-workflow.sh` | See [TDD Workflow](references/operations/nextjs-tdd.md) |
| Security audit | `scripts/nextjs/security-check.sh` | See [Security Audit](references/operations/nextjs-security.md) (7 layers) |

## Before Any Operation

**Drupal:**
1. Locate Drupal root: check `web/core/lib/Drupal.php` or `docroot/core/lib/Drupal.php`
2. Verify DDEV: `ddev describe`
3. Create reports directory: `mkdir -p .reports && echo ".reports/" >> .gitignore`

**Next.js:**
1. Verify npm: `npm --version`
2. Create reports directory: `mkdir -p .reports && echo ".reports/" >> .gitignore`

> **Sandbox users:** If Claude Code sandbox mode is enabled, bash scripts that invoke linters (PHPStan, ESLint, Semgrep, Trivy, Gitleaks) require their binary paths to be whitelisted. Add the tool binaries to your `allowedPaths` in `claude_code_config.json` (e.g., `vendor/bin/phpstan`, `/usr/local/bin/semgrep`). DDEV-proxied commands run inside the container and are unaffected.

## When to Run What

Read `decision-guides/quality-audit-checklist.md` for detailed guidance.

| Context | What to Run | Time |
|---------|-------------|------|
| Pre-commit | `quality:cs` only | ~5s |
| Pre-push | PHPStan + Unit/Kernel tests | ~2min |
| Pre-merge | Full audit | ~10min |
| Weekly | Full audit + HTML reports | ~15min |

## Adaptive Audit Depth (`${CLAUDE_EFFORT}`)

When this skill drives an audit, scale depth to the session's effort level. The `${CLAUDE_EFFORT}` substitution resolves to the current level:

| `${CLAUDE_EFFORT}` | Audit depth |
|---|---|
| `low` | Fast lint only — coding-standards pass; skip security, SOLID, DRY, coverage |
| `medium` | Lint + coverage + SOLID + DRY; skip the deep security battery |
| `high` | Full audit — all 22 operations (the effective default) |
| `xhigh` / `max` | Full audit, then offer `/code-quality:security-debate` for a 3-agent review of the security findings |

Treat an unset or unrecognized value as `high` (full audit) — never silently skip coverage or security because the level could not be read.

This is a **pilot** (v3.5.0): adaptive depth is wired into the audit flow only. The `FileChanged` watch-mode dispatcher and per-command effort gates are intentionally not yet effort-aware — they will be revisited once this pilot has been observed in real use.

## Scope Targeting

To audit specific modules or components instead of the entire project:

**See [Scope Targeting](references/scope-targeting.md)** for three approaches:
1. **Change directory** (recommended) - `cd web/modules/custom/my_module`
2. **Environment variables** - `DRUPAL_MODULES_PATH=path/to/module`
3. **Full scan** (default) - Run from project root

Intelligent detection: Claude detects current directory and user intent.

---

# Operations

All detailed operation instructions have been moved to reference files for better organization.

## Drupal Operations

### Setup & Configuration
- **Operation 1:** [Setup Tools](references/operations/drupal-setup.md#operation-1-setup-tools) - Install PHPStan, PHPMD, PHPCPD, Coder
- **Operation 6:** [Module-Specific Audit](references/operations/drupal-setup.md#operation-6-module-specific-audit) - Scope audit to one module
- **Operation 7:** [Add Composer Scripts](references/operations/drupal-setup.md#operation-7-add-composer-scripts) - Configure quality scripts
- **Operation 8:** [CI Integration](references/operations/drupal-setup.md#operation-8-ci-integration) - Setup GitHub Actions

### Quality Audits
- **Operation 2:** [Full Audit](references/operations/drupal-audits.md#operation-2-full-audit) - Run all quality checks
- **Operation 3:** [Coverage Check](references/operations/drupal-audits.md#operation-3-coverage-check) - Measure test coverage
- **Operation 4:** [SOLID Check](references/operations/drupal-audits.md#operation-4-solid-check) - Find principle violations
- **Operation 5:** [DRY Check](references/operations/drupal-audits.md#operation-5-dry-check) - Detect code duplication
- **Operation 11:** [Lint Check](references/operations/drupal-audits.md#operation-11-lint-check) - Coding standards
- **Operation 12:** [Rector Fix](references/operations/drupal-audits.md#operation-12-rector-fix) - Auto-fix deprecations

### Development Workflows
- **Operation 10:** [TDD Workflow](references/operations/drupal-tdd.md) - RED-GREEN-REFACTOR cycle

### Security
- **Operation 20:** [Security Audit](references/operations/drupal-security.md) — 10 security layers
  - Drush pm:security, Composer audit
  - yousha/php-security-linter, Psalm taint analysis
  - Custom Drupal patterns, Security Review module
  - Semgrep SAST, Trivy scanner, Gitleaks
  - Roave Security Advisories

## Next.js Operations

### Setup & Configuration
- **Operation 13:** [Setup Tools](references/operations/nextjs-setup.md) - Install ESLint, Jest, security tools

### Quality Audits
- **Operation 14:** [Full Audit](references/operations/nextjs-audits.md#operation-14-full-audit) - Run all quality checks
- **Operation 15:** [Lint Check](references/operations/nextjs-audits.md#operation-15-lint-check) - ESLint + TypeScript
- **Operation 16:** [Coverage Check](references/operations/nextjs-audits.md#operation-16-coverage-check) - Jest coverage
- **Operation 17:** [DRY Check](references/operations/nextjs-audits.md#operation-17-dry-check) - Detect duplication
- **Operation 19:** [SOLID Check](references/operations/nextjs-audits.md#operation-19-solid-check) - Circular deps, complexity

### Development Workflows
- **Operation 18:** [TDD Workflow](references/operations/nextjs-tdd.md) - RED-GREEN-REFACTOR with Jest

### Security
- **Operation 21:** [Security Audit](references/operations/nextjs-security.md) — 7 security layers
  - npm audit, ESLint security plugins
  - Semgrep SAST, Trivy scanner, Gitleaks
  - Custom React/Next.js patterns (XSS, eval, navigation)
  - Socket CLI

## Optional: DAST (Dynamic Testing)

**Pre-production security testing for staging environments**

- **Operation 22:** [DAST Tools](references/operations/dast-tools.md) — Dynamic security testing
  - OWASP ZAP (full DAST scanner)
  - Nuclei (template-based CVE scanning)
  - Requires running application
  - Use before releases on staging/pre-production

---

## Saving Reports

All reports must follow `schemas/audit-report.schema.json`:

```json
{
  "meta": {
    "project_type": "drupal|nextjs|monorepo",
    "timestamp": "2025-12-19T12:00:00Z",
    "thresholds": { "coverage_minimum": 70, "duplication_max": 5 }
  },
  "summary": {
    "overall_score": "pass|warning|fail",
    "coverage_score": "pass|warning|fail",
    "solid_score": "pass|warning|fail",
    "dry_score": "pass|warning|fail",
    "security_score": "pass|warning|fail"
  },
  "coverage": { "line_coverage": 75.5, "files_analyzed": 45 },
  "solid": { "violations": [] },
  "dry": { "duplication_percentage": 3.2, "clones": [] },
  "security": { "critical": 0, "high": 0, "medium": 3, "low": 5, "issues": [] },
  "recommendations": []
}
```

---

## References

### Core Guidance
- `references/tdd-workflow.md` - RED-GREEN-REFACTOR patterns, test naming, cycle targets
- `references/coverage-metrics.md` - Coverage targets by code type, PCOV vs Xdebug
- `references/dry-detection.md` - Rule of Three, when duplication is OK
- `references/solid-detection.md` - SOLID detection patterns and fixes
- `references/composer-scripts.md` - Ready-to-use composer scripts
- `references/scope-targeting.md` - Target specific modules/components
- `references/post-batch-aggregation.md` - Optional `PostToolBatch` aggregation pattern (Claude Code 2.1.118+); not shipped by default
- `references/code-intelligence.md` - Optional LSP-tool code intelligence for deeper SOLID/DRY/review analysis (recommended-not-required)
- `references/setup-hook-pattern.md` - Optional `Setup`-hook pattern for one-time CI tool bootstrap on `claude --init -p`; not shipped by default

### Operations
- `references/operations/drupal-setup.md` - Drupal setup operations
- `references/operations/drupal-audits.md` - Drupal quality audit operations
- `references/operations/drupal-security.md` - **Drupal security (10 layers, v2.0.0)**
- `references/operations/drupal-tdd.md` - Drupal TDD workflow
- `references/operations/nextjs-setup.md` - Next.js setup operations
- `references/operations/nextjs-audits.md` - Next.js quality audit operations
- `references/operations/nextjs-security.md` - **Next.js security (7 layers, v2.0.0)**
- `references/operations/nextjs-tdd.md` - Next.js TDD workflow

### Online Dev-Guides (Drupal Domain)

For deeper Drupal-specific patterns beyond tool commands, fetch the guide index:

**Index:** `https://camoa.github.io/dev-guides/llms.txt`

Likely relevant topics: solid-principles, dry-principles, security, testing, tdd, js-development, github-actions

Usage: WebFetch the index to discover available topics, then fetch specific topic pages when explaining violations, suggesting fixes, or providing architectural context.

## Decision Guides

- `decision-guides/test-type-selection.md` - Unit vs Kernel vs Functional decision tree
- `decision-guides/quality-audit-checklist.md` - When to run what (pre-commit vs pre-merge)

## Templates

### Drupal
- `templates/drupal/phpstan.neon` - PHPStan 2.x config (extensions auto-load)
- `templates/drupal/phpmd.xml` - PHPMD ruleset for Drupal
- `templates/drupal/phpunit.xml` - PHPUnit config with testsuites
- `templates/ci/github-drupal.yml` - GitHub Actions workflow with security tools

### Next.js
- `templates/nextjs/eslint.config.js` - ESLint v9 flat config with TypeScript + security
- `templates/nextjs/jest.config.js` - Jest config with coverage thresholds
- `templates/nextjs/jest.setup.js` - Jest setup with Testing Library
- `templates/nextjs/.prettierrc` - Prettier config with Tailwind plugin

See `CHANGELOG.md` for version history.
