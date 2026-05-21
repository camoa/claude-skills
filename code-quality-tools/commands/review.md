---
description: Review code quality with structured rubric scoring (Content + Structure grades, /50 scale). Use when user says "review this code", "grade this module", "code review", "quality score", "is this production ready", "rate this code", "code assessment". Produces scored report with quality gate (PASS 35+/FAIL) and prioritized action items.
allowed-tools: Read, Bash, Grep, Glob, Write
argument-hint: "[--json] <file-or-directory-path>"
---

# Code Review

Structured code review with rubric-based scoring. Produces a graded assessment with per-category scores and prioritized action items.

> **Reading strategy:** This is **Type B** work — read full source and config files; do NOT grep-first. See `https://camoa.github.io/dev-guides/development/reading-strategy/` via `dev-guides-navigator`.

## LSP Code Intelligence (recommended)

If a code-intelligence plugin is installed (`php-lsp` for Drupal, `typescript-lsp` for Next.js), use the **LSP tool** to ground the rubric's *Separation of concerns* and *Testability* categories in evidence rather than impression: `call-hierarchy` shows whether a controller/form method reaches into a data layer N levels deep; `find-references` and definition resolution show how dependencies are actually wired. The tool needs no permission and is inert when no plugin is installed — fall back to full-file reads when it is unavailable. See `skills/code-quality-audit/references/code-intelligence.md`.

## Usage

```
/code-quality:review <file-or-directory-path>            # writes scored markdown report
/code-quality:review --json <file-or-directory-path>     # CI mode — single stable JSON on stdout
```

## CI Mode (--json)

When invoked with `--json`, emit schema `v1.0` JSON on stdout and skip writing the markdown report. Fields include:

- `summary.total` (0-50), `summary.grade`, `summary.gate` (`PASS` / `FAIL`)
- `findings[]` with per-category score, severity, file:line, message, fix
- `action_items[]` with priority and resolves-findings references

Gate on `.summary.gate`:

```bash
result=$(/code-quality:review --json "$TARGET")
echo "$result" | jq -e '.summary.gate == "PASS"' >/dev/null || exit 1
```

Schema: `skills/code-quality-audit/references/json-schemas.md`.

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

Claude Code's managed Code Review service injects `REVIEW.md` verbatim as the highest-priority instruction block into every review agent. If `REVIEW.md` exists at the project root, read it before scoring and apply its severity overrides, skip directives, and mandatory checks.

Severity labels: 🔴 **Important** (blocks merge), 🟡 **Nit**, 🟣 **Pre-existing**. The JSON check-run output keys Important findings as `normal` for backwards compatibility — see `skills/code-quality-audit/references/check-run-json.md` for CI gating.

For authoring REVIEW.md, see `skills/code-quality-audit/references/review-md-v2.md` — covers severity overrides, nit caps, skip directives, verification bars, and starter templates for Drupal and Next.js. Generate one with `/code-quality:generate-review-md`.

## CI Integration

To gate merges on Code Review findings, parse the **Claude Code Review** check run's JSON output with `gh` + `jq`. A non-zero `normal` count means at least one Important finding was posted. See `skills/code-quality-audit/references/check-run-json.md` for the `gh api` command and a starter GitHub Actions workflow.

## See also

- `/code-quality:audit` — Full automated audit (tools only, no rubric)
- `/code-quality:solid` — SOLID principles check only
- `/code-quality:security` — Security audit only
- `/code-quality:generate-review-md` — generate a v2 REVIEW.md tailored to the project
- `/code-quality:ultrareview` — cloud multi-agent deep review for pre-merge (slower, more rigorous, paid after free quota)
- `@claude review once` — GitHub PR comment that triggers one managed Code Review without subscribing the PR to future push-triggered reviews. Requires the managed Code Review service enabled on the repository. Useful for long-running PRs with frequent rebases.
- `claude --from-pr <number>` — resumes the Claude Code session linked to a PR (linked automatically when Claude opened it). Use it to act on review findings in the original session's context.
