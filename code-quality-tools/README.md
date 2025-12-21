# Code Quality Tools

Code quality and security auditing plugin for Claude Code. Provides TDD, SOLID, DRY, and OWASP security checks for **Drupal** (via DDEV) and **Next.js** projects with Semgrep, Trivy, and Gitleaks.

## Installation

```bash
/plugin install code-quality-tools@camoa-skills
```

## What Claude Can Do

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

**v2.1.0** - Optional DAST tools (OWASP ZAP + Nuclei) for pre-production security testing

**v2.0.0** - Major refactoring + Phase 1 (Semgrep, Trivy, Gitleaks) + Phase 2 (Roave, Socket CLI)
- Drupal: 10 security layers (90% coverage)
- Next.js: 7 security layers (85% coverage)

## License

MIT
