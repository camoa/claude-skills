---
description: Quick-convert branded HTML pages to a Drupal Radix sub-theme
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion, Skill
---

# Convert to Radix Quick Command

Quick-convert branded HTML pages into a Drupal Radix sub-theme with minimal interaction. Auto-resolves all ambiguities using sensible defaults: components with few instances become block types, components with many instances become views, icons always generate a pack, and all recommended modules are included.

## Prerequisites

- A brand project with `brand-philosophy.md`
- At least one HTML design system with `design-system.md` and `canvas-philosophy.md`
- At least one HTML page in `html-pages/` containing metadata comments
- The `html-to-radix-analyzer` and `radix-sdc-generator` skills

---

## Workflow

### Step 1: Find Project and HTML Pages

Search for `brand-philosophy.md` using standard project detection order:

1. Current directory — check `./brand-philosophy.md`
2. Parent directory — check `../brand-philosophy.md`
3. Subdirectories — `find . -maxdepth 2 -name "brand-philosophy.md"`
4. If multiple found — ask user which project
5. If none found — tell user to run `/brand-init` first

Set `PROJECT_PATH` to the directory containing `brand-philosophy.md`.

Search for HTML files with metadata comments:
```
find {PROJECT_PATH}/html-pages -name "*.html" -type f 2>/dev/null
```

Verify each file contains `<!-- component:` markers. If none found — tell user to run `/html-page` first and ensure pages include metadata comments.

If exactly one page found — auto-select it.

### Step 2: Select Pages

Only ask if multiple pages exist.

**AskUserQuestion**: "Which pages to convert?"

If 4 or fewer pages, list each plus "All pages". If more than 4, show the 3 most recent (by directory date prefix) plus "All pages".

- **{page-name}** — {date}, {component count} components
- **All pages** — Convert all {count} pages

Store as `SELECTED_PAGES`.

### Step 3: Drupal Path

**AskUserQuestion**: "Drupal codebase path?"
- **None — green-field** — "Generate complete structure from scratch"
- **Provide path** — "I'll scan config/sync/ for existing backend to reuse"

If path provided, verify `config/sync/` exists. Warn if missing but continue.

Store as `DRUPAL_PATH` (path string or `null`).

### Step 4: Theme Name

Read `brand-philosophy.md` to extract the brand name. Derive a machine name: lowercase, replace spaces/hyphens with underscores, remove special characters.

**AskUserQuestion**: "Theme machine name?"
- **{suggested_name}** — Based on brand name
- **{suggested_name}_theme** — With _theme suffix
- **Custom** — Enter your own

Validate: lowercase letters, digits, underscores; starts with a letter. Re-ask if invalid.

Store as `THEME_NAME`.

### Step 5: Auto-Analyze and Generate

Read all required files:
- Each selected HTML page
- Design system: `{PROJECT_PATH}/templates/html/*/design-system.md`
- Canvas philosophy: `{PROJECT_PATH}/templates/html/*/canvas-philosophy.md`
- Brand philosophy: `{PROJECT_PATH}/brand-philosophy.md`

Invoke the `html-to-radix-analyzer` skill via the Skill tool with HTML contents, design system files, brand philosophy, and `DRUPAL_PATH` if provided.

Apply quick-mode auto-resolution rules to the analysis result:
- **Ambiguous components with 1-3 instances** — classify as `block_type`
- **Ambiguous components with 4+ instances** — classify as `view_content_type`
- **Icons** — always generate an icon pack (`ICON_STRATEGY = "generate_pack"`)
- **Modules** — accept all recommended modules

Invoke the `radix-sdc-generator` skill via the Skill tool with:
- Analysis output (with auto-resolved classifications)
- `THEME_NAME`
- `DRUPAL_PATH` (if provided)
- Icon strategy: `generate_pack` if icons exist, `none` otherwise
- Full recommended module list
- Design system and brand philosophy contents

Save conversion config to `{PROJECT_PATH}/converter/radix-sdc.yml` (create `converter/` directory if needed).

### Step 6: Display Summary

Present the results:

```
-- Theme Generated --

Theme: {THEME_NAME}
Location: {PROJECT_PATH}/converter/{THEME_NAME}/

Components: {count} ({atoms} atoms, {molecules} molecules, {organisms} organisms)
Config exports: {count}
Icons: {count} (if applicable)

Commands to run:
  composer require drupal/radix drupal/layout_builder_styles {other modules}
  drush en {module_list}
  drush theme:enable {THEME_NAME}
  drush config:set system.theme default {THEME_NAME}
  cd {theme_path} && npm install && npm run build

Next steps:
  1. Copy theme to your Drupal themes/custom/ directory
  2. Import config exports with drush config:import
  3. Configure Layout Builder on target content types

Conversion config: {PROJECT_PATH}/converter/radix-sdc.yml
```

---

## Output

- Created: `{PROJECT_PATH}/converter/radix-sdc.yml` (conversion configuration)
- Created: `{PROJECT_PATH}/converter/{THEME_NAME}/` (complete Radix sub-theme)
- Created: SDC components, SCSS, config exports, and optional icon pack within theme directory
