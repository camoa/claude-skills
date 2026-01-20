---
description: Run complete code quality and security audit for Drupal/Next.js projects
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# Code Quality Audit

Run a comprehensive code quality and security audit on your project.

## Usage

```
/code-quality:audit [project-path]
```

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Runs full audit suite (all 22 operations)
3. Generates reports in `.reports/` directory
4. Displays summary in chat

## Detection & Execution

!cd skills/code-quality-audit && bash scripts/core/detect-project.sh

Based on detection result, executes:
- **Drupal**: `bash scripts/core/full-audit.sh` (via DDEV)
- **Next.js**: `bash scripts/core/full-audit.sh` (via npm/yarn)

## Output

- JSON reports: `.reports/*.json`
- Markdown summary: `.reports/audit-summary.md`
- Chat summary with key findings

## Error Handling

If audit fails, see:
- Error messages with recovery guidance
- Troubleshooting: `references/troubleshooting.md`

## Related Commands

- `/code-quality:coverage` - Test coverage only
- `/code-quality:security` - Security audit only
- `/code-quality:lint` - Linting check only
