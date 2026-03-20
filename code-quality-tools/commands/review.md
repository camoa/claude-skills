---
description: Review code quality with structured rubric scoring (Content + Structure grades, /50 scale). Use when user says "review this code", "grade this module", "code review", "quality score", "is this production ready", "rate this code", "code assessment". Produces scored report with quality gate (PASS 35+/FAIL) and prioritized action items.
allowed-tools: Read, Bash, Grep, Glob, Write
argument-hint: <file-or-directory-path>
---

# Code Review

Structured code review with rubric-based scoring. Produces a graded assessment with per-category scores and prioritized action items.

## Usage

```
/code-quality:review <file-or-directory-path>
```

## What This Does

1. Reads target code and determines project type (Drupal/Next.js)
2. Runs relevant automated tools (PHPStan/ESLint, security scan)
3. Applies rubric scoring across 10 categories (Content + Structure)
4. Produces scored report with quality gate decision
5. Writes report to `.reports/code-review-{name}.md`

## Instructions

When this command is invoked with `$ARGUMENTS`:

### Step 1 — Identify Target

Parse `$ARGUMENTS` as a file or directory path. Verify it exists.

If no arguments provided:
> What code should I review? Provide a file or directory path:
> ```
> /code-quality:review src/Service/PaymentService.php
> /code-quality:review web/modules/custom/my_module
> ```

If path doesn't exist:
> Path not found: `{path}`. Check the path and try again.

### Step 2 — Read and Analyze

1. Read all files in target (if directory, read `.php`, `.js`, `.ts`, `.tsx`, `.module`, `.inc` files)
2. Count total lines, files, classes/functions
3. Detect project type from file extensions and structure

### Step 3 — Run Automated Tools

Based on project type, run available tools:

**Drupal:**
```bash
# PHPStan (if available)
ddev exec vendor/bin/phpstan analyse {path} --level=5 --error-format=json 2>/dev/null || true

# PHPCS (if available)
ddev exec vendor/bin/phpcs --standard=Drupal {path} --report=json 2>/dev/null || true
```

**Next.js:**
```bash
# ESLint (if available)
npx eslint {path} --format=json 2>/dev/null || true
```

If tools are not installed, note it and continue with manual analysis only.

### Step 4 — Score with Rubric

Apply the following rubric. Score each category 1-5:

**Content (Does it work?):**

| Category | 1 (Poor) | 3 (Adequate) | 5 (Excellent) |
|----------|----------|--------------|---------------|
| **Correctness** | Fails on happy path | Works for happy path, fails edge cases | Handles all scenarios correctly |
| **Completeness** | Missing major functionality | Core present, gaps in edge cases | All requirements met, edge cases handled |
| **Edge cases** | No handling | Some handled (null, empty) | Comprehensive (null, empty, zero, large, concurrent) |
| **Error handling** | No handling, crashes | Basic try/catch, generic messages | Specific errors, recovery paths, user-friendly |
| **Security** | Obvious vulnerabilities | Basic sanitization, some gaps | Defense in depth, validated at all boundaries |

**Structure (Is it maintainable?):**

| Category | 1 (Poor) | 3 (Adequate) | 5 (Excellent) |
|----------|----------|--------------|---------------|
| **Readability** | Cryptic names, no structure | Reasonable names, some structure | Self-documenting, clear intent |
| **Separation of concerns** | Business logic in controllers/forms | Some separation, some mixing | Clean layers, single responsibility |
| **DRY** | Copy-pasted blocks | Minor duplication | No unnecessary duplication |
| **Testability** | Untestable (hardcoded deps) | Partially testable | Fully injectable, pure functions |
| **Extensibility** | Changes require rewriting | Can extend with moderate effort | Open/closed principle followed |

### Step 5 — Write Report

Write to `.reports/code-review-{filename-or-dirname}.md`:

```markdown
# Code Review Report

## Target
{file/directory path, total lines, total files, language}

## Automated Tool Results
{PHPStan/ESLint findings summary — or "Tools not available, manual analysis only"}

## Rubric Score

### Content (Does it work?)
| Category | Score | Notes |
|----------|-------|-------|
| Correctness | {1-5} | {specific observations} |
| Completeness | {1-5} | {what's present, what's missing} |
| Edge cases | {1-5} | {what's handled, what's not} |
| Error handling | {1-5} | {patterns used, gaps} |
| Security | {1-5} | {validation, sanitization, auth} |
| **Content subtotal** | **{sum}/25** | |

### Structure (Is it maintainable?)
| Category | Score | Notes |
|----------|-------|-------|
| Readability | {1-5} | {naming, structure, comments} |
| Separation | {1-5} | {layers, responsibilities} |
| DRY | {1-5} | {duplication level} |
| Testability | {1-5} | {dependency injection, pure functions} |
| Extensibility | {1-5} | {patterns, flexibility} |
| **Structure subtotal** | **{sum}/25** | |

### Total: {sum}/50

### Quality Gate
{45-50: Excellent — production ready}
{35-44: Good — minor improvements needed}
{25-34: Adequate — improvements needed before production}
{15-24: Below standard — significant rework required}
{<15: Poor — fundamental issues}

**Gate: PASS / FAIL** (minimum: 35/50, no category below 2)

## Key Findings
| # | Category | Issue | Severity | Location | Fix |
|---|----------|-------|----------|----------|-----|

## Prioritized Action Items
1. {highest impact fix}
2. {next fix}
3. {next fix}
```

### Step 6 — Report to User

> Code review complete. Score: **{total}/50** — **{grade}**
> Report saved to `.reports/code-review-{name}.md`
> {if FAIL: "Quality gate FAILED. See action items for required fixes."}

## REVIEW.md Convention

Claude Code's Code Review feature supports a `REVIEW.md` file at the project root to customize review behavior. If `REVIEW.md` exists in the project, Claude will read it before scoring to apply project-specific standards (e.g., required patterns, team conventions, framework-specific rules). Create a `REVIEW.md` to tailor the rubric to your project's needs.

## Related Commands

- `/code-quality:audit` — Full automated audit (tools only, no rubric)
- `/code-quality:solid` — SOLID principles check only
- `/code-quality:security` — Security audit only
