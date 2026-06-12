---
description: Check code duplication (DRY principle) for Drupal/Next.js projects. Use when user says "find duplicates", "DRY check", "copy paste detection", "code duplication", "repeated code", "PHPCPD", "jscpd". Identifies duplicated code blocks and suggests consolidation.
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# DRY Check (Duplication Detection)

Find duplicated code blocks that violate the DRY (Don't Repeat Yourself) principle.

> **Reading strategy:** This is **Type B** work — duplicate detection often reveals near-duplicates that need full-file context to assess intent. Do NOT grep-first. See `https://camoa.github.io/dev-guides/development/reading-strategy/`.

## LSP Code Intelligence (recommended)

PHPCPD and jscpd detect **textual** clones. If a code-intelligence plugin is installed (`php-lsp` for Drupal, `typescript-lsp` for Next.js), also use the **LSP tool**'s `find-references` to catch **semantic** duplication the copy-paste detectors miss — e.g. the same service resolved inline at 14 call sites is a DRY/DIP violation even though the surrounding text differs at every site.

The LSP tool needs no permission and is inert when no plugin is installed — fall back to the copy-paste detectors and full-file reads when it is unavailable. See `skills/code-quality-audit/references/code-intelligence.md`.

## Usage

```
/code-quality:dry [project-path] [--changed <file>]
```

`--changed <file>`: path to a newline-delimited list of changed files (e.g. from
`git diff --name-only`). When supplied, the scan stays **whole-tree** (necessary
because a clone needs both copies; scoping the scan to the diff would silently miss
"you duplicated existing code"). The **verdict** is filtered: only clones where ≥1
file location appears in the changed-files list are **failing**. Clones entirely
among unchanged files are recorded **informationally** and do not fail the gate.
Without `--changed`, every clone counts (original behavior, unchanged).

## What This Does

1. Auto-detects project type (Drupal or Next.js)
2. Scans for duplicated code blocks (**always whole-tree** — DRY is inherently cross-file)
3. Reports duplication percentage
4. Under `--changed`: filters verdict to change-touching clones; others are informational
5. Suggests refactoring opportunities

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
- **Drupal**: `bash scripts/drupal/dry-check.sh [--changed <file>]`
- **Next.js**: `bash scripts/nextjs/dry-check.sh`

### Change-scoped mode (per-WO gating)

When called from `/review` in headless/loop mode, the review command resolves the
merge-base diff and passes a changed-files list via `--changed`. DRY is **not**
scoped to the diff at scan time — both copies of a clone must be visible for the
check to be meaningful. Instead, the post-scan verdict is filtered:

| Clone | Verdict |
|-------|---------|
| ≥1 file in changed-files list | **FAIL** — fix before merging |
| All files outside changed-files list | **INFO** — pre-existing debt, not blocking |

Run without `--changed` (e.g. `/code-quality:audit`, `--full-audit`) to restore
whole-tree failing behavior on all clones.

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
