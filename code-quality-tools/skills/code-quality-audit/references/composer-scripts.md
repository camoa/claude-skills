# Composer Scripts Reference

Recommended composer scripts for quality tools integration.

## Basic Scripts

Add to `composer.json`:

```json
{
  "scripts": {
    "test": "phpunit",
    "test:unit": "phpunit --testsuite unit",
    "test:kernel": "phpunit --testsuite kernel",
    "test:coverage": "php -d pcov.enabled=1 vendor/bin/phpunit --coverage-text",
    "test:coverage-html": "php -d pcov.enabled=1 vendor/bin/phpunit --coverage-html .reports/coverage",

    "quality:phpstan": "phpstan analyse web/modules/custom",
    "quality:phpmd": "phpmd web/modules/custom text phpmd.xml",
    "quality:dry": "phpcpd web/modules/custom --min-lines=10",
    "quality:cs": "phpcs --standard=Drupal,DrupalPractice web/modules/custom",
    "quality:all": ["@quality:phpstan", "@quality:phpmd", "@quality:dry"]
  }
}
```

## Usage

```bash
# Run all quality checks
ddev composer quality:all

# Individual checks
ddev composer quality:phpstan
ddev composer quality:phpmd
ddev composer quality:dry

# Tests with coverage
ddev composer test:coverage
```

## CI Integration

For CI/CD, use exit codes:
- `composer quality:all` returns non-zero if any check fails
- Chain with `&&` for fail-fast: `composer quality:phpstan && composer test`

## Custom Module Path

If modules are elsewhere, update paths:

```json
{
  "scripts": {
    "quality:phpstan": "phpstan analyse docroot/modules/custom"
  }
}
```
