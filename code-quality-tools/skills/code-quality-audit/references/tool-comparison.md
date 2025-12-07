# Tool Comparison Reference

Mapping of code quality tools between Drupal and Next.js ecosystems.

## Quick Reference

| Purpose | Drupal (PHP) | Next.js (TypeScript) |
|---------|--------------|----------------------|
| Test runner | PHPUnit | Jest / Vitest |
| Coverage | PCOV / Xdebug | c8 / Istanbul |
| Static analysis | PHPStan | TypeScript strict |
| Linting | PHP_CodeSniffer | ESLint |
| Code smells | PHPMD | ESLint plugins |
| Duplication | PHPCPD | jscpd |
| Deprecations | phpstan-deprecation-rules | ESLint rules |

## Static Analysis

### PHPStan (Drupal)

**Purpose:** Type safety, bug detection
**SOLID:** LSP, DIP detection

```bash
ddev exec vendor/bin/phpstan analyse \
    --level=8 \
    --error-format=json \
    web/modules/custom
```

**Levels:** 0-10 (10 = strictest)

### TypeScript Strict Mode (Next.js)

**Purpose:** Type safety, bug detection
**SOLID:** LSP detection

```json
// tsconfig.json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true
  }
}
```

## Linting / Coding Standards

### PHP_CodeSniffer + Drupal Coder

**Purpose:** Coding standards enforcement

```bash
# Check
ddev exec vendor/bin/phpcs \
    --standard=Drupal,DrupalPractice \
    web/modules/custom

# Fix
ddev exec vendor/bin/phpcbf \
    --standard=Drupal \
    web/modules/custom
```

### ESLint (Next.js)

**Purpose:** Linting, code quality rules

```bash
npx eslint src/ --ext .ts,.tsx
```

```json
// .eslintrc.json
{
  "extends": [
    "next/core-web-vitals",
    "@typescript-eslint/recommended"
  ]
}
```

## Code Smell Detection

### PHPMD

**Purpose:** Complexity, design issues
**SOLID:** SRP detection

```bash
ddev exec vendor/bin/phpmd \
    web/modules/custom \
    json \
    cleancode,codesize,design
```

**Rulesets:**
- `cleancode` - Static access, boolean params
- `codesize` - Complexity, method length
- `design` - Coupling, depth of inheritance
- `naming` - Variable/method naming
- `unusedcode` - Dead code

### ESLint Plugins (Next.js)

**Purpose:** Similar checks for TypeScript

```bash
npm install -D \
    eslint-plugin-sonarjs \
    eslint-plugin-import
```

**SonarJS rules:**
- `cognitive-complexity`
- `no-duplicate-string`
- `no-identical-functions`

## Duplication Detection

### PHPCPD (PHP)

**Package:** `systemsdk/phpcpd`

```bash
ddev exec vendor/bin/phpcpd \
    --min-lines=10 \
    --min-tokens=70 \
    web/modules/custom
```

### jscpd (JavaScript/TypeScript)

```bash
npm install -D jscpd
npx jscpd src/ --min-lines 10 --reporters json
```

```json
// .jscpd.json
{
  "threshold": 5,
  "reporters": ["json", "console"],
  "ignore": ["**/*.test.ts", "**/node_modules/**"]
}
```

## Test Coverage

### PHPUnit + PCOV (Drupal)

```bash
ddev exec php -d pcov.enabled=1 \
    vendor/bin/phpunit \
    --coverage-clover coverage.xml
```

### Jest + c8 (Next.js)

```bash
npx jest --coverage --coverageReporters=json
```

```json
// jest.config.js
module.exports = {
  collectCoverageFrom: [
    'src/**/*.{ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/*.test.{ts,tsx}'
  ],
  coverageThreshold: {
    global: {
      lines: 70
    }
  }
}
```

## All-in-One Solutions

### SonarQube (Both)

- Unified dashboard for PHP and TypeScript
- Historical trends
- Quality gates
- CI/CD integration

```yaml
# sonar-project.properties
sonar.projectKey=my-project
sonar.sources=web/modules/custom,src
sonar.php.coverage.reportPaths=coverage.xml
sonar.javascript.lcov.reportPaths=coverage/lcov.info
```

### PHPMetrics (Drupal Only)

Visual reports with complexity graphs.

```bash
ddev exec vendor/bin/phpmetrics \
    --report-html=metrics \
    web/modules/custom
```

## CI/CD Commands Summary

### Drupal Project

```bash
# Install all tools
ddev composer require --dev \
    phpstan/phpstan \
    phpstan/extension-installer \
    mglaman/phpstan-drupal \
    phpstan/phpstan-deprecation-rules \
    phpmd/phpmd \
    systemsdk/phpcpd \
    drupal/coder

# Run all checks
ddev exec vendor/bin/phpstan analyse web/modules/custom
ddev exec vendor/bin/phpmd web/modules/custom text cleancode,codesize
ddev exec vendor/bin/phpcpd web/modules/custom
ddev exec vendor/bin/phpcs --standard=Drupal web/modules/custom
ddev exec vendor/bin/phpunit --coverage-clover coverage.xml
```

### Next.js Project

```bash
# Install all tools
npm install -D \
    jest \
    eslint \
    @typescript-eslint/eslint-plugin \
    jscpd \
    eslint-plugin-sonarjs

# Run all checks
npx tsc --noEmit
npx eslint src/
npx jscpd src/
npx jest --coverage
```

## Tool Versions (December 2025)

### PHP Ecosystem

| Tool | Version | PHP Requirement |
|------|---------|-----------------|
| PHPStan | 2.x | PHP 7.4+ |
| phpstan-deprecation-rules | Latest | PHP 7.4+ |
| PHPMD | Latest | PHP 8.1+ |
| PHPCPD | 8.x | PHP 8.3+ |
| Drupal Coder | 9.x | PHP 8.1+ |

> **Note**: `mglaman/drupal-check` is deprecated. Use `phpstan/phpstan-deprecation-rules` instead.

### Node.js Ecosystem

| Tool | Version | Node Requirement |
|------|---------|------------------|
| ESLint | 9.x | Node 18+ |
| Jest | 29.x | Node 16+ |
| jscpd | 4.x | Node 16+ |
| TypeScript | 5.x | Node 16+ |
