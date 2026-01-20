---
description: Check test coverage for Drupal/Next.js projects
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# Test Coverage Check

Run test coverage analysis and generate coverage reports.

## Usage

```
/code-quality:coverage [project-path]
```

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Runs test suite with coverage enabled
3. Generates coverage reports
4. Displays coverage percentage and uncovered areas

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
