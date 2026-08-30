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
    --level="$(jq -r '.phpstan.level' .code-quality.json)" \
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
    --extensions=php,module,inc,install,profile,theme,engine \
    web/modules/custom

# Fix
ddev exec vendor/bin/phpcbf \
    --standard=Drupal \
    --extensions=php,module,inc,install,profile,theme,engine \
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
ddev exec vendor-bin/phpmd/vendor/bin/phpmd \
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
ddev exec vendor-bin/phpcpd/vendor/bin/phpcpd \
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
# Install the project-scope tools: the analysers that resolve the project's own classes.
# The constraints are ranges because drupal/core-dev pins the same packages; a bare
# ^9.0 or ^2.0 does not install on a Drupal site that has it.
ddev composer require --dev \
    "phpstan/phpstan:^1.12.4||^2.0" \
    phpstan/extension-installer:^1.4 \
    "mglaman/phpstan-drupal:^1.2.12||^2.1.2" \
    "phpstan/phpstan-deprecation-rules:^1.2||^2.0" \
    "drupal/coder:^8.3.30||^9.0"

# Install the isolated-scope tools: one bin namespace each, so their dependency trees
# never have to agree with the site's.
ddev composer require --dev bamarni/composer-bin-plugin:^1.9
ddev composer config extra.bamarni-bin.forward-command true
ddev composer bin phpmd require --dev phpmd/phpmd:^2.15
ddev composer bin phpcpd require --dev systemsdk/phpcpd:^9.0

# Run all checks
ddev exec vendor/bin/phpstan analyse web/modules/custom
ddev exec vendor-bin/phpmd/vendor/bin/phpmd web/modules/custom text cleancode,codesize
ddev exec vendor-bin/phpcpd/vendor/bin/phpcpd web/modules/custom
ddev exec vendor/bin/phpcs --standard=Drupal --extensions=php,module,inc,install,profile,theme,engine web/modules/custom
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

## Tool Versions

### PHP Ecosystem

The table below is GENERATED. `Installed as` is the constraint
`skills/code-quality-audit/schema/tool-catalog.json` resolves, so this table cannot
disagree with what the installer installs; the version, PHP requirement and date come
from `schema/upstream-versions.json`. Edit those two files and run `make tool-versions`.

The date is per row, never over the table. The heading used to carry one month-year stamp
while two of its six rows had gone wrong, and nothing said which rows had been re-read.

<!-- BEGIN GENERATED: tool-versions -->
<!-- Generated from skills/code-quality-audit/schema/tool-catalog.json (package and
     constraint) and schema/upstream-versions.json (version, PHP floor, checked date).
     Do not modify this region directly; edit those two files and run `make tool-versions`.
     `make claims` fails when this region and the schemas disagree. -->

| Tool | Package | Installed as | Upstream latest | PHP requirement | Checked |
|---|---|---|---|---|---|
| `phpstan` | phpstan/phpstan | `^1.12.4||^2.0` | 2.2.9 (2026-08-22) | `^7.4\|^8.0` | 2026-08-28 |
| `phpstan-extension-installer` | phpstan/extension-installer | `^1.4` | 1.4.3 (2024-09-04) | `^7.2 \|\| ^8.0` | 2026-08-28 |
| `phpstan-drupal` | mglaman/phpstan-drupal | `^1.2.12||^2.1.2` | 2.1.2 (2026-08-13) | `^8.1` | 2026-08-28 |
| `phpstan-deprecation-rules` | phpstan/phpstan-deprecation-rules | `^1.2||^2.0` | 2.0.5 (2026-07-22) | `^7.4 \|\| ^8.0` | 2026-08-28 |
| `coder` | drupal/coder | `^8.3.30||^9.0` | 9.0.1 (2026-06-21) | `>=7.4` | 2026-08-28 |
| `rector` | palantirnet/drupal-rector | `^0.20||^1.1` | 1.1.2 (2026-07-31) | not declared | 2026-08-28 |
| `phpunit` | drupal/core-dev | `*` | 11.4.5 (2026-08-06) | not declared | 2026-08-28 |
| `roave` | roave/security-advisories | `dev-master` | no tagged release | not declared | 2026-08-28 |
| `grumphp` | phpro/grumphp | `^2.0` | 2.23.0 (2026-07-22) | `~8.2.0 \|\| ~8.3.0 \|\| ~8.4.0 \|\| ~8.5.0` | 2026-08-28 |
| `phpmd` | phpmd/phpmd | `^2.15` | 2.15.0 (2023-12-11) | `>=5.3.9` | 2026-08-28 |
| `phpcpd` | systemsdk/phpcpd | `^9.0` | 9.0.0 (2026-03-08) | `>=8.4` | 2026-08-28 |
| `php-security-linter` | yousha/php-security-linter | `^3.1` | 3.1.8.6 (2026-08-17) | `>=8.2` | 2026-08-28 |
| `psalm` | vimeo/psalm | `^6.0` | 6.16.1 (2026-03-19) | `~8.1.31 \|\| ~8.2.27 \|\| ~8.3.16 \|\| ~8.4.3 \|\| ~8.5.0` | 2026-08-28 |
<!-- END GENERATED: tool-versions sha256:dcc22c2ff76b373e64392802da31243b4646ba63b914112055ba183e86fe169c -->

> **Note**: `mglaman/drupal-check` cannot be installed into a project this skill
> configures. Its 1.5.0 `composer.json` declares `mglaman/phpstan-drupal ^1.0.0` and
> `phpstan/phpstan-deprecation-rules ^1.0.0`, and declares no dependency on
> `phpstan/phpstan` at all. PHPStan 1.x arrives transitively, because phpstan-drupal 1.x
> requires `phpstan/phpstan ^1.12`. This skill installs the PHPStan 2.x stack, so the two
> cannot resolve together. Use `phpstan/phpstan-deprecation-rules` with
> `mglaman/phpstan-drupal` 2.x instead.
>
> Upstream state, checked 2026-08-28: not marked abandoned on Packagist, not archived on
> GitHub, latest release 1.5.0 (2024-08-14). The constraint above is the reason to reach
> for something else; the project's health is not.

> **phpstan-drupal 2.1.0 raises the floor.** Nine rules that were opt-in are now on by
> default (`testClassSuffixNameRule`, `dependencySerializationTraitPropertyRule`,
> `accessResultConditionRule`, `cacheableDependencyRule`, `hookFormAlterRule`,
> `loggerFromFactoryPropertyAssignmentRule`, `entityStorageDirectInjectionRule`,
> `symfonyYamlParseRule`, `entityOperationsCacheabilityRule`), so the first run after
> upgrading reports more findings on unchanged code.
>
> **Breaking**: the `hookRules` config key is now `hookFormAlterRule`; PHPStan rejects a
> config that still uses the old key. Also new: `ContainerInterface::has()` returns
> `bool` rather than being inferred always-true, and a fixed inverted type check makes
> the `LoadIncludes` rule fire on code it used to skip.
>
> Disable an individual rule with `drupal: rules: <name>: false`. Do not silence these
> with `excludePaths` for `tests/`, `*.module` or `*.install`: those patterns leave
> several of the default rules with nothing to analyse. See
> `templates/drupal/phpstan.neon`.

### Node.js Ecosystem

| Tool | Version | Node Requirement |
|------|---------|------------------|
| ESLint | 9.x | Node 18+ |
| Jest | 29.x | Node 16+ |
| jscpd | 4.x | Node 16+ |
| TypeScript | 5.x | Node 16+ |
