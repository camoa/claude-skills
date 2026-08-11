# Scope Targeting

How to run quality checks on specific modules, components, or directories instead of the entire project.

## Contents

- [Overview](#overview)
- [Approach 1: Change Directory](#approach-1-change-directory-recommended)
- [Approach 2: Environment Variables](#approach-2-environment-variables)
- [Approach 3: Full Scan](#approach-3-full-scan-default)
- [Intelligent Detection](#intelligent-detection)

---

## Overview

Sometimes you want to audit a specific module or component instead of the entire project:
- Contributing a specific Drupal module
- Testing a single Next.js component
- Working in a module/component subdirectory

**Decision:** Use simple `cd` and environment variable approaches. No `--scope` flags needed.

---

## Approach 1: Change Directory (Recommended)

The most natural approach - just navigate to the directory you want to audit.

### Drupal Example
```bash
# Navigate to specific module
cd web/modules/custom/my_module

# Run security check (script automatically scans current context)
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/security-check.sh"

# Script will scan from your current directory
```

### Next.js Example
```bash
# Navigate to specific component directory
cd src/components/auth

# Run security check
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/nextjs/security-check.sh"
```

**Why this works:**
- Scripts detect your current working directory
- Natural developer workflow
- No special flags or configuration
- Works with all tools (PHPStan, ESLint, Semgrep, etc.)

---

## Approach 2: Environment Variables

Override default paths using environment variables.

### Drupal Variables
```bash
# Override modules path
DRUPAL_MODULES_PATH=web/modules/custom/my_module \
  bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/security-check.sh"

# Override themes path
DRUPAL_THEMES_PATH=web/themes/custom/my_theme \
  bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/security-check.sh"

# Override both
DRUPAL_MODULES_PATH=web/modules/custom/my_module \
DRUPAL_THEMES_PATH=web/themes/custom/my_theme \
  bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/security-check.sh"
```

### Next.js Variables
```bash
# Override source path
SRC_PATH=src/components/auth \
  bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/nextjs/security-check.sh"

# Or for multiple paths
SRC_PATH="src/components/auth src/lib/auth" \
  bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/nextjs/security-check.sh"
```

### Persistent Override
Create `.env` file in project root:
```bash
# .env
DRUPAL_MODULES_PATH=web/modules/custom/my_module
SRC_PATH=src/components/dashboard
```

Then run scripts normally - they'll use the env vars.

---

## Approach 3: Full Scan (Default)

Run from project root without any overrides.

```bash
# Drupal - scans all custom modules and themes
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/security-check.sh"

# Next.js - scans entire src directory
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/nextjs/security-check.sh"
```

**Default paths:**
- Drupal: `web/modules/custom` + `web/themes/custom`
- Next.js: `src`

---

## Intelligent Detection

Claude should detect the user's intent based on:

### 1. Current Directory Context
```bash
# User is in module directory
pwd  # /var/www/html/web/modules/custom/my_module

# Claude should ask: "Run audit on my_module only, or full project scan?"
```

### 2. Explicit User Request
- "Just this module" → Use Approach 1 or 2
- "Full scan" → Use Approach 3
- "Check the auth component" → Navigate to component first

### 3. Environment Variables Present
```bash
# User has .env with DRUPAL_MODULES_PATH set
# Claude should acknowledge: "Using module path from .env: {path}"
```

---

## Examples

### Example 1: Contributing a Drupal Module
```bash
# You're developing a custom module for contribution
cd web/modules/custom/my_awesome_module

# Run all quality checks on just this module
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/security-check.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/solid-check.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/drupal/dry-check.sh"

# Results are scoped to this module and saved to $REPORT_DIR (resolved by
# scripts/core/report-dir.sh; outside the audited repository)
```

### Example 2: Testing Specific Component
```bash
# Testing authentication component
cd src/components/auth

# Run security check
SRC_PATH=. bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/nextjs/security-check.sh"

# Or just run from component directory
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/nextjs/security-check.sh"
```

### Example 3: CI/CD for Monorepo

`${CLAUDE_PLUGIN_ROOT}` is a Claude Code substitution and does **not** exist in CI. A
runner has no installed plugin, so check this one out and point at that checkout:

```yaml
# .github/workflows/module-quality.yml
env:
  DRUPAL_MODULES_PATH: web/modules/custom/${{ matrix.module }}

jobs:
  test:
    strategy:
      matrix:
        module: [module_a, module_b, module_c]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
        with:
          repository: camoa/claude-skills
          path: .code-quality-tools
      - run: bash .code-quality-tools/code-quality-tools/skills/code-quality-audit/scripts/drupal/security-check.sh
```

Reports land wherever the resolver decides on the runner, which is outside the checkout.
Set `REPORT_DIR` to a path you then upload as a build artifact, or `REPORT_DIR_IN_REPO=1`
for an in-repo `.reports/` — an ephemeral runner has no branch for a report to ride on,
which is why the shipped [CI template](../templates/ci/github-drupal-pr.yml) takes the
in-repo route.

---

## Why Not --scope Flags?

**Decision:** Keep it simple. Avoid adding `--scope` flags because:

1. **Already works** - `cd` and env vars cover all use cases
2. **Simpler** - No extra code, documentation, or testing
3. **Natural workflow** - Developers already use `cd`
4. **Zero learning curve** - Standard Unix approach
5. **Flexible** - Env vars work in CI/CD too

**Quote from architectural decision:**
> "Simpler, matches developer workflow, zero extra code, already works."

---

## Report Naming

Scoping changes *what* is analyzed, not what the report is called. A scoped run writes the same fixed filenames into `$REPORT_DIR`:

```bash
$REPORT_DIR/security-report.json
$REPORT_DIR/solid-report.json
```

Successive runs are kept apart by the report directory, which carries a timestamp (or a date, under an `ai-dev-assistant` project), not by a per-scope filename prefix. To keep two scopes side by side deliberately, set `REPORT_DIR` explicitly for each run.
