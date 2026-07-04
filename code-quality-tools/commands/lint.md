---
description: Check code standards and linting for Drupal/Next.js projects. Use when user says "lint this", "check standards", "coding standards", "PHPCS", "ESLint", "code style", "Drupal Coder", "Prettier". Validates code against project coding standards.
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# Lint Check

Check code against coding standards and style guidelines.

## Usage

```
/code-quality-tools:lint [project-path]
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

## Change-Scoped Mode (`--changed`)

Pass a newline-delimited file of changed paths to scope `phpcs` to those files only:

```bash
bash scripts/drupal/lint-check.sh --changed .changed-files.txt
```

Behaviour:
- Filters the list to lintable extensions (`.php .module .inc .install .profile .theme .engine .js`) and excludes `vendor/`, `web/core/`, `*/contrib/*`.
- If the filtered set is empty → exits `0` with status `skipped` (no whole-tree scan).
- Report gains `"mode": "changed"` and `"relevant_files": N`.
- The `--fix` flag is **not** supported in `--changed` mode; use the full-path invocation for auto-fix.
- Compatible with CI patterns: `bash scripts/drupal/lint-check.sh --changed .changed-files.txt`

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
- **"Linter not found"**: Run `/code-quality-tools:setup`
- **"Too many violations"**: Start with auto-fix, then review remaining

See: `references/troubleshooting.md#linting-issues`

## Related Commands

- `/code-quality-tools:audit` - Full audit (includes linting)
- `/code-quality-tools:setup` - Install linting tools
