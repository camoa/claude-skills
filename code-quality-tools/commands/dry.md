---
description: Check code duplication (DRY principle) for Drupal/Next.js projects
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# DRY Check (Duplication Detection)

Find duplicated code blocks that violate the DRY (Don't Repeat Yourself) principle.

## Usage

```
/code-quality:dry [project-path]
```

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Scans for duplicated code blocks
3. Reports duplication percentage
4. Suggests refactoring opportunities

## DRY Principle

**Don't Repeat Yourself** - Every piece of knowledge should have a single, unambiguous representation in the system.

Duplication leads to:
- Maintenance burden (change in multiple places)
- Inconsistency bugs
- Larger codebase

## Detection Tools

**Drupal:**
- PHPCPD (PHP Copy/Paste Detector)
- Minimum lines: 5 (configurable)
- Minimum tokens: 70 (configurable)

**Next.js:**
- jscpd (JavaScript/TypeScript copy-paste detector)
- Configurable thresholds
- Supports JSX, TSX

## Detection & Execution

!cd skills/code-quality-audit && bash scripts/core/detect-project.sh

Based on detection result, executes:
- **Drupal**: `bash scripts/drupal/dry-check.sh`
- **Next.js**: `bash scripts/nextjs/dry-check.sh`

## Duplication Thresholds

Default: Duplication > 5% triggers warning

To customize, create `.code-quality.json`:
```json
{
  "thresholds": {
    "duplication": 3
  }
}
```

## Output

- JSON report: `.reports/dry.json`
- Duplication percentage
- Duplicated blocks with file locations
- Refactoring suggestions (extract method, create utility)

## Refactoring Strategies

1. **Extract Method** - Move duplicate code to shared function
2. **Extract Class** - Create utility class for common operations
3. **Use Inheritance** - DRY via parent class
4. **Composition** - Inject shared behavior

## Error Handling

Common issues:
- **"Tool not found"**: Run `/code-quality:setup`
- **"High duplication"**: Prioritize by impact (frequently changed code first)

See: `references/troubleshooting.md#dry-check-issues`

## Related Commands

- `/code-quality:audit` - Full audit (includes DRY)
- `/code-quality:solid` - Architecture check (related)
