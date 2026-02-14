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
- **Yes -- provide path** -- "I'll scan for existing content types, views, themes, and modules"
- **No -- green-field** -- "I'll generate a complete recommended structure from scratch"

If "Yes", ask for the Drupal root path, then:

1. **Discover config sync directory**:
   - Search for `settings.php` at: `{DRUPAL_PATH}/web/sites/default/settings.php`, then `{DRUPAL_PATH}/sites/default/settings.php`
   - Grep for `$settings['config_sync_directory']` to extract the path value
   - If the extracted path is relative, resolve it against `{DRUPAL_PATH}` (or `{DRUPAL_PATH}/web/`)
   - If grep finds nothing, fall back to checking these directories for YAML files: `{DRUPAL_PATH}/config/sync/`, `{DRUPAL_PATH}/sites/default/sync/`, `{DRUPAL_PATH}/../config/sync/`
   - If no config directory found, warn the user and suggest running `drush config:export` first
2. Store as `CONFIG_SYNC_DIR`.
3. Verify the directory exists and contains YAML files (at minimum `core.extension.yml`).

Store as `DRUPAL_PATH` (path string or `null`).

#### Step 4b: Existing Site Inventory

Only when `DRUPAL_PATH` is provided:

1. Read `{CONFIG_SYNC_DIR}/{current_theme}.settings.yml` for logo, favicon, features
2. List all `.html.twig` template files in the current theme directory
3. Get enabled views from `drush views:list --status=enabled` or scan config files
4. Get enabled modules from `drush pm:list --status=enabled --type=module` or `core.extension.yml`
5. Store as `SITE_INVENTORY`
6. Display inventory summary: "{N} templates, {N} views, {N} content types, {N} block types found in existing site"

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

Invoke the `html-to-radix-analyzer` skill with HTML file paths, `DRUPAL_PATH`, `CONFIG_SYNC_DIR`, and design context.

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

#### Step 9: Handle Ambiguous Items (Competing Agents)

For each ambiguous component, spawn a **team of competing sonnet agents** to debate the best Drupal pattern:

1. **Create team** via TeamCreate with sonnet agents:
   - **custom-block**: argues for custom block type (page-specific curated content via Layout Builder)
   - **content-view**: argues for content type + view (dynamic listing, admin-manageable)
   - **taxonomy-view**: argues for taxonomy vocabulary + view (categorized items) -- only when taxonomy is plausible
   - **devils-advocate**: challenges ALL proposals, looking for edge cases, scalability issues, content editor UX, maintenance burden

2. **Each agent receives** this context as a message:
   - Component type and variant (e.g., "testimonials, slider variant")
   - Props list with types (e.g., "quote: string, author: string, role: string, photo: image")
   - Slot details (item count, whether items are uniform)
   - First 30 lines of the component's raw HTML
   - Source page filename
   - Content excerpt: heading text and first sentence of body text
   - Site inventory summary (if available): existing content types, block types, views

3. **Each agent produces**: a short brief (3-5 sentences) explaining why their pattern is the best fit, with Drupal-specific rationale

4. **Devil's advocate** receives all other agents' briefs and raises concerns about each

5. **The command (opus) synthesizes** the debate: read all agent briefs, summarize each position into 1-2 sentences, and present via AskUserQuestion. Prefix with source HTML page filename and include content excerpts (heading text, 1-line description).
   - **Taxonomy-view** is only included when the component has items with a categorical structure (e.g., tags, categories, types) — skip this agent when items have no natural taxonomy.

**AskUserQuestion**: "[{source_page}] How should we handle '{component_name}' ({heading_excerpt})?"
- **Custom block type** -- "{custom-block agent's reasoning summary}"
- **Fields on content type** -- "Add directly to the node type when content appears on all pages of this type"
- **View + content type** -- "{content-view agent's reasoning summary}"
- **Taxonomy + view** -- "{taxonomy-view agent's reasoning summary}" (only when applicable)
- **Skip** -- "Do not convert this component"

6. **Shut down the team** after all ambiguities resolved

**NOT valid options**: "Hardcoded in template" is never acceptable. Paragraphs is not offered as a default.

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

Invoke the `radix-sdc-generator` skill with:
- Full analysis output (including `pageLayouts` from Part 1b)
- `THEME_NAME`, `THEME_LABEL`
- `DRUPAL_PATH`, `CONFIG_SYNC_DIR`
- `SITE_INVENTORY` (existing theme data, if available)
- `PAGE_ORDER` -- ordered list of pages (home first, then additive)
- Icon strategy, module list, and design context

Instruct the generator to follow the layered flow:
- Part 1: Scaffold (Radix CLI when available) + styleguide directories
- Part 2: Tokens → Bootstrap SCSS + styleguide token includes
- Part 3: Foundation (image styles with focal point + WebP, breakpoints, icons, LB styles) + styleguide foundation includes
- Part 4: Layout wireframes from `pageLayouts` + styleguide layout includes
- Part 5: Components (atoms → molecules → organisms per page) + styleguide component includes
- Part 6: Template overrides (skip existing)
- Part 7: Config exports (two-pass: pass1/ and pass2/)
- Part 8: Conversion report + styleguide master template

The skill generates:
- Theme directory with flat `components/` structure (via Radix CLI or scaffold reference)
- Foundation layer: image styles (focal point + WebP), breakpoints, icons, LB styles
- SDC components with `.component.yml`, `.twig`, `.scss` in atomic order per page
- Bootstrap-mapped SCSS with design tokens
- Template overrides mapping Drupal fields to SDC props (entity-level access, radix:block wrapper)
- Layout Builder config exports in `pass1/` and `pass2/` directories
- Layout composition instructions sourced from `pageLayouts`
- Styleguide page with master template + sub-template includes for each layer
- Conversion report with styleguide setup instructions

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
  Config exports:    {count} (pass1: {n}, pass2: {n})
  Icon pack:         {count} icons

Next steps:
  1. Install required modules:
     composer require drupal/layout_builder_styles drupal/radix {other_missing}
  2. Build theme assets:
     cd {theme_path} && npm install && npm run build
  3. Import config (two passes -- order matters):
     drush config:import --partial --source={config_path}/pass1/
     drush config:import --partial --source={config_path}/pass2/
  4. Enable theme:
     drush theme:enable {THEME_NAME}
     drush config:set system.theme default {THEME_NAME}
  5. Clear cache: drush cr
  6. Create a basic page at /styleguide (empty body)
  7. Rename node--styleguide.html.twig to node--{nid}.html.twig
  8. Visit /styleguide to verify tokens, foundation, and components
  9. Follow Layout Composition Instructions in conversion-report.md

Conversion report: {output_path}/conversion-report.md
```

---

## Output

- Created: `{PROJECT_PATH}/converter/radix-sdc.yml` (conversion configuration)
- Created: `{PROJECT_PATH}/converter/output/{THEME_NAME}/` (complete Radix sub-theme)
- Created: `conversion-report.md` with Layout Composition Instructions
