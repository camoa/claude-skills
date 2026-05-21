# Code Quality Tools

Code quality and security auditing plugin for Claude Code. Provides TDD, SOLID, DRY, and OWASP security checks for **Drupal** (via DDEV) and **Next.js** projects with Semgrep, Trivy, and Gitleaks.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md) — skills work in Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more.

## How Detection Works

**All commands are the same for both project types.** When you run any command, the plugin auto-detects your project by checking:

| Signal | Detected As |
|--------|-------------|
| `composer.json` with `drupal/core` | Drupal |
| `web/core/` or `docroot/core/` directory | Drupal |
| `.ddev/config.yaml` with `type: drupal` | Drupal |
| `next.config.js` / `.mjs` / `.ts` | Next.js |
| `package.json` with `"next"` dependency | Next.js |
| Both present | Monorepo (runs both toolchains) |

Then it routes to the correct toolchain — PHPStan/PHPMD/Psalm for Drupal, ESLint/Jest/madge for Next.js. You never need to specify which type.

## Quick Start

### 1. Install Plugin

```bash
/plugin install code-quality-tools@camoa-skills
```

### 2. First-Time Setup

Run the interactive setup wizard — it detects your project type and installs the right tools:

```
/code-quality:setup
```

Or install manually:

**Drupal (via DDEV):**
```bash
ddev composer require --dev \
  phpstan/phpstan \
  phpmd/phpmd \
  sebastian/phpcpd \
  vimeo/psalm \
  drupal/coder \
  drupal/security_review \
  roave/security-advisories
```

**Next.js:**
```bash
npm install --save-dev \
  eslint \
  @typescript-eslint/parser \
  @typescript-eslint/eslint-plugin \
  eslint-plugin-security \
  jest \
  @testing-library/react \
  @testing-library/jest-dom \
  jscpd \
  madge
```

**System tools (both):** [Semgrep](https://semgrep.dev/docs/getting-started/), [Trivy](https://trivy.dev/latest/getting-started/installation/), [Gitleaks](https://github.com/gitleaks/gitleaks#installing)

**Code intelligence (optional, recommended):** install a code-intelligence plugin — `php-lsp` (Drupal) or `typescript-lsp` (Next.js) — plus its language-server binary to make `/code-quality:solid`, `:dry`, and `:review` resolve inherited and config-wired relationships semantically via Claude Code's LSP tool. Recommended, not required: the commands fall back to full-file reads when no LSP plugin is present. See `skills/code-quality-audit/references/code-intelligence.md`.

### 3. Run Commands

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `/code-quality:audit` | Full audit + cross-tool synthesis (`--json` for CI) | Before commits/releases |
| `/code-quality:review` | Rubric-scored code review (/50 scale, `--json` for CI) | PR reviews, code assessment |
| `/code-quality:ultrareview` | Cloud multi-agent deep review (paid after free quota) | Pre-merge on substantial changes |
| `/code-quality:security` | Security scan (10 Drupal, 7 Next.js; `--json` for CI) | Pre-deployment |
| `/code-quality:generate-review-md` | Generate v2 REVIEW.md (injection model) | One-time per project |
| `/code-quality:coverage` | Test coverage | During TDD |
| `/code-quality:lint` | Code standards | Quick checks |
| `/code-quality:solid` | Architecture check | Refactoring |
| `/code-quality:dry` | Find duplication | Code cleanup |
| `/code-quality:tdd` | TDD workflow (test watcher) | Development |
| `/code-quality:setup` | Install and configure tools | First-time setup |

### Agent Team Commands (Multi-Perspective Debate)

These spawn 3-agent teams that analyze from competing perspectives, cross-challenge, and synthesize a balanced assessment:

| Command | Agents | Best For |
|---------|--------|----------|
| `/code-quality:security-debate` | Defender + Red Team + Compliance | Validating 10+ security findings |
| `/code-quality:architecture-debate` | Pragmatist + Purist + Maintainer | Contentious design decisions |

Each agent runs in an isolated worktree with scoped tool access and cost-controlled turns.

## How It Works

### Conversational Use

Once installed, Claude responds to natural language:

| Say This | Claude Does This |
|----------|------------------|
| "Audit this code" | Full audit with cross-tool synthesis |
| "Review this module" | Rubric-scored review with /50 grade |
| "Check security" | 10-layer security scan (Drupal) or 7-layer (Next.js) |
| "Is this production ready?" | Code review with quality gate (PASS 35+/FAIL) |
| "Debate the architecture" | 3-agent team: Pragmatist vs Purist vs Maintainer |
| "Start TDD" | RED-GREEN-REFACTOR cycle with test watcher |
| "Find SOLID violations" | PHPStan + PHPMD + complexity analysis |
| "Check duplication" | PHPCPD (Drupal) or jscpd (Next.js) |
| "Lint this" | phpcs with Drupal standards or ESLint |
| "Fix deprecations" | drupal-rector auto-fix (Drupal only) |

### Code Review Scoring

`/code-quality:review` grades code on a /50 rubric:

**Content (Does it work?) — /25:**
- Correctness, Completeness, Edge cases, Error handling, Security

**Structure (Is it maintainable?) — /25:**
- Readability, Separation of concerns, DRY, Testability, Extensibility

**Quality Gate:** PASS requires 35+/50 with no category below 2.

### Cross-Audit Synthesis

`/code-quality:audit` doesn't just run tools — it correlates findings:
- **Hot spots:** Files flagged by multiple tools = highest priority
- **Cross-category risks:** Security issue + missing tests + SOLID violation = compounding risk
- **Prioritized action plan:** Top 5 fixes that resolve the most findings
- Output: `.reports/audit-synthesis.md`

### Security Debate

`/code-quality:security-debate` spawns 3 agents after a security audit:
- **Defender:** Validates findings, identifies false positives, checks framework mitigations
- **Red Team:** Chains findings into attack scenarios, searches CVEs, finds audit gaps
- **Compliance:** Maps to OWASP Top 10 / CWE, identifies coverage blind spots

Output: `.reports/security-debate.md` with debated severity ratings and prioritized remediation.

### Architecture Debate

`/code-quality:architecture-debate` spawns 3 agents for design decisions:
- **Pragmatist:** "Does it ship? Is refactoring worth the cost?"
- **Purist:** "What SOLID/DRY violations exist? How should this be structured?"
- **Maintainer:** "Can I debug this at 2am? Can a new dev understand it?"

Output: `.reports/architecture-debate.md` with consensus fixes and accepted trade-offs.

## Reports

All results save to `.reports/` (git-ignored):

```
.reports/
├── audit-report.json         # Full audit (aggregated)
├── audit-synthesis.md         # Cross-tool correlation and action plan
├── coverage-report.json       # Test coverage data
├── solid-report.json          # SOLID violations
├── dry-report.json            # Duplication analysis
├── security-report.json       # Security vulnerabilities
├── code-review-{name}.md      # Rubric-scored review
├── security-debate.md         # 3-agent security debate
├── architecture-debate.md     # 3-agent architecture debate
└── lint-report.json           # Lint results
```

## Thresholds

| Metric | Pass | Warning | Fail |
|--------|------|---------|------|
| Coverage | >80% | 70-80% | <70% |
| Duplication | <5% | 5-10% | >10% |
| Complexity | <10 | 10-15 | >15 |
| Code Review | 35+/50 | 25-34 | <25 |
| Security: Critical | 0 | 0 | >0 |
| Security: High | 0 | 1-3 | >3 |

## Requirements

### Drupal
- **DDEV** — all tools run inside DDEV container
- **Drupal 10.3+** or **11.x**
- **PHP 8.2+** (8.3+ recommended)

### Next.js
- **Node.js 18+**
- **npm** or **yarn**
- **TypeScript** (recommended)

## Security Layers

### Drupal (10 layers)

| # | Tool | What It Checks |
|---|------|---------------|
| 1 | Drush pm:security | Drupal security advisories |
| 2 | Composer audit | Package vulnerabilities |
| 3 | yousha/php-security-linter | PHPCS security rules (OWASP/CIS) |
| 4 | Psalm taint analysis | XSS/SQLi data flow tracking |
| 5 | Custom Drupal patterns | db_query, FormBase, access callbacks |
| 6 | Security Review module | Drupal config audit |
| 7 | Semgrep SAST | 20,000+ rules (PHP, JS, YAML) |
| 8 | Trivy | Dependencies, containers, secrets |
| 9 | Gitleaks | Secret detection (800+ patterns) |
| 10 | Roave Security Advisories | Composer prevention layer |

### Next.js (7 layers)

| # | Tool | What It Checks |
|---|------|---------------|
| 1 | npm audit | Package vulnerabilities |
| 2 | ESLint security plugins | Security linting rules |
| 3 | Custom React/Next.js patterns | XSS, eval, navigation |
| 4 | Semgrep SAST | 20,000+ rules (React, JS, TS) |
| 5 | Trivy | Dependencies, containers, secrets |
| 6 | Gitleaks | Secret detection (800+ patterns) |
| 7 | Socket CLI | Supply chain attack detection |

### Optional: DAST (Pre-Production)

| Tool | Purpose |
|------|---------|
| [OWASP ZAP](https://www.zaproxy.org/) | Full DAST scanner — active/passive scanning |
| [Nuclei](https://nuclei.projectdiscovery.io/) | Template-based CVE scanning (1000+ templates) |

See `references/operations/dast-tools.md` for setup.

## CI & Git Hooks (opt-in)

Two GitHub Actions templates and a pre-commit hook config ship with the plugin. All three are independently opt-in — install whichever fit your team.

### GitHub Actions

| Template | Triggers on | Scope | What it does |
|----------|-------------|-------|--------------|
| `templates/ci/github-drupal.yml` → `.github/workflows/quality.yml` | `push` + `pull_request` to `main`/`develop` | Full custom modules + themes tree | Full battery: PHPStan, PHPMD, PHPCPD, phpcs, Psalm, Drush security advisories, `composer audit`, Semgrep, Trivy, Gitleaks, PHPUnit + coverage gate. Uploads to Codecov. |
| `templates/ci/github-drupal-pr.yml` → `.github/workflows/quality-pr.yml` | `pull_request` only | **Changed PHP files in the PR only** (via `git diff --diff-filter=ACMR base...head`) | Runs phpcs + phpstan + Semgrep scoped to changed files, builds a rubric score (/50), and posts a **sticky PR comment** (`marocchino/sticky-pull-request-comment`) with findings + gate verdict. Uploads raw JSON as an artifact. |

**Gate behavior for the PR workflow:** soft by default — comment posts, check stays green. To enforce, set repo Variable `FAIL_ON_GATE=true` (Settings → Variables → Actions). Then the workflow fails when rubric < 35/50 OR any high/critical Semgrep finding.

Both assume DDEV (uses `ddev/github-action-setup-ddev@v1`). For non-DDEV projects, adapt the `ddev exec` calls to plain `vendor/bin/...`.

### Git pre-commit hook (Drupal, optional)

`/code-quality:setup` will prompt — default **No** — to install **GrumPHP** with `phpcs + phpstan` running on **staged files only** (`context: git-staged-files`). The template lives at `templates/grumphp.yml`. Excluded by design: PHPCPD (directory-scoped, slow on every commit), PHPUnit (full suite — keep that in CI), PHPMD (noisy; opt in by editing the template).

To install later without re-running setup:

```bash
ddev composer require --dev phpro/grumphp
cp <plugin>/skills/code-quality-audit/templates/grumphp.yml ./grumphp.yml
ddev exec vendor/bin/grumphp git:init
```

## Watch-mode & Scheduled Sweeps

- **Watch-mode linting** activates while the `code-quality-audit` skill is loaded — edits to `composer.json`, `package.json`, `phpstan.neon*`, `psalm.xml`, `eslint.config.*`, or `tsconfig.json` re-run the lint. Disable mid-session: `export CLAUDE_CODE_QUALITY_WATCH=0`.
- **Scheduled sweeps** — pick a surface (Desktop / Cloud Routine / `/loop`) based on whether the audit needs local file access, machine-off reliability, or in-session polling. Templates in `skills/code-quality-audit/references/scheduled-sweeps.md`, `desktop-sweep-template.md`, `cloud-routine-sweep.md`.
- **Pre-merge CI gate** — Cloud Routine with API trigger callable from GitHub Actions / GitLab CI. Full template in `skills/code-quality-audit/references/premerge-gate-routine.md`.
- **Check-run JSON** — parse the managed Code Review check run with `gh`+`jq` to block merge on Important findings. See `skills/code-quality-audit/references/check-run-json.md`.

## Version

See `CHANGELOG.md` for the full history.

## License

MIT
