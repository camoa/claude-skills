# Coverage Metrics Reference

Test coverage measurement and interpretation for Drupal projects.

> **Online Dev-Guides:** For coverage strategy, quality gates, and metrics interpretation beyond tool configuration, see https://camoa.github.io/dev-guides/drupal/tdd/coverage-metrics-strategy/ and https://camoa.github.io/dev-guides/drupal/tdd/quality-gates-audit-checklist/.

## Coverage Types

| Type | What It Measures | Tool Support |
|------|------------------|--------------|
| **Line Coverage** | Lines executed by tests | PCOV, Xdebug |
| **Branch Coverage** | Decision branches taken | Xdebug only |
| **Path Coverage** | Execution paths through code | Xdebug only |
| **Function Coverage** | Functions called by tests | Both |

**Recommendation:** Use line coverage for speed. Use branch coverage for critical code.

## PCOV vs Xdebug

| Feature | PCOV | Xdebug 3 |
|---------|------|----------|
| Speed | 2-5x faster | Slower |
| Line coverage | Yes | Yes |
| Branch coverage | No | Yes |
| Path coverage | No | Yes |
| Memory usage | Lower | Higher |
| Best for | CI/CD, daily use | Deep analysis |
| Overhead when disabled | None | Some |

### When to Choose Each

**Choose PCOV when:**
- Running tests in CI/CD pipelines (speed matters)
- Daily development test runs
- Line coverage is sufficient
- You want minimal performance impact

**Choose Xdebug when:**
- Need branch/path coverage for critical code
- Also need debugging/profiling capabilities
- Doing deep analysis before releases

### Performance When Disabled

**PCOV**: Zero overhead when disabled (`pcov.enabled=0`). Safe to have installed but disabled - only adds overhead when explicitly enabled for coverage runs.

**Xdebug**: Has some overhead even when disabled. Mode switching (`XDEBUG_MODE=off`) reduces but doesn't eliminate impact. Consider removing in production environments.

### PCOV Setup (DDEV)

First, check your PHP version:
```bash
ddev exec php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;"
```

Add to `.ddev/config.yaml` (replace `8.3` with your actual PHP version):
```yaml
webimage_extra_packages:
  - php8.3-pcov
```

Then restart:
```bash
ddev restart
```

> **Note**: DDEV uses Debian with system PHP packages. Use the version-specific package name (e.g., `php8.3-pcov`), not a variable.

### Running with PCOV

```bash
# Enable PCOV for coverage
ddev exec php -d pcov.enabled=1 \
    -d pcov.directory=/var/www/html/web/modules/custom \
    vendor/bin/phpunit \
    --coverage-text \
    --coverage-clover reports/coverage.xml
```

### Running with Xdebug (Branch Coverage)

```bash
# Switch to Xdebug mode
ddev xdebug on

# Run with branch coverage
XDEBUG_MODE=coverage ddev exec vendor/bin/phpunit \
    --coverage-html reports/coverage \
    --path-coverage
```

**Note:** PCOV and Xdebug are mutually exclusive.

## Coverage Thresholds

| Level | Line Coverage | Use Case |
|-------|---------------|----------|
| **Minimum** | 70% | CI gate - fail build below |
| **Target** | 80% | Goal for new code |
| **Excellent** | 90%+ | Mature, critical systems |

### Environment Variables

```bash
export COVERAGE_MINIMUM=70   # CI gate
export COVERAGE_TARGET=80    # Goal
```

## PHPUnit Configuration

### phpunit.xml Coverage Settings

```xml
<?xml version="1.0" encoding="UTF-8"?>
<phpunit xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:noNamespaceSchemaLocation="vendor/phpunit/phpunit/phpunit.xsd"
         bootstrap="web/core/tests/bootstrap.php"
         colors="true">

    <testsuites>
        <testsuite name="unit">
            <directory>web/modules/custom/*/tests/src/Unit</directory>
        </testsuite>
        <testsuite name="kernel">
            <directory>web/modules/custom/*/tests/src/Kernel</directory>
        </testsuite>
    </testsuites>

    <source>
        <include>
            <directory suffix=".php">web/modules/custom</directory>
        </include>
        <exclude>
            <directory>web/modules/custom/*/tests</directory>
            <directory>web/modules/custom/*/.module</directory>
        </exclude>
    </source>

    <coverage>
        <report>
            <clover outputFile="reports/coverage/clover.xml"/>
            <html outputDirectory="reports/coverage/html"/>
            <text outputFile="php://stdout"/>
        </report>
    </coverage>
</phpunit>
```

## Coverage Reports

### Clover XML (CI Integration)

```bash
ddev exec vendor/bin/phpunit --coverage-clover reports/coverage.xml
```

Used by: Codecov, Coveralls, SonarQube

### HTML Report (Manual Review)

```bash
ddev exec vendor/bin/phpunit --coverage-html reports/coverage
```

Open `reports/coverage/index.html` in browser.

### Text Report (Console)

```bash
ddev exec vendor/bin/phpunit --coverage-text
```

Output:
```
Code Coverage Report:
  Lines:   72.34% (123/170)
  Methods: 65.00% (13/20)
  Classes: 75.00% (3/4)
```

## Interpreting Coverage

### What High Coverage Means

- Lines are executed during tests
- Basic happy paths are tested
- Code is reachable

### What High Coverage Does NOT Mean

- Code is correct
- All edge cases are tested
- Tests are meaningful
- No bugs exist

### Quality vs Quantity

**Bad test with 100% coverage:**
```php
public function testProcess(): void {
    $result = $service->process(['data']);
    $this->assertNotNull($result); // Weak assertion
}
```

**Good test with same coverage:**
```php
public function testProcess_withValidData_returnsExpectedStructure(): void {
    $result = $service->process(['title' => 'Test']);

    $this->assertIsArray($result);
    $this->assertArrayHasKey('processed_title', $result);
    $this->assertEquals('Processed: Test', $result['processed_title']);
}
```

## Coverage Strategy

### Focus Areas (Test Thoroughly)

- **Services with business logic** - 90%+ coverage
- **API controllers** - 85%+ coverage
- **Form validation** - 85%+ coverage
- **Security-related code** - 95%+ coverage
- **Data transformations** - 90%+ coverage

### Lower Priority

- **Getters/setters** - 50-70% acceptable
- **Simple CRUD** - 60-70% acceptable
- **Configuration forms** - 50-70% acceptable
- **Event subscribers** - 60-70% acceptable

### What to Skip

- **Third-party code** - Exclude from coverage
- **Generated code** - Exclude from coverage
- **Tests themselves** - Exclude from coverage

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Run tests with coverage
  run: |
    ddev exec php -d pcov.enabled=1 \
      vendor/bin/phpunit \
      --coverage-clover coverage.xml

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: coverage.xml
    fail_ci_if_error: true
    token: ${{ secrets.CODECOV_TOKEN }}
```

### Coverage Gate

```yaml
- name: Check coverage threshold
  run: |
    COVERAGE=$(grep -oP 'line-rate="\K[\d.]+' coverage.xml | head -1)
    COVERAGE_PCT=$(echo "$COVERAGE * 100" | bc)
    if (( $(echo "$COVERAGE_PCT < 70" | bc -l) )); then
      echo "Coverage $COVERAGE_PCT% is below 70% minimum"
      exit 1
    fi
```

## JSON Report Format

```json
{
  "line_coverage": 72.3,
  "branch_coverage": null,
  "files_analyzed": 45,
  "files_covered": 38,
  "uncovered_files": [
    {"file": "src/Service/Uncovered.php", "coverage": 45}
  ],
  "test_count": 47,
  "tests_passed": 45,
  "tests_failed": 2,
  "status": "warning",
  "thresholds": {
    "minimum": 70,
    "target": 80
  }
}
```

## Resources

- [PHPUnit Code Coverage](https://docs.phpunit.de/en/10.5/code-coverage.html)
- [PCOV vs Xdebug Comparison](https://thephp.cc/articles/pcov-or-xdebug)
- [Codecov with GitHub Actions](https://about.codecov.io/blog/measuring-php-code-coverage-with-phpunit-and-github-actions/)
