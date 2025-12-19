# Drupal Setup Operations

Setup and configuration operations for Drupal code quality tools.

## Contents

- [Operation 1: Setup Tools](#operation-1-setup-tools)
- [Operation 6: Module-Specific Audit](#operation-6-module-specific-audit)
- [Operation 7: Add Composer Scripts](#operation-7-add-composer-scripts)
- [Operation 8: CI Integration](#operation-8-ci-integration)

---

## Operation 1: Setup Tools

When user says "setup tools", "install PHPStan", "install testing tools":

1. Create `.reports/` directory, add to `.gitignore`
2. Check installed: `ddev exec vendor/bin/phpstan --version`
3. Install missing:
   ```bash
   ddev composer require --dev phpstan/phpstan phpstan/extension-installer \
     mglaman/phpstan-drupal phpstan/phpstan-deprecation-rules \
     phpmd/phpmd systemsdk/phpcpd drupal/coder
   ```
4. Copy templates to project root:
   - `templates/drupal/phpstan.neon` (PHPStan 2.x - extensions auto-load)
   - `templates/drupal/phpmd.xml`
   - `templates/drupal/phpunit.xml`
5. Ask coverage driver preference:

   | Option | Best For | Trade-off |
   |--------|----------|-----------|
   | **PCOV** | CI/CD, daily dev | 2-5x faster, line coverage only |
   | **Xdebug** | Deep analysis | Slower, has branch/path coverage |

   If PCOV: Check PHP version (`ddev exec php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;"`), add to `.ddev/config.yaml`:
   ```yaml
   webimage_extra_packages:
     - php8.3-pcov  # Use actual version
   ```
6. Show composer scripts (mandatory):
   ```bash
   ddev composer quality:all    # All checks
   ddev composer test:coverage  # Tests with coverage
   ddev composer quality:fix    # Auto-fix standards
   ```

---

## Operation 6: Module-Specific Audit

When user says "check {module_name}", "audit my_module":

1. Verify module exists: `ls -la web/modules/custom/{module_name}`
2. Run all checks scoped to that path
3. Save reports with prefix: `.reports/{module_name}-*.json`

---

## Operation 7: Add Composer Scripts

When user says "add composer scripts", "setup quality scripts":

1. Read existing `composer.json`
2. Detect modules path (`web/modules/custom` or `docroot/modules/custom`)
3. Add scripts (merge with existing):
   ```json
   {
     "scripts": {
       "test": "phpunit",
       "test:unit": "phpunit --testsuite unit",
       "test:kernel": "phpunit --testsuite kernel",
       "test:coverage": "php -d pcov.enabled=1 vendor/bin/phpunit --coverage-text",
       "quality:phpstan": "phpstan analyse {modules_path}",
       "quality:phpmd": "phpmd {modules_path} text phpmd.xml",
       "quality:dry": "phpcpd {modules_path} --min-lines=10",
       "quality:cs": "phpcs --standard=Drupal,DrupalPractice {modules_path}",
       "quality:all": ["@quality:phpstan", "@quality:phpmd", "@quality:dry"],
       "quality:fix": "phpcbf --standard=Drupal,DrupalPractice {modules_path}"
     }
   }
   ```
4. Show usage (mandatory):
   ```bash
   ddev composer quality:all    # All checks
   ddev composer test:coverage  # With coverage
   ddev composer quality:fix    # Auto-fix
   ```

---

## Operation 8: CI Integration

When user says "add to CI", "setup GitHub Actions":

1. Copy `templates/ci/github-drupal.yml` to `.github/workflows/quality.yml`
2. Explain pipeline: Lint → Static Analysis → Tests → Coverage (fails <70%)
