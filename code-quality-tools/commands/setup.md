---
description: Interactive setup wizard to install and configure code quality tools for Drupal/Next.js projects. Use when user says "install quality tools", "set up PHPStan", "configure linting", "add code quality", "first time setup", "install ESLint", "setup security tools". Detects project type and installs recommended tools.
allowed-tools: Read, Bash, Grep, Glob, AskUserQuestion, Write
argument-hint: optional|project-path
---

# Setup Wizard

Interactive wizard to install and configure code quality tools for your project.

## Usage

```
/code-quality:setup [project-path]
```

## What This Does

1. Auto-detects project type (Drupal, Next.js, or both)
2. Presents tool selection (Quick install or Custom)
3. Configures quality thresholds
4. Installs selected tools
5. Generates `.code-quality.json` configuration
6. Optionally sets up git hooks (GrumPHP/Husky)
7. Runs baseline audit
8. Displays next steps

## Setup Workflow

```
Detection → Tool Selection → Threshold Config → Installation → Git Hooks (optional) → Baseline Audit → Summary
```

## Tool Categories

**Static Analysis:**
- Drupal: PHPStan, Psalm, PHPMD
- Next.js: ESLint, TypeScript, madge

**Security:**
- Both: Semgrep, Trivy, Gitleaks
- Drupal: Security Review, Drush advisories, Roave, Composer audit
- Next.js: npm audit, Socket CLI

**Quality Metrics:**
- Drupal: PHPCPD (duplication)
- Next.js: jscpd (duplication)

**Testing:**
- Drupal: PHPUnit
- Next.js: Jest

**Standards:**
- Drupal: Drupal Coder, Rector
- Next.js: Prettier (optional)

**Code Intelligence (recommended):**
- Drupal: `php-lsp` plugin + `intelephense` binary
- Next.js: `typescript-lsp` plugin + `typescript-language-server` binary

## Installation Modes

### Quick Install (Recommended)
Installs all recommended tools with default thresholds.

**Drupal:**
```bash
ddev composer require --dev \
  phpstan/phpstan \
  phpmd/phpmd \
  sebastian/phpcpd \
  vimeo/psalm \
  drupal/coder \
  rector/rector \
  phpro/grumphp \
  roave/security-advisories
```

Plus: Semgrep, Trivy, Gitleaks (system-level)

**Next.js:**
```bash
npm install --save-dev \
  eslint \
  @typescript-eslint/parser \
  @typescript-eslint/eslint-plugin \
  jest \
  @testing-library/react \
  @testing-library/jest-dom \
  jscpd \
  madge \
  husky \
  lint-staged
```

Plus: Semgrep, Trivy, Gitleaks (system-level)

### Custom Install
Select specific tools and configure thresholds individually.

## Code Intelligence Plugins (recommended)

The `/code-quality:solid`, `/code-quality:dry`, and `/code-quality:review` commands go deeper when Claude Code's built-in **LSP tool** is active — it resolves references, interface implementations, and call hierarchies that grep cannot see, and it reports type errors automatically after every edit. The tool is inactive until a code-intelligence plugin **and** its language-server binary are installed:

| Project | Plugin | Server binary |
|---------|--------|---------------|
| Drupal / PHP | `php-lsp` | `intelephense` |
| Next.js / TypeScript | `typescript-lsp` | `typescript-language-server` |

```bash
/plugin install php-lsp@claude-plugins-official        # or typescript-lsp@claude-plugins-official
```

Then install the language-server binary so it is on `$PATH` (see each plugin's README for the exact package). If `/plugin` shows `Executable not found in $PATH`, the binary is missing.

This is **recommended, not required** — every command falls back to full-file reads when no LSP plugin is present. Analysis-depth gains and the Drupal `.module`/`.inc`/`.theme` indexing caveat: `skills/code-quality-audit/references/code-intelligence.md`.

## Threshold Configuration

Interactive prompts for:

1. **Coverage Threshold** (default: 80%)
   - Minimum test coverage percentage

2. **Complexity Threshold** (default: 10)
   - Maximum cyclomatic complexity

3. **Duplication Threshold** (default: 5%)
   - Maximum allowed code duplication

4. **Security Severity** (default: medium+)
   - Options: all, low+, medium+, high+, critical

## Generated Configuration

Creates `.code-quality.json`:
```json
{
  "version": "2.2.0",
  "project": {
    "type": "drupal",
    "path": "./",
    "name": "my-project"
  },
  "tools": {
    "static_analysis": ["phpstan", "psalm"],
    "security": ["semgrep", "trivy", "gitleaks"],
    "quality": ["phpmd", "phpcpd"],
    "testing": ["phpunit"],
    "standards": ["drupal-coder"]
  },
  "thresholds": {
    "coverage": 80,
    "complexity": 10,
    "duplication": 5,
    "security_severity": "medium"
  },
  "reports": {
    "directory": ".reports/",
    "formats": ["json", "markdown", "html"],
    "retention_days": 30
  },
  "git_hooks": {
    "enabled": false,
    "tool": "grumphp",
    "checks": ["lint", "security"]
  }
}
```

## Git Hooks Setup (Optional)

After installing the static-analysis tools, prompt the user:

> Install GrumPHP git hooks to lint staged files on every commit? [y/N]

Default is **No**. The wizard must not install hooks silently. Re-runs of `/code-quality:setup` re-ask only if hooks aren't already installed.

### On "yes" — Drupal (GrumPHP)

The hook only checks **files staged for the current commit** (`context: git-staged-files`). Heavier checks stay in CI.

1. Install GrumPHP:
   ```bash
   ddev composer require --dev phpro/grumphp
   ```
2. Copy the template into the project root:
   ```bash
   cp skills/code-quality-audit/templates/grumphp.yml ./grumphp.yml
   ```
   The template ships with `phpcs` (Drupal standards) and `phpstan` only. Intentionally excluded:
   - **phpcpd** — directory-scoped, too slow for pre-commit
   - **phpunit** — runs the full suite; lives in CI instead
   - **phpmd** — noisy on legacy code; opt-in by uncommenting in the template
3. Register the hook:
   ```bash
   ddev exec vendor/bin/grumphp git:init
   ```
4. Confirm with a no-op staged change:
   ```bash
   git commit --allow-empty -m "Test grumphp hook"
   ```

To remove later: `vendor/bin/grumphp git:deinit && composer remove --dev phpro/grumphp`.

### On "yes" — Next.js (Husky + lint-staged)

```json
// package.json
"lint-staged": {
  "*.{js,jsx,ts,tsx}": [
    "eslint --fix",
    "jest --findRelatedTests --passWithNoTests"
  ]
}
```

Then `npx husky init && echo 'npx lint-staged' > .husky/pre-commit`.

### CI alternative (recommended in addition to or instead of hooks)

For per-PR review without a local hook, install one or both opt-in GitHub Actions workflows:

- `skills/code-quality-audit/templates/ci/github-drupal.yml` → `.github/workflows/quality.yml` — full quality battery on push/PR to main.
- `skills/code-quality-audit/templates/ci/github-drupal-pr.yml` → `.github/workflows/quality-pr.yml` — **changed-files-only** review of PRs; posts a sticky comment with synthesis + rubric. Gate is soft by default; set repo Variable `FAIL_ON_GATE=true` to enforce.

Both workflows are independent — install one, both, or neither.

## Baseline Audit

After installation, runs initial audit to establish baseline:
- Current coverage %
- Existing security issues
- Current duplication level
- SOLID score

Baseline saved to `.reports/baseline.json`

## Output & Next Steps

```
✅ Setup Complete!

Tools Installed:
  ✓ PHPStan 1.10.x
  ✓ Psalm 5.x
  ✓ Semgrep 1.x
  ✓ Trivy 0.48.x
  ✓ Gitleaks 8.x

Configuration:
  ✓ .code-quality.json created
  ✓ Git hooks configured (GrumPHP — staged files only, phpcs + phpstan)

Baseline Audit Results:
  Coverage: 72% (target: 80%)
  Security Issues: 3 medium severity
  Duplication: 4.2%
  SOLID Score: 85/100

Next Steps:
1. Review baseline: .reports/baseline.json
2. Address security issues: /code-quality:security
3. Improve coverage: /code-quality:tdd
4. Run full audit: /code-quality:audit

Documentation: See references/setup-guide.md
```

## Re-running Setup

Safe to re-run - will:
- Detect existing tools
- Offer to update configuration
- Skip already-installed tools
- Update git hooks if requested

## Error Handling

Common issues:
- **"DDEV not running"** (Drupal): Start DDEV (`ddev start`)
- **"npm not found"** (Next.js): Install Node.js
- **"Permission denied"**: Check file permissions

See: `references/troubleshooting.md#setup-issues`

## Related Commands

- `/code-quality:audit` - Run full audit after setup
- `/code-quality:coverage` - Check test coverage
- `/code-quality:security` - Run security scan

## Implementation Note

This command guides setup interactively through Claude — no external script needed.
Follow the steps above to detect project type, present options, and install tools.
