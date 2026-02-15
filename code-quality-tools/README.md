# Code Quality Tools

Code quality and security auditing plugin for Claude Code. Provides TDD, SOLID, DRY, and OWASP security checks for **Drupal** (via DDEV) and **Next.js** projects with Semgrep, Trivy, and Gitleaks.

## Quick Start

### 1. Install Plugin

```bash
/plugin install code-quality-tools@camoa-skills
```

### 2. Install Tools

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

System tools (install once):
- [Semgrep](https://semgrep.dev/docs/getting-started/) - `pip install semgrep`
- [Trivy](https://trivy.dev/latest/getting-started/installation/) - Platform-specific
- [Gitleaks](https://github.com/gitleaks/gitleaks#installing) - Platform-specific

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

System tools: Semgrep, Trivy, Gitleaks (same as above)

### 3. Run Commands

| Command | Purpose | Example Use |
|---------|---------|-------------|
| `/code-quality:audit` | Full audit (all checks) | Before commits/releases |
| `/code-quality:coverage` | Test coverage | During TDD |
| `/code-quality:security` | Security scan | Pre-deployment |
| `/code-quality:lint` | Code standards | PR reviews |
| `/code-quality:solid` | Architecture check | Refactoring |
| `/code-quality:dry` | Find duplication | Code cleanup |
| `/code-quality:tdd` | TDD workflow | Development |
| `/code-quality:security-debate` | Multi-perspective security debate (agent teams) | Post-audit deep analysis |

**Troubleshooting?** See [Troubleshooting Guide](skills/code-quality-audit/references/troubleshooting.md)

---

## What Claude Can Do (Conversational)

Once installed, Claude handles these requests:

### Drupal Projects

| Request | What Claude Does |
|---------|------------------|
| "Setup code quality tools" | Installs PHPStan, PHPMD, PHPCPD, Psalm, security tools via composer |
| "Run a code quality audit" | Runs all checks, saves JSON to `.reports/`, shows summary |
| "Check test coverage" | PHPUnit + PCOV coverage |
| "Find SOLID violations" | PHPStan + PHPMD + static call detection |
| "Check for duplication" | PHPCPD duplication analysis |
| "Lint code" | phpcs with Drupal/DrupalPractice standards |
| "Fix deprecations" | drupal-rector auto-fix |
| **"Run security audit"** | **OWASP + Drupal security: Drush advisories, Composer audit, Psalm taint, PHPCS security, Semgrep SAST, Trivy, Gitleaks, Roave, custom patterns (10 layers)** |
| "Add quality checks to CI" | Creates GitHub Actions workflow |

### Next.js Projects

| Request | What Claude Does |
|---------|------------------|
| "Setup code quality tools" | Installs ESLint + security plugins, Jest, jscpd, madge, Semgrep, Trivy, Gitleaks via npm |
| "Run a code quality audit" | Runs all checks, saves JSON to `.reports/`, shows summary |
| "Check test coverage" | Jest coverage with thresholds |
| "Find SOLID violations" | Circular deps (madge), complexity, large files, TS strict |
| "Check for duplication" | jscpd duplication analysis |
| "Lint code" | ESLint + TypeScript type checking |
| **"Run security audit"** | **npm audit, ESLint security plugins, Semgrep SAST, Trivy, Gitleaks, Socket CLI, React XSS patterns (7 layers)** |
| "Start TDD" | Jest watch mode with RED-GREEN-REFACTOR |

## Reports

All audit results are saved to `.reports/` (git-ignored):

```
.reports/
├── coverage-report.json    # Test coverage data
├── solid-report.json       # SOLID violations
├── lint-report.json        # Lint results (Next.js)
├── dry-report.json         # Duplication analysis
├── security-report.json    # Security vulnerabilities (OWASP)
├── audit-report.json       # Full audit (aggregated)
└── audit-report.md         # Human-readable report
```

## Thresholds

| Metric | Pass | Warning | Fail |
|--------|------|---------|------|
| Coverage | >80% | 70-80% | <70% |
| Duplication | <5% | 5-10% | >10% |
| Complexity | <10 | 10-15 | >15 |
| Circular deps (Next.js) | 0 | - | >0 |
| **Security: Critical** | **0** | **0** | **>0** |
| **Security: High** | **0** | **1-3** | **>3** |
| **Security: Medium** | **0** | **1-10** | **>10** |

## Requirements

### Drupal
- **DDEV** - All tools run inside DDEV container
- **Drupal 10.3+** or **11.x**
- **PHP 8.2+** (8.3+ recommended)

### Next.js
- **Node.js 18+**
- **npm** or **yarn**
- **TypeScript** (recommended)

## Directory Structure

```
code-quality-tools/
├── skills/
│   └── code-quality-audit/
│       ├── SKILL.md              # Claude instructions (19 operations)
│       ├── scripts/
│       │   ├── core/             # Shared scripts
│       │   ├── drupal/           # Drupal-specific
│       │   └── nextjs/           # Next.js-specific
│       ├── templates/
│       │   ├── drupal/           # phpstan.neon, phpmd.xml, etc.
│       │   └── nextjs/           # eslint.config.js, jest.config.js
│       ├── references/           # Detailed docs
│       └── decision-guides/      # When to use what
```

## Tools Used

### Drupal
| Tool | Purpose |
|------|---------|
| [phpstan/phpstan](https://phpstan.org/) | Static analysis |
| [mglaman/phpstan-drupal](https://github.com/mglaman/phpstan-drupal) | Drupal rules |
| [phpmd/phpmd](https://phpmd.org/) | Code smells |
| [systemsdk/phpcpd](https://github.com/systemsdk/phpcpd) | Duplication |
| [drupal/coder](https://www.drupal.org/project/coder) | Coding standards |
| [palantirnet/drupal-rector](https://github.com/palantirnet/drupal-rector) | Auto-fix deprecations |
| **[vimeo/psalm](https://psalm.dev/)** | **Taint analysis (XSS/SQLi)** |
| **[yousha/php-security-linter](https://github.com/Yousha/php-security-linter)** | **PHPCS security (OWASP/CIS)** |
| **[Semgrep](https://semgrep.dev/)** | **Multi-language SAST (20K+ rules)** |
| **[Trivy](https://trivy.dev/)** | **Dependency/container/secret scanner** |
| **[Gitleaks](https://gitleaks.io/)** | **Secret detection (800+ patterns)** |
| **[drupal/security_review](https://www.drupal.org/project/security_review)** | **Drupal config audit** |
| **[Roave Security Advisories](https://github.com/Roave/SecurityAdvisories)** | **Composer prevention layer** |
| **Drush pm:security** | **Drupal security advisories** |
| **Composer audit** | **Package vulnerabilities** |

### Next.js
| Tool | Purpose |
|------|---------|
| [ESLint](https://eslint.org/) | Linting |
| **[eslint-plugin-security](https://github.com/eslint-community/eslint-plugin-security)** | **Security linting** |
| [TypeScript](https://www.typescriptlang.org/) | Type checking |
| [Jest](https://jestjs.io/) | Testing + coverage |
| [jscpd](https://github.com/kucherenko/jscpd) | Duplication |
| [madge](https://github.com/pahen/madge) | Circular dependency detection |
| **[Semgrep](https://semgrep.dev/)** | **Multi-language SAST (React/JS/TS rules)** |
| **[Trivy](https://trivy.dev/)** | **Dependency/container/secret scanner** |
| **[Gitleaks](https://gitleaks.io/)** | **Secret detection (800+ patterns)** |
| **[Socket CLI](https://socket.dev/)** | **Supply chain attack detection** |
| **npm audit** | **Package vulnerability scanning** |

## Optional: DAST Tools

For **pre-production and staging environments**, optional DAST (Dynamic Application Security Testing) tools are documented:

| Tool | Purpose |
|------|---------|
| **[OWASP ZAP](https://www.zaproxy.org/)** | Full DAST scanner - active/passive scanning, authentication testing |
| **[Nuclei](https://nuclei.projectdiscovery.io/)** | Template-based CVE scanning - 1000+ vulnerability templates |

See `references/operations/dast-tools.md` for installation and usage.

## Version

**v2.5.0** (Current) - Online dev-guides integration
- SOLID, DRY, Security topics from https://camoa.github.io/dev-guides/ for deeper Drupal context
- Security debate enrichment with WebFetch of relevant OWASP/XSS/SQLi/CSRF guides
- 28-entry keyword→URL mapping in SKILL.md for Drupal domain knowledge

**v2.4.0** - Security Debate Team (agent teams)
- `/code-quality:security-debate` — 3-agent debate over security audit findings
- Defender + Red Team + Compliance Checker with cross-challenge synthesis
- Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

**v2.3.0** - Plugin conventions and model routing
- Model routing (`sonnet`) on skill for cost optimization
- CLAUDE.md and `.claude/rules/` conventions

**v2.2.0** - Commands for direct access + improved discoverability
- 8 new slash commands for direct operation access
- Project auto-detection (Drupal/Next.js)
- Intelligent error handling with recovery guidance

**v2.1.0** - Optional DAST tools (OWASP ZAP + Nuclei) for pre-production security testing

**v2.0.0** - Major refactoring + Phase 1 (Semgrep, Trivy, Gitleaks) + Phase 2 (Roave, Socket CLI)
- Drupal: 10 security layers (90% coverage)
- Next.js: 7 security layers (85% coverage)

## License

MIT
