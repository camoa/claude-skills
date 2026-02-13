---
description: Convert design system HTML pages to a Drupal Radix sub-theme with SDC components, template overrides, and Layout Builder composition
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion, Skill, WebFetch
---

# Convert to Radix Command

Convert HTML pages (with metadata comments) into a Drupal Radix sub-theme featuring SDC components, Bootstrap-mapped SCSS, template overrides with field-to-prop mapping, Layout Builder configuration, and optional icon packs. The converter is metadata-driven -- it parses `<!-- component: ... -->` annotations dynamically.

## Prerequisites

- A brand project with `brand-philosophy.md`
- At least one HTML design system with `design-system.md` and `canvas-philosophy.md`
- At least one HTML page in `html-pages/` containing metadata comments
- The `html-to-radix-analyzer` and `radix-sdc-generator` skills

---

## Workflow

### Phase 1: Discovery

#### Step 1: Find Project

Search for `brand-philosophy.md` using standard project detection order:

1. Current directory -- check `./brand-philosophy.md`
2. Parent directory -- check `../brand-philosophy.md`
3. Subdirectories -- `find . -maxdepth 2 -name "brand-philosophy.md"`
4. If multiple found -- ask user which project
5. If none found -- tell user to run `/brand-init` first

Set `PROJECT_PATH` to the directory containing `brand-philosophy.md`.

#### Step 2: Find HTML Pages

Search for HTML files with metadata comments:
```
find {PROJECT_PATH}/html-pages -name "*.html" -type f 2>/dev/null
```

For each file found, check for `<!-- component:` markers. List found pages with directory dates.

If none found -- tell user to run `/html-page` or `/html-page-quick` first.

#### Step 3: Select Pages

**AskUserQuestion**: "Which HTML pages should we convert?"

If 4 or fewer pages, list each plus "All pages". If more, show 3 most recent plus "All pages".

Options format:
- **{page-name}** -- {date}, {component count} components detected
- **All pages** -- Convert everything found ({count} pages)

Store as `SELECTED_PAGES`.

---

### Phase 2: Drupal Context

#### Step 4: Drupal Codebase

**AskUserQuestion**: "Do you have an existing Drupal codebase to target?"
- **Yes -- provide path** -- "I'll scan config/sync/ for existing content types, views, and modules"
- **No -- green-field** -- "I'll generate a complete recommended structure from scratch"

If "Yes", ask for the Drupal root path and verify `config/sync/` exists.

Store as `DRUPAL_PATH` (path string or `null`).

#### Step 5: Theme Name

Read `brand-philosophy.md` to extract the brand name. Derive a machine name (lowercase, underscores, no special chars).

**AskUserQuestion**: "What should the Radix sub-theme be called?"
- **{suggested_name}** -- Based on brand name
- **{suggested_name}_theme** -- With _theme suffix
- **Custom** -- Enter your own machine name

Validate: lowercase letters, digits, underscores; starts with a letter.

Store as `THEME_NAME`.

---

### Phase 3: Analysis

#### Step 6: Run Analysis

Read the following files:
- Each selected HTML page
- Design system and canvas philosophy from `{PROJECT_PATH}/templates/html/*/`
- `{PROJECT_PATH}/brand-philosophy.md`

Invoke the `html-to-radix-analyzer` skill with HTML file paths, `DRUPAL_PATH`, and design context.

Store the full result as `ANALYSIS`.

---

### Phase 4: Review Plan

#### Step 7: Display Analysis Summary

Present the analysis in a structured summary:

```
-- Conversion Analysis --

Components: {count} found across {page_count} pages
  Atoms: {count}  |  Molecules: {count}  |  Organisms: {count}

Classifications:
  Block types:          {count}
  Views + content type: {count}
  Menus:                {count}
  Forms:                {count}
  Ambiguous:            {count}

Design Tokens: {count} total
Icons: {count} unique icons
Template Overrides: {count} template files to generate
```

If `DRUPAL_PATH` was provided, show backend inventory and reuse matches.

#### Step 8: Review Plan

**AskUserQuestion**: "Here is the conversion plan. How would you like to proceed?"
- **Approve and continue** -- "Generate the theme with these settings"
- **Modify classifications** -- "I want to change how some components are handled"
- **Start over** -- "Let me reconfigure from the beginning"

If **Modify**: show each component's classification and let user override.

---

### Phase 5: Resolve Ambiguities

#### Step 9: Handle Ambiguous Items

For each ambiguous component:

**AskUserQuestion**: "How should we handle '{component_name}'?"
- **Custom block type** -- "Static curated content, managed per-block"
- **View + content type** -- "Dynamic listing, each item is a content node"
- **Skip** -- "Do not convert this component"

#### Step 10: Icon Strategy

If icons found, check for existing icon infrastructure in Drupal. Set `ICON_STRATEGY`.

#### Step 11: Module Review

**AskUserQuestion**: "These Drupal modules are recommended:"
- **Accept all**
- **Customize** -- review and adjust
- **Minimal** -- only essentials

Store as `MODULES`.

#### Step 12: Save Configuration

Write decisions to `{PROJECT_PATH}/converter/radix-sdc.yml`.

---

### Phase 6: Generation

#### Step 13: Generate Theme

Invoke the `radix-sdc-generator` skill with full analysis, theme name, Drupal path, icon strategy, module list, and design context.

The skill generates:
- Theme directory with flat `components/` structure
- SDC components with `.component.yml`, `.twig`, `.scss`
- Bootstrap-mapped SCSS with design tokens
- Template overrides mapping Drupal fields to SDC props
- Layout Builder config exports
- Layout composition instructions in the conversion report
- Icon pack (if applicable)

---

### Phase 7: Completion

#### Step 14: Display Summary

Present the generation results:

```
-- Theme Generated --

Theme: {THEME_NAME}
Location: {output_path}

Files created: {total count}
  Theme scaffold:    {count}
  SDC components:    {count} (flat components/ directory)
  Template overrides:{count}
  Config exports:    {count}
  Icon pack:         {count} icons

Next steps:
  1. cd {theme_path} && npm install && npm run build
  2. drush config:import --partial --source={config_path}
  3. drush theme:enable {THEME_NAME}
  4. Follow Layout Composition Instructions in conversion-report.md

Conversion report: {output_path}/conversion-report.md
```

---

## Output

- Created: `{PROJECT_PATH}/converter/radix-sdc.yml` (conversion configuration)
- Created: `{PROJECT_PATH}/converter/output/{THEME_NAME}/` (complete Radix sub-theme)
- Created: `conversion-report.md` with Layout Composition Instructions
