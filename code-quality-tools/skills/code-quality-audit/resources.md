# External Resources

Links to official documentation and learning resources.

## Official Documentation

### PHP Tools

- [PHPStan User Guide](https://phpstan.org/user-guide/getting-started)
- [PHPStan Rule Levels](https://phpstan.org/user-guide/rule-levels)
- [PHPMD Rules](https://phpmd.org/rules/)
- [PHPUnit Code Coverage](https://docs.phpunit.de/en/10.5/code-coverage.html)

### Drupal-Specific

- [phpstan-drupal](https://github.com/mglaman/phpstan-drupal)
- [drupal-check](https://github.com/mglaman/drupal-check)
- [Drupal Coder](https://www.drupal.org/project/coder)
- [Drupal Testing Documentation](https://www.drupal.org/docs/develop/automated-testing)

### Coverage Tools

- [PCOV Documentation](https://github.com/krakjoe/pcov)
- [PCOV vs Xdebug Comparison](https://thephp.cc/articles/pcov-or-xdebug)
- [Codecov Setup](https://about.codecov.io/blog/measuring-php-code-coverage-with-phpunit-and-github-actions/)

## Learning Resources

### TDD

- [Oliver Davies: TDD in Drupal](https://www.oliverdavies.uk/blog/writing-new-drupal-8-module-using-test-driven-development-tdd)
- [Drupal Commerce: Test Types](https://drupalcommerce.org/blog/45322/commerce-2x-unit-kernel-and-functional-tests-oh-my)

### SOLID Principles

- [SOLID in Drupal](https://drupal.com.ua/152/mastering-oop-and-solid-principles-php-drupal-examples-complete-guide)
- [Matt Glaman: DI Anti-Patterns](https://mglaman.dev/blog/dependency-injection-anti-patterns-drupal)
- [Drupal Services and DI](https://www.drupal.org/docs/drupal-apis/services-and-dependency-injection)

### DRY Principle

- [Sandi Metz: The Wrong Abstraction](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction)
- [SensioLabs: DRY Balance](https://sensiolabs.com/blog/2025/the-dry-principle-finding-the-delicate-balance-between-code-reuse-and-clarity)
- [Drupalize.me: Traits in Drupal](https://drupalize.me/blog/peek-traits-drupal-8)

## Packages

### Required (Drupal)

```bash
composer require --dev \
  phpstan/phpstan \
  phpstan/extension-installer \
  mglaman/phpstan-drupal \
  phpstan/phpstan-deprecation-rules \
  phpmd/phpmd \
  systemsdk/phpcpd \
  mglaman/drupal-check \
  drupal/coder
```

### Optional

- [PHPMetrics](https://github.com/phpmetrics/PhpMetrics) - Visual reports
- [Psalm](https://psalm.dev/) - Alternative static analyzer
- [Rector](https://getrector.org/) - Automated refactoring

## CI/CD Services

- [Codecov](https://codecov.io/) - Coverage reporting
- [Coveralls](https://coveralls.io/) - Coverage reporting
- [SonarQube](https://www.sonarqube.org/) - All-in-one analysis
