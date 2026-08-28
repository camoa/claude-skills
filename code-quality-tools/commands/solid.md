---
description: Check SOLID principles and architecture quality for Drupal/Next.js projects. Use when user says "SOLID check", "single responsibility", "architecture quality", "dependency inversion", "check principles", "code complexity", "find violations". For debated analysis, use /code-quality-tools:architecture-debate.
allowed-tools: Read, Bash, Grep, Glob
argument-hint: optional|project-path
---

# SOLID Principles Check

Analyze code architecture and adherence to SOLID principles.

> **Reading strategy:** This is **Type B** work — read full class hierarchies, interfaces, and service definitions; do NOT grep-first. SOLID violations span inherited methods that grep cannot see. See `https://camoa.github.io/dev-guides/development/reading-strategy/`.

## LSP Code Intelligence (recommended)

If a code-intelligence plugin is installed (`php-lsp` for Drupal, `typescript-lsp` for Next.js), prefer the **LSP tool** over grep for the relationship questions SOLID depends on:

- **Liskov / Interface Segregation** — `find-implementations` on an interface enumerates every subtype; check each override for contract compatibility. This is the exact check grep cannot do.
- **Dependency Inversion** — `find-references` on a concrete class shows whether high-level modules depend on it directly instead of on an abstraction.
- **Single Responsibility** — `call-hierarchy` gives real fan-in/fan-out instead of inferring "reasons to change" from file size.

The LSP tool needs no permission and is inert when no plugin is installed — **fall back to the full-file-read Type-B pass above** in that case. Setup and the Drupal `.module`/`.inc`/`.theme` indexing caveat: `skills/code-quality-audit/references/code-intelligence.md`.

## Usage

```
/code-quality-tools:solid [project-path]
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

!bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/detect-project.sh"

Based on detection result, executes:
- **Drupal**: `bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/solid-check.sh"`
- **Next.js**: `bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/nextjs/solid-check.sh"`

## Change-Scoped Mode (`--changed`)

Pass a newline-delimited file of changed paths to scope `phpstan`, `phpmd`, and the `\Drupal::` grep to those files only:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/solid-check.sh" --changed .changed-files.txt
```

Behaviour:
- Filters the list to PHP-family extensions (`.php .module .inc .install .profile .theme .engine`) and excludes `vendor/`, `web/core/`, `*/contrib/*`.
- If the filtered set is empty → exits `0` with status `skipped` (no whole-tree scan).
- If every named file is missing from disk → exits `4` with status `unmeasured`, and
  `tools_unmeasured[]` names the analyzers that had nothing to read.
- If SOME named files are missing → exits `1` with status `partial` and `paths_missing[]`
  naming them. A violation in the files that WERE read still wins, and still exits `2`.
- `phpmd` receives a comma-separated file list (its required format for file-level targeting).
- Report gains `"mode": "changed"` and `"relevant_files": N`.
- Compatible with CI patterns: `bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/solid-check.sh" --changed .changed-files.txt`

## Exit codes and status words

| exit | `.status` | means |
|---|---|---|
| 0 | `pass` | the analyzers ran over the scoped paths and found nothing |
| 0 | `skipped` | every analyzer is absent, or one that was present returned nothing usable |
| 1 | `warning` | more than 10 warnings, no criticals |
| 1 | `partial` | `--changed` only: some named files were not on disk |
| 2 | `fail` | critical violations found |
| 4 | `unmeasured` | the scanned path, or every file in the changed set, is not there. **Nothing was checked** |

`.phpstan_level` is the level the run actually used: the placed config's when there is
one, the flag's when there is not, and `null` when the config sets it somewhere this gate
cannot read (an `includes:` file). It is not always a number — `max` is valid — so a
consumer comparing it arithmetically has to check the type first.

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

- JSON report: `$REPORT_DIR/solid-report.json`, plus per-tool raw output under `$REPORT_DIR/solid/` (`$REPORT_DIR` is announced by the script on start; it is not inside the audited repository)
- SOLID score (0-100)
- Violations by principle with examples
- Refactoring suggestions

## Error Handling

Common issues:
- **"High complexity everywhere"**: Start with highest offenders
- **"Tool not found"**: Run `/code-quality-tools:setup`

See: `references/troubleshooting.md#solid-check-issues`

## Related Commands

- `/code-quality-tools:audit` - Full audit (includes SOLID)
- `/code-quality-tools:dry` - Check duplication (related to SRP)
