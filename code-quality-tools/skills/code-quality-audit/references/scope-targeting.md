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
ddev exec ../../../../scripts/drupal/security-check.sh

# Script will scan from your current directory
```

### Next.js Example
```bash
# Navigate to specific component directory
cd src/components/auth

# Run security check
bash ../../../skills/code-quality-audit/scripts/nextjs/security-check.sh
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
  ./scripts/drupal/security-check.sh

# Override themes path
DRUPAL_THEMES_PATH=web/themes/custom/my_theme \
  ./scripts/drupal/security-check.sh

# Override both
DRUPAL_MODULES_PATH=web/modules/custom/my_module \
DRUPAL_THEMES_PATH=web/themes/custom/my_theme \
  ./scripts/drupal/security-check.sh
```

### Next.js Variables
```bash
# Override source path
SRC_PATH=src/components/auth \
  ./scripts/nextjs/security-check.sh

# Or for multiple paths
SRC_PATH="src/components/auth src/lib/auth" \
  ./scripts/nextjs/security-check.sh
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
./scripts/drupal/security-check.sh

# Next.js - scans entire src directory
./scripts/nextjs/security-check.sh
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
ddev exec ../../../../scripts/drupal/security-check.sh
ddev exec ../../../../scripts/drupal/solid-check.sh
ddev exec ../../../../scripts/drupal/dry-check.sh

# Results saved to .reports/ scoped to this module
```

### Example 2: Testing Specific Component
```bash
# Testing authentication component
cd src/components/auth

# Run security check
SRC_PATH=. bash ../../../scripts/nextjs/security-check.sh

# Or just run from component directory
bash ../../../scripts/nextjs/security-check.sh
```

### Example 3: CI/CD for Monorepo
```bash
# .github/workflows/module-quality.yml
env:
  DRUPAL_MODULES_PATH: web/modules/custom/${{ matrix.module }}

jobs:
  test:
    strategy:
      matrix:
        module: [module_a, module_b, module_c]
    steps:
      - run: ./scripts/drupal/security-check.sh
```

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

When scoping to a specific module/component, reports can be prefixed:

```bash
# Module-specific reports
.reports/my_module-security-report.json
.reports/my_module-solid-report.json

# Component-specific reports
.reports/auth-component-security.json
```

Scripts automatically detect scoped runs and adjust report names.
