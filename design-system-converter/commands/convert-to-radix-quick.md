---
description: Quick-convert design system HTML pages to a Drupal Radix sub-theme
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion, Skill, WebFetch
---

# Convert to Radix Quick Command

Quick-convert HTML pages into a Drupal Radix sub-theme with minimal interaction. Auto-resolves all ambiguities: components with few instances become block types, components with many instances become views, icons always generate a pack, and all recommended modules are included.

## Prerequisites

- A brand project with `brand-philosophy.md`
- At least one HTML design system with `design-system.md` and `canvas-philosophy.md`
- At least one HTML page in `html-pages/` containing metadata comments
- The `html-to-radix-analyzer` and `radix-sdc-generator` skills

---

## Workflow

### Step 1: Find Project and HTML Pages

Search for `brand-philosophy.md` using standard project detection order:

1. Current directory -- check `./brand-philosophy.md`
2. Parent directory -- check `../brand-philosophy.md`
3. Subdirectories -- `find . -maxdepth 2 -name "brand-philosophy.md"`
4. If multiple found -- ask user which project
5. If none found -- tell user to run `/brand-init` first

Set `PROJECT_PATH`. Find HTML files with `<!-- component:` markers. If exactly one page -- auto-select it.

### Step 2: Select Pages

Only ask if multiple pages exist.

**AskUserQuestion**: "Which pages to convert?"
- **{page-name}** -- {date}, {component count} components
- **All pages** -- Convert all {count} pages

Store as `SELECTED_PAGES`.

### Step 3: Drupal Path

**AskUserQuestion**: "Drupal codebase path?"
- **None -- green-field** -- "Generate complete structure from scratch"
- **Provide path** -- "I'll scan config/sync/ for existing backend to reuse"

Store as `DRUPAL_PATH`.

### Step 4: Theme Name

Read `brand-philosophy.md` for brand name. Derive machine name.

**AskUserQuestion**: "Theme machine name?"
- **{suggested_name}** -- Based on brand name
- **{suggested_name}_theme** -- With _theme suffix
- **Custom** -- Enter your own

Validate: lowercase letters, digits, underscores; starts with a letter.

Store as `THEME_NAME`.

### Step 5: Auto-Analyze and Generate

Read all required files (HTML pages, design system, canvas philosophy, brand philosophy).

Invoke the `html-to-radix-analyzer` skill with quick mode enabled.

Apply auto-resolution rules:
- **Ambiguous components with 1-3 instances** -- classify as `block_type`
- **Ambiguous components with 4+ instances** -- classify as `view_content_type`
- **Icons** -- always generate a pack
- **Modules** -- accept all recommended

Invoke the `radix-sdc-generator` skill with auto-resolved analysis.

Save conversion config to `{PROJECT_PATH}/converter/radix-sdc.yml`.

### Step 6: Display Summary

```
-- Theme Generated --

Theme: {THEME_NAME}
Location: {output_path}

Components: {count} ({atoms} atoms, {molecules} molecules, {organisms} organisms)
Template overrides: {count}
Config exports: {count}
Icons: {count}

Commands to run:
  cd {theme_path} && npm install && npm run build
  drush config:import --partial --source={config_path}
  drush theme:enable {THEME_NAME}

Next steps:
  1. Follow Layout Composition Instructions in conversion-report.md
  2. Configure Layout Builder on target content types
  3. Verify responsive behavior

Conversion report: {output_path}/conversion-report.md
```

---

## Output

- Created: `{PROJECT_PATH}/converter/radix-sdc.yml` (conversion configuration)
- Created: `{PROJECT_PATH}/converter/output/{THEME_NAME}/` (complete Radix sub-theme)
- Created: `conversion-report.md` with Layout Composition Instructions
