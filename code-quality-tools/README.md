# Code Quality Tools

Code quality auditing plugin for Claude Code. Provides TDD, SOLID, and DRY principle checks for **Drupal** (via DDEV) and **Next.js** projects.

## Installation

```bash
/plugin install code-quality-tools@camoa-skills
```

## What Claude Can Do

Once installed, Claude handles these requests:

### Drupal Projects

| Request | What Claude Does |
|---------|------------------|
| "Setup code quality tools" | Installs PHPStan, PHPMD, PHPCPD, drupal-rector via composer |
| "Run a code quality audit" | Runs all checks, saves JSON to `.reports/`, shows summary |
| "Check test coverage" | PHPUnit + PCOV coverage |
| "Find SOLID violations" | PHPStan + PHPMD + static call detection |
| "Check for duplication" | PHPCPD duplication analysis |
| "Lint code" | phpcs with Drupal/DrupalPractice standards |
| "Fix deprecations" | drupal-rector auto-fix |
| "Add quality checks to CI" | Creates GitHub Actions workflow |

### Next.js Projects

| Request | What Claude Does |
|---------|------------------|
| "Setup code quality tools" | Installs ESLint, Jest, jscpd, madge via npm |
| "Run a code quality audit" | Runs all checks, saves JSON to `.reports/`, shows summary |
| "Check test coverage" | Jest coverage with thresholds |
| "Find SOLID violations" | Circular deps (madge), complexity, large files, TS strict |
| "Check for duplication" | jscpd duplication analysis |
| "Lint code" | ESLint + TypeScript type checking |
| "Start TDD" | Jest watch mode with RED-GREEN-REFACTOR |

## Reports

All audit results are saved to `.reports/` (git-ignored):

```
.reports/
├── coverage-report.json    # Test coverage data
├── solid-report.json       # SOLID violations
├── lint-report.json        # Lint results (Next.js)
├── dry-report.json         # Duplication analysis
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

### Next.js
| Tool | Purpose |
|------|---------|
| [ESLint](https://eslint.org/) | Linting |
| [TypeScript](https://www.typescriptlang.org/) | Type checking |
| [Jest](https://jestjs.io/) | Testing + coverage |
| [jscpd](https://github.com/kucherenko/jscpd) | Duplication |
| [madge](https://github.com/pahen/madge) | Circular dependency detection |

## Version

**v1.6.0** - Full SOLID support for Next.js with madge

## License

MIT
