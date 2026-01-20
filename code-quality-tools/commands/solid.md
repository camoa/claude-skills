---
description: Check SOLID principles and architecture quality for Drupal/Next.js projects
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# SOLID Principles Check

Analyze code architecture and adherence to SOLID principles.

## Usage

```
/code-quality:solid [project-path]
```

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Analyzes code complexity and architecture
3. Checks SOLID principle violations
4. Reports cyclomatic complexity and coupling

## SOLID Principles Checked

- **S**ingle Responsibility Principle
- **O**pen/Closed Principle
- **L**iskov Substitution Principle
- **I**nterface Segregation Principle
- **D**ependency Inversion Principle

## Analysis Tools

**Drupal:**
- PHPStan (complexity analysis)
- PHPMD (mess detection, complexity thresholds)
- Psalm (type analysis)
- PHPCPD (duplication as indicator of SRP violations)

**Next.js:**
- ESLint complexity rules
- madge (circular dependencies, coupling)
- jscpd (duplication analysis)
- TypeScript compiler (type analysis)

## Detection & Execution

!cd skills/code-quality-audit && bash scripts/core/detect-project.sh

Based on detection result, executes:
- **Drupal**: `bash scripts/drupal/solid-check.sh`
- **Next.js**: `bash scripts/nextjs/solid-check.sh`

## Complexity Thresholds

Default: Cyclomatic complexity > 10 triggers warning

To customize, create `.code-quality.json`:
```json
{
  "thresholds": {
    "complexity": 15
  }
}
```

## Output

- JSON report: `.reports/solid.json`
- SOLID score (0-100)
- Violations by principle with examples
- Refactoring suggestions

## Error Handling

Common issues:
- **"High complexity everywhere"**: Start with highest offenders
- **"Tool not found"**: Run `/code-quality:setup`

See: `references/troubleshooting.md#solid-check-issues`

## Related Commands

- `/code-quality:audit` - Full audit (includes SOLID)
- `/code-quality:dry` - Check duplication (related to SRP)
