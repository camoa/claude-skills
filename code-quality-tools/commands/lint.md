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

!bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/detect-project.sh"

Based on detection result, executes:
- **Drupal**: `bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/lint-check.sh"`
- **Next.js**: `bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/nextjs/lint-check.sh"`

## Change-Scoped Mode (`--changed`)

Pass a newline-delimited file of changed paths to scope `phpcs` to those files only:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/lint-check.sh" --changed .changed-files.txt
```

Behaviour:
- Filters the list to lintable extensions (`.php .module .inc .install .profile .theme .engine .js`) and excludes `vendor/`, `web/core/`, `*/contrib/*`.
- If the filtered set is empty → exits `0` with status `skipped` (no whole-tree scan).
- If every named file is missing from disk → exits `4` with status `unmeasured`. Nothing
  was checked, and this is not a skip: the gate was asked about files it could not read.
- If SOME named files are missing → exits `1` with status `partial` and `paths_missing[]`
  naming them. What was read is clean; the set was not fully covered. A finding in the
  files that WERE read still wins, and still exits `2`.
- Report gains `"mode": "changed"` and `"relevant_files": N`.
- The `--fix` flag is **not** supported in `--changed` mode; use the full-path invocation for auto-fix.
- Compatible with CI patterns: `bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/lint-check.sh" --changed .changed-files.txt`

## Exit codes and status words

| exit | `.status` | means |
|---|---|---|
| 0 | `pass` | phpcs ran over the scoped paths and found nothing |
| 0 | `skipped` | nothing lintable was in scope (a docs-only changed set) |
| 1 | `warning` | more than 10 warnings, no errors |
| 1 | `partial` | `--changed` only: some named files were not on disk |
| 2 | `fail` | errors found |
| 4 | `unmeasured` | phpcs produced no usable report, or every path it was given is absent. **Nothing was checked** |

A CI gate that reads only the error count treats `unmeasured` and `partial` as clean,
because both carry zero errors by construction. Gate on `.status` first:

```bash
STATUS=$(jq -r '.status' lint-report.json)
case "$STATUS" in
  unmeasured|partial) echo "lint did not cover its ground (${STATUS})"; exit 1 ;;
  fail)               exit 1 ;;
esac
```

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

- JSON report: `$REPORT_DIR/lint-report.json`, plus per-tool raw output under `$REPORT_DIR/lint/` (`$REPORT_DIR` is announced by the script on start; it is not inside the audited repository)
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
