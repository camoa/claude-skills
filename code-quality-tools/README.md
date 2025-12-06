# Code Quality Tools

Code quality auditing plugin for Claude Code. Provides TDD, SOLID, and DRY principle checks for Drupal projects via DDEV.

## Installation

```bash
/plugin install code-quality-tools@camoa-skills
```

## Quick Start

Once installed, Claude will automatically use this skill when you say things like:
- "Run a code quality audit on my Drupal module"
- "Check my test coverage"
- "Find SOLID violations in my codebase"
- "Check for code duplication"
- "Setup quality tools for my project"

### Manual Usage

```bash
# 1. Navigate to your Drupal project (must have DDEV configured)
cd /path/to/drupal-project

# 2. Detect environment and validate DDEV
./scripts/core/detect-environment.sh

# 3. Install quality tools (if not already installed)
./scripts/core/install-tools.sh

# 4. Run full audit
./scripts/core/full-audit.sh

# Reports generated in ./reports/quality/
# - audit-report.json (structured data)
# - audit-report.md (human-readable)
```

## What It Does

### Checks Performed

| Check | Tools | What It Detects |
|-------|-------|-----------------|
| **Test Coverage** | PHPUnit + PCOV | Line coverage percentage |
| **SOLID Principles** | PHPStan, PHPMD, drupal-check | SRP violations (complexity), DIP violations (static calls), LSP (type errors) |
| **DRY Violations** | PHPCPD | Code duplication percentage |
| **Coding Standards** | Drupal Coder | Drupal/DrupalPractice standards |

### Default Thresholds

| Metric | Default | Environment Variable |
|--------|---------|----------------------|
| Coverage minimum | 70% | `COVERAGE_MINIMUM` |
| Coverage target | 80% | `COVERAGE_TARGET` |
| Max duplication | 5% | `DUPLICATION_MAX` |
| Max complexity | 10 | `COMPLEXITY_MAX` |

### Output

- **JSON reports** - Structured data for CI/CD integration
- **Markdown reports** - Human-readable with tables and recommendations
- **Exit codes** - 0 (pass), 1 (warning), 2 (fail)

## Requirements

- **DDEV** - All tools run inside DDEV container for consistent PHP environment
- **Drupal 10.3+** or **11.x**
- **PHP 8.2+** (8.3+ recommended for PHPCPD)

## Skills Included

### code-quality-audit

The main skill. See `skills/code-quality-audit/SKILL.md` for complete documentation including:
- Detailed threshold configuration
- SOLID principle detection methods
- TDD workflow guidance
- Troubleshooting guide

## Directory Structure

```
code-quality-tools/
├── skills/
│   └── code-quality-audit/
│       ├── SKILL.md              # Main documentation (Claude reads this)
│       ├── scripts/
│       │   ├── core/             # Environment, install, audit, report
│       │   └── drupal/           # Coverage, SOLID, DRY, TDD scripts
│       ├── references/           # Detailed docs (loaded on demand)
│       ├── decision-guides/      # Test type selection, audit checklist
│       ├── templates/            # phpunit.xml, phpstan.neon, etc.
│       └── schemas/              # JSON report schema
```

## Tools Used

| Tool | Version | Purpose | License |
|------|---------|---------|---------|
| [phpstan/phpstan](https://phpstan.org/) | 2.x | Static analysis | MIT |
| [mglaman/phpstan-drupal](https://github.com/mglaman/phpstan-drupal) | Latest | Drupal-specific rules | MIT |
| [phpmd/phpmd](https://phpmd.org/) | Latest | Code smells detection | BSD-3 |
| [systemsdk/phpcpd](https://github.com/systemsdk/phpcpd) | 8.x | Copy-paste detection | BSD-3 |
| [mglaman/drupal-check](https://github.com/mglaman/drupal-check) | 1.5+ | Deprecation checks | GPL-2.0 |
| [drupal/coder](https://www.drupal.org/project/coder) | 9.x | Coding standards | GPL-2.0 |

## Acknowledgments

This skill was built using patterns and insights from:

### Tools & Libraries
- **[PHPStan](https://phpstan.org/)** by Ondřej Mirtes - Static analysis foundation
- **[phpstan-drupal](https://github.com/mglaman/phpstan-drupal)** by Matt Glaman - Drupal integration for PHPStan
- **[drupal-check](https://github.com/mglaman/drupal-check)** by Matt Glaman - Deprecation analysis
- **[PHPMD](https://phpmd.org/)** - Code smell detection and complexity metrics
- **[PHPCPD](https://github.com/systemsdk/phpcpd)** (systemsdk fork) - Copy-paste detection (original by Sebastian Bergmann)
- **[PCOV](https://github.com/krakjoe/pcov)** by Joe Watkins - Fast code coverage

### Methodologies & Articles
- **[Sandi Metz](https://sandimetz.com/)** - "The Wrong Abstraction" and Rule of Three for DRY
- **[Oliver Davies](https://www.oliverdavies.uk/)** - TDD in Drupal methodology
- **[Matt Glaman](https://mglaman.dev/)** - Dependency injection anti-patterns in Drupal

### Frameworks
- **[Superpowers](https://github.com/obra/superpowers-marketplace)** by Jesse Vincent - Code review output format inspiration
- **[skill-creation-tools](../skill-creation-tools/)** - Skill creation workflow

### Documentation Sources
- [PHPStan Rule Levels](https://phpstan.org/user-guide/rule-levels)
- [PHPMD Rules Documentation](https://phpmd.org/rules/)
- [Drupal Testing Documentation](https://www.drupal.org/docs/develop/automated-testing)
- [PHPUnit Code Coverage](https://docs.phpunit.de/en/10.5/code-coverage.html)

## Contributing

Issues and PRs welcome at the [camoa-skills repository](https://github.com/camoa/claude-skills).

## License

MIT
