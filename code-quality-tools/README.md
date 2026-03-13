# Code Quality Tools

Code quality and security auditing plugin for Claude Code. Provides TDD, SOLID, DRY, and OWASP security checks for **Drupal** (via DDEV) and **Next.js** projects with Semgrep, Trivy, and Gitleaks.

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

### 3. Run Commands

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `/code-quality:audit` | Full audit (all checks + synthesis) | Before commits/releases |
| `/code-quality:review` | Rubric-scored code review (/50 scale) | PR reviews, code assessment |
| `/code-quality:security` | Security scan (10 layers Drupal, 7 Next.js) | Pre-deployment |
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

## Version

**v2.7.0** (Current)
- Rubric-scored code review (`/review`) with /50 scale and quality gate
- Architecture debate (`/architecture-debate`) — Pragmatist + Purist + Maintainer
- Cross-audit synthesis in `/audit` — hot spots, cross-category risks, action plan
- Agent team enhancements: maxTurns, isolated worktrees, scoped tools, quality gates
- Removed experimental agent teams flag (now GA)

**v2.5.0** — Online dev-guides integration for deeper Drupal context

**v2.4.0** — Security debate team (Defender + Red Team + Compliance)

**v2.1.0** — Optional DAST tools (OWASP ZAP + Nuclei)

**v2.0.0** — Major security expansion: Semgrep, Trivy, Gitleaks, Roave, Socket CLI

## License

MIT
