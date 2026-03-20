---
description: Analyze a codebase and generate a starter REVIEW.md for Claude Code's managed Code Review service. Use when user says "generate review md", "create review config", "setup code review", "review guidelines", "review rules", "what should code review check".
allowed-tools: Read, Glob, Grep, Write, Bash, AskUserQuestion
---

# Generate REVIEW.md

Analyze a codebase's patterns, conventions, and common issues, then generate a `REVIEW.md` file that Claude Code's managed Code Review service reads during PR reviews.

## Usage

```
/code-quality:generate-review-md
```

## What This Does

1. Detects project type (Drupal, Next.js, general)
2. Scans for existing conventions (linter configs, CLAUDE.md rules, coding standards)
3. Analyzes recent git history for common change patterns
4. Generates a `REVIEW.md` with project-specific review rules
5. User reviews and adjusts before committing

## Instructions

When this command is invoked:

### Step 1 — Detect Project Type

Identify the project:
- Drupal: `*.info.yml`, `composer.json` with drupal/core
- Next.js: `next.config.*`, `package.json` with next
- React: `package.json` with react
- Python: `pyproject.toml`, `setup.py`, `requirements.txt`
- General: fallback

### Step 2 — Scan Existing Conventions

Read these files if they exist (do not fail if missing):

**Linter configs:**
- `.eslintrc*`, `eslint.config.*` — JS/TS rules
- `phpstan.neon*` — PHP static analysis level
- `.phpcs.xml*` — PHP coding standards
- `phpmd.xml*` — PHP mess detector rules
- `.prettierrc*` — formatting rules
- `tsconfig.json` — TypeScript strictness

**Project rules:**
- `CLAUDE.md` — existing project instructions (at root and subdirectories)
- `.claude/rules/*.md` — path-specific rules
- `.editorconfig` — indentation, line endings

**CI config:**
- `.github/workflows/*.yml` — what CI already checks
- `.gitlab-ci.yml` — same

Extract:
- What rules are already enforced by tooling (don't duplicate in REVIEW.md)
- What strictness level is configured (PHPStan level, TypeScript strict mode, etc.)
- What CI already catches (tests, lint, security scans)

### Step 3 — Analyze Recent Git History

Run:
```bash
git log --oneline --since="3 months ago" -100
```

Look for patterns:
- Common file types changed (what's actively developed)
- Commit message patterns (conventional commits? ticket references?)
- Common directories (where most work happens)
- Revert/fix patterns (areas with frequent bugs)

### Step 4 — Build REVIEW.md

Generate a `REVIEW.md` at the project root using this structure:

```markdown
# Code Review Guidelines

## Always check
[Project-specific rules derived from analysis]

## Style
[Conventions detected from linter configs and CLAUDE.md]

## Security
[Security rules appropriate for the project type]

## Skip
[Files/directories that shouldn't be reviewed]
```

**Rules by project type:**

**Drupal:**
- Always: hook implementations follow naming conventions, services use dependency injection (no `\Drupal::service()`), form handlers validate CSRF tokens, database queries use placeholders (no string concatenation), render arrays use `#markup` only with `Xss::filter()` or `t()`
- Style: follow Drupal coding standards (detected from phpcs config), use entity API over direct queries
- Security: check `\Drupal::request()` usage for injection, verify access checks on routes, check for `#markup` with unsanitized input
- Skip: `vendor/`, `core/`, generated config in `config/sync/`

**Next.js / React:**
- Always: API routes validate input, `getServerSideProps` doesn't leak secrets to client, dynamic imports for heavy components, environment variables use `NEXT_PUBLIC_` prefix correctly
- Style: follow ESLint config (detected), consistent component file structure
- Security: no secrets in client bundles, API routes check authentication, form inputs sanitized
- Skip: `node_modules/`, `.next/`, generated types in `__generated__/`

**Python:**
- Always: type hints on public functions, no bare `except:` clauses, SQL queries use parameterized statements
- Style: follow project formatter (black/ruff detected from config)
- Security: no `eval()` or `exec()` on user input, secrets not hardcoded
- Skip: `venv/`, `__pycache__/`, `.eggs/`

**General (all projects):**
- Always: error messages don't leak internal details, new API endpoints have tests, database migrations are backward-compatible
- Security: no credentials in code, no `TODO` or `FIXME` in security-critical paths
- Skip: lock files (formatting-only changes), generated code directories

### Step 5 — Merge with Existing Rules

If CLAUDE.md contains review-relevant rules:
- Don't duplicate them in REVIEW.md (CLAUDE.md is already read by Code Review)
- Add a comment in REVIEW.md: `<!-- Rules from CLAUDE.md are also applied during review -->`
- Only add rules that are review-specific (things you'd flag in a PR but not enforce in normal coding)

If `.claude/rules/` has path-specific rules:
- Reference them: `<!-- Path-specific rules in .claude/rules/ are also applied -->`

### Step 6 — Present and Confirm

Show the generated REVIEW.md content to the user.

**AskUserQuestion:** "Here's the generated REVIEW.md based on your project analysis. Would you like to:"
- **Save as-is** — Write to `REVIEW.md` at project root
- **Edit first** — I'll modify specific sections before saving
- **Show analysis** — See what I detected and why each rule was included

If **Edit first**: Ask which sections to modify, apply changes, then save.
If **Show analysis**: Present the detection report, then ask again.

After saving:
> `REVIEW.md` saved to project root. Claude Code's managed Code Review service will read this during PR reviews. You can also run `/code-quality:review` locally — it reads REVIEW.md for project-specific standards.
>
> **Tip:** `/loop 30m /code-quality:lint` runs periodic lint checks during long coding sessions.

## Output

- Created: `REVIEW.md` at project root
- Logged: analysis summary in conversation
