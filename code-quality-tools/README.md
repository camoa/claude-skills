# Code Quality Tools

Code quality auditing plugin for Claude Code. Provides TDD, SOLID, and DRY principle checks for Drupal projects via DDEV.

## Installation

```bash
/plugin install code-quality-tools@camoa-skills
```

## Skills

### code-quality-audit

Automated code quality auditing that runs:
- **Test Coverage**: PHPUnit + PCOV via DDEV
- **SOLID Checks**: PHPStan, PHPMD, drupal-check
- **DRY Checks**: PHPCPD duplication detection
- **Coding Standards**: Drupal Coder (phpcs)

Generates JSON reports converted to Markdown for human readability.

## Usage

Trigger phrases:
- "Run a code quality audit on my Drupal module"
- "Check my test coverage"
- "Find SOLID violations in my codebase"
- "Check for code duplication"

## Requirements

- DDEV environment
- Drupal 10.3+ or 11.x project
- PHP 8.2+

## Tools Used

| Tool | Version | Purpose |
|------|---------|---------|
| phpstan/phpstan | 2.x | Static analysis |
| mglaman/phpstan-drupal | Latest | Drupal-specific rules |
| phpmd/phpmd | Latest | Code smells |
| systemsdk/phpcpd | 8.x | Copy-paste detection |
| mglaman/drupal-check | 1.5+ | Deprecation checks |
| drupal/coder | 9.x | Coding standards |

## License

MIT
