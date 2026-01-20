---
description: Interactive setup wizard to install and configure code quality tools for Drupal/Next.js projects
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

**Drupal - GrumPHP:**
```yaml
# grumphp.yml
grumphp:
  tasks:
    phpstan:
      level: 5
    phpcs:
      standard: Drupal
    phpcpd:
      min_lines: 5
```

**Next.js - Husky + lint-staged:**
```json
// package.json
"lint-staged": {
  "*.{js,jsx,ts,tsx}": [
    "eslint --fix",
    "jest --findRelatedTests --passWithNoTests"
  ]
}
```

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
  ✓ Git hooks configured (GrumPHP)

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

This command will invoke `scripts/core/setup-wizard.sh` (to be created in Phase B).
For now, setup must be done manually following README instructions.
