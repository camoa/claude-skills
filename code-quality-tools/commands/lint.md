---
description: Check code standards and linting for Drupal/Next.js projects
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# Lint Check

Check code against coding standards and style guidelines.

## Usage

```
/code-quality:lint [project-path]
```

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Runs linting checks
3. Reports style violations and standard breaches
4. Suggests fixes (many can be auto-fixed)

## Linting Tools

**Drupal:**
- Drupal Coder (Drupal coding standards)
- PHPCS (PHP_CodeSniffer)
- PHPStan (static analysis)
- Psalm (type checking)

**Next.js:**
- ESLint (JavaScript/TypeScript standards)
- Prettier (code formatting - optional)
- TypeScript compiler (type checking)

## Detection & Execution

!cd skills/code-quality-audit && bash scripts/core/detect-project.sh

Based on detection result, executes:
- **Drupal**: `bash scripts/drupal/lint-check.sh`
- **Next.js**: `bash scripts/nextjs/lint-check.sh`

## Auto-Fix

Many violations can be auto-fixed:

**Drupal:**
```bash
ddev exec phpcbf --standard=Drupal,DrupalPractice web/modules/custom/
```

**Next.js:**
```bash
npm run lint -- --fix
```

## Output

- JSON report: `.reports/lint.json`
- Violations by file with line numbers
- Auto-fix suggestions

## Error Handling

Common issues:
- **"Linter not found"**: Run `/code-quality:setup`
- **"Too many violations"**: Start with auto-fix, then review remaining

See: `references/troubleshooting.md#linting-issues`

## Related Commands

- `/code-quality:audit` - Full audit (includes linting)
- `/code-quality:setup` - Install linting tools
