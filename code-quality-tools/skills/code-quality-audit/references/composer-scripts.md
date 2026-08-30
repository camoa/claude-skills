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
    "test:coverage-html": "php -d pcov.enabled=1 vendor/bin/phpunit --coverage-html ${REPORT_DIR:-build/coverage}",

    "quality:phpstan": "phpstan analyse web/modules/custom",
    "quality:phpmd": "phpmd web/modules/custom text phpmd.xml",
    "quality:dry": "phpcpd web/modules/custom --min-lines=10",
    "quality:cs": "phpcs --standard=Drupal,DrupalPractice --extensions=php,module,inc,install,profile,theme,engine web/modules/custom",
    "quality:all": ["@quality:phpstan", "@quality:phpmd", "@quality:dry"]
  }
}
```

## Coverage output location

`test:coverage-html` is the project's own PHPUnit target, not a plugin report, so nothing resolves a directory for it. It honours `REPORT_DIR` when this plugin's scripts set one, which keeps HTML coverage out of the repository on an audit run. Run bare, it falls back to `build/coverage` in the working directory — gitignore that path if you keep it. The plugin's own coverage gate (`scripts/{drupal,nextjs}/coverage-report.sh`) does not use this script and always writes to the resolved report directory.

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
