---
description: Check test coverage for Drupal/Next.js projects. Use when user says "test coverage", "what's untested", "coverage report", "missing tests", "how much is covered", "PHPUnit coverage", "Jest coverage". Shows coverage percentage and identifies uncovered code.
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# Test Coverage Check

Run test coverage analysis and generate coverage reports.

## Usage

```
/code-quality:coverage [project-path]
/code-quality:coverage --changed <src.php> [src2.php ...]
```

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Runs test suite with coverage enabled
3. Generates coverage reports
4. Displays coverage percentage and uncovered areas

### --changed mode

Scopes coverage analysis to the changed source files only — suitable for
per-WO gate runs where whole-project coverage would report pre-existing debt.

```
# Coverage for a single changed source
/code-quality:coverage --changed web/modules/custom/my_mod/src/Service/MyService.php

# Multiple changed files (typical CI/gate usage)
/code-quality:coverage --changed $(cat .changed-files.txt)
```

What happens:
- Maps each changed `src/*.php` to its co-located `tests/src/{Unit,Kernel}/…/*Test.php`
- Runs only the mapped test files (not the full suite)
- Passes `--coverage-filter <src_file>` for each changed source so coverage is
  reported only for the changed code, not the whole module or project
- Records sources with no co-located test as **coverage gaps** (informational, not failures)

**Mapping convention (Drupal):**

```
changed  web/modules/custom/<mod>/src/<Dir>/Foo.php
→ Unit   web/modules/custom/<mod>/tests/src/Unit/<Dir>/FooTest.php
→ Kernel web/modules/custom/<mod>/tests/src/Kernel/<Dir>/FooTest.php
```

**Mapping limit — PHPUnit has no `--findRelatedTests`:**

> This flag exists in Jest (Next.js) and is used by the Next.js toolchain.
> PHPUnit has no equivalent. The Drupal mapping here is *structural* —
> it derives test paths from source paths by convention. It does NOT
> perform semantic analysis of import graphs or call sites.

Sources with no co-located `*Test.php` are recorded as **coverage gaps** in
the JSON report (`gaps` field). A gap is informational — it is **not a test failure**.
The no-`--changed` path runs the whole suite unchanged.

## Detection & Execution

!cd skills/code-quality-audit && bash scripts/core/detect-project.sh

Based on detection result, executes:
- **Drupal**: `bash scripts/drupal/coverage-report.sh` (PHPUnit with coverage)
- **Next.js**: `bash scripts/nextjs/coverage-report.sh` (Jest with coverage)

## Output

- JSON report: `.reports/coverage.json`
- HTML report: `.reports/coverage/index.html`
- Coverage percentage in chat

## Thresholds

Default coverage threshold: 80%

To customize, create `.code-quality.json`:
```json
{
  "thresholds": {
    "coverage": 85
  }
}
```

## Error Handling

Common issues:
- **"No tests found"**: Add tests to `tests/` directory
- **"Coverage tool not installed"**: Run `/code-quality:setup`

See: `references/troubleshooting.md#coverage-issues`

## Related Commands

- `/code-quality:audit` - Full audit (includes coverage)
- `/code-quality:tdd` - TDD workflow with coverage
