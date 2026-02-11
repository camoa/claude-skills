---
description: Convert branded HTML pages to a Drupal Radix sub-theme with SDC components and Layout Builder composition
allowed-tools: Bash, Read, Write, Glob, Grep, AskUserQuestion, Skill
---

# Convert to Radix Command

Convert branded HTML pages (with metadata comments) into a Drupal Radix sub-theme featuring SDC components, SCSS tokens, Layout Builder configuration, and optional icon packs. The converter is metadata-driven — it parses `<!-- component: ... -->` annotations dynamically, not hardcoded to specific component types.

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

1. Current directory — check `./brand-philosophy.md`
2. Parent directory — check `../brand-philosophy.md`
3. Subdirectories — `find . -maxdepth 2 -name "brand-philosophy.md"`
4. If multiple found — ask user which project
5. If none found — tell user to run `/brand-init` first

Set `PROJECT_PATH` to the directory containing `brand-philosophy.md`.

#### Step 2: Find HTML Pages

Search for HTML files with metadata comments:
```
find {PROJECT_PATH}/html-pages -name "*.html" -type f 2>/dev/null
```

For each file found, check for metadata comment markers (`<!-- component:`) to confirm they are annotated pages. List found pages with their directory dates (extracted from the `YYYY-MM-DD` prefix in directory names).

If none found — tell user to run `/html-page` or `/html-page-quick` first, and ensure pages contain metadata comments.

#### Step 3: Select Pages

**AskUserQuestion**: "Which HTML pages should we convert?"

If 4 or fewer pages exist, list each as an option plus "All pages".

If more than 4 pages exist, show the 3 most recent (by directory date) plus "All pages".

Options format:
- **{page-name}** — {date}, {component count} components detected
- **All pages** — Convert everything found ({count} pages)

Store selected pages as `SELECTED_PAGES`.

---

### Phase 2: Drupal Context

#### Step 4: Drupal Codebase

**AskUserQuestion**: "Do you have an existing Drupal codebase to target?"
- **Yes — provide path** — "I'll scan config/sync/ for existing content types, views, and modules"
- **No — green-field** — "I'll generate a complete recommended structure from scratch"

If user selects "Yes", ask for the Drupal root path. Verify the path exists and contains `config/sync/`:
```
ls {DRUPAL_PATH}/config/sync/ 2>/dev/null
```

If `config/sync/` is missing, warn the user and ask whether to continue without backend inventory or provide a corrected path.

Store result as `DRUPAL_PATH` (path string or `null` for green-field).

#### Step 5: Theme Name

Read `brand-philosophy.md` to extract the brand name. Derive a suggested machine name:
- Lowercase the brand name
- Replace spaces and hyphens with underscores
- Remove special characters
- Truncate to 32 characters if needed

**AskUserQuestion**: "What should the Radix sub-theme be called?"
- **{suggested_name}** — Based on brand name "{brand name}"
- **{suggested_name}_theme** — Longer variant with _theme suffix
- **Custom** — Enter your own machine name

Validate the chosen name: lowercase letters, digits, and underscores only; must start with a letter; must be a valid Drupal machine name. If invalid, explain the constraints and ask again.

Store as `THEME_NAME`.

---

### Phase 3: Analysis

#### Step 6: Run Analysis

Read the following files:
- Each selected HTML page from `SELECTED_PAGES`
- `{PROJECT_PATH}/templates/html/*/design-system.md` (find the design system associated with the pages)
- `{PROJECT_PATH}/templates/html/*/canvas-philosophy.md`
- `{PROJECT_PATH}/brand-philosophy.md`

Invoke the `html-to-radix-analyzer` skill via the Skill tool with this context:
- HTML file paths and their contents
- `DRUPAL_PATH` (if provided, for config/sync scanning)
- Design system and canvas philosophy contents
- Brand philosophy contents

The skill parses metadata comments (`<!-- component: ... -->`, `<!-- prop: ... -->`, `<!-- slot: ... -->`) from each HTML page and returns:
- **components** — List of components with names, variants, props, slots, nesting
- **design_tokens** — Extracted from `:root { --color-*: ...; --font-*: ...; }` blocks
- **classifications** — Each component classified as: block_type, view_content_type, menu, form, or ambiguous
- **icons** — Icon references found in metadata or inline SVGs
- **inventory** — If DRUPAL_PATH provided: existing content types, views, vocabularies, modules, and reuse matches
- **atomic_levels** — Each component assigned: atom, molecule, organism
- **warnings** — Issues, conflicts, or items needing attention

Store the full analysis result as `ANALYSIS`.

---

### Phase 4: Review Plan

#### Step 7: Display Analysis Summary

Present the analysis to the user in a structured summary:

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
  Colors: {count}  |  Typography: {count}  |  Spacing: {count}  |  Other: {count}

Icons: {count} unique icons referenced
```

If `DRUPAL_PATH` was provided, also show:
```
Backend Inventory:
  Existing content types: {count} ({list reuse matches})
  Existing views:         {count} ({list reuse matches})
  Modules enabled:        {count relevant}
  Reusable:               {count} components match existing backend
  New:                    {count} components need new backend config
```

If warnings exist, list each one clearly.

#### Step 8: Review Plan

**AskUserQuestion**: "Here is the conversion plan. How would you like to proceed?"
- **Approve and continue** — "Generate the theme with these settings"
- **Modify classifications** — "I want to change how some components are handled"
- **Start over** — "Let me reconfigure from the beginning"

If **Start over**: return to Step 3.

If **Modify classifications**: for each component, show its current classification and ask the user to confirm or override. Use follow-up AskUserQuestion calls, grouping up to 4 components per question where practical:
- "{component_name}: currently classified as {classification}. Change to?"
- Options: Block type, View + content type, Menu, Form, Skip

After modifications, update `ANALYSIS` with the overrides and return to Step 7 to re-display the summary.

If **Approve and continue**: proceed to Phase 5.

---

### Phase 5: Resolve Ambiguities

#### Step 9: Handle Ambiguous Items

Only execute this step if `ANALYSIS` contains components flagged as `ambiguous: true`.

For each ambiguous component:

**AskUserQuestion**: "How should we handle '{component_name}'? (appears {count} times across pages)"
- **Custom block type** — "Static curated content, managed per-block in Layout Builder"
- **View + content type** — "Dynamic listing, each item is a content node"
- **Skip** — "Do not convert this component"

Update `ANALYSIS` with each resolution.

#### Step 10: Icon Strategy

If icons were found in `ANALYSIS`:

Display: "{count} unique icons referenced across components."

Check if `DRUPAL_PATH` has an existing icon module or icon pack configuration:
```
find {DRUPAL_PATH}/config/sync -name "ui_icons*" 2>/dev/null
ls {DRUPAL_PATH}/modules/custom/*/icons/ 2>/dev/null
```

If existing icon infrastructure found:
- Report what was found and suggest reusing it
- Store `ICON_STRATEGY = "reuse_existing"`

If no existing icons:
- Store `ICON_STRATEGY = "generate_pack"` (generate a Drupal Icon API pack using `extractor: svg`)

If no icons found in analysis, store `ICON_STRATEGY = "none"`.

#### Step 11: Module Review

Compile a list of recommended Drupal modules based on the analysis:
- **Required**: `drupal/radix`, `drupal/layout_builder` (core)
- **Recommended**: `drupal/layout_builder_styles` (section styling)
- **If icons**: `drupal/ui_icons` (Drupal Core Icon API)
- **If views detected**: `drupal/views` (core, usually enabled)
- **If forms detected**: `drupal/webform` or `drupal/contact` depending on complexity
- Any additional modules identified by the analyzer

**AskUserQuestion**: "These Drupal modules are recommended for this conversion:"
Show the compiled list with brief purpose for each.
- **Accept all** — "Install all recommended modules"
- **Customize** — "Let me review and adjust the module list"
- **Minimal** — "Only essential modules (radix + layout_builder)"

If **Customize**: show each module and let user toggle on/off via follow-up questions.

Store final module list as `MODULES`.

#### Step 12: Save Configuration

Write all collected decisions to `{PROJECT_PATH}/converter/radix-sdc.yml`:

```yaml
converter:
  target: radix-sdc
  created: {ISO date}
  theme_name: {THEME_NAME}
  drupal_path: {DRUPAL_PATH or null}

pages:
  - {list of selected page paths}

analysis:
  component_count: {count}
  token_count: {count}
  icon_count: {count}

classifications:
  {component_name}: {classification}
  # ... for each component

icon_strategy: {ICON_STRATEGY}

modules:
  - {module list}

ambiguity_resolutions:
  {component_name}: {resolution}
  # ... for each resolved ambiguity
```

Create the `converter/` directory if it does not exist.

---

### Phase 6: Generation

#### Step 13: Generate Theme

Invoke the `radix-sdc-generator` skill via the Skill tool with:
- Full `ANALYSIS` output from Step 6 (with any user modifications from Steps 8-9)
- `THEME_NAME` from Step 5
- `DRUPAL_PATH` (if provided)
- `ICON_STRATEGY` from Step 10
- `MODULES` list from Step 11
- Classification overrides and ambiguity resolutions
- Design system and brand philosophy contents

The skill generates:
- Theme directory structure under `{PROJECT_PATH}/converter/{THEME_NAME}/`
- `{THEME_NAME}.info.yml` — theme definition with Radix base theme
- `{THEME_NAME}.libraries.yml` — asset libraries
- SDC component directories under `components/` — each with `.twig`, `.yml` (schema), `.scss`
- Global SCSS with design tokens mapped to Bootstrap variables
- Layout Builder config exports under `config/` — section layouts with styles
- Icon pack directory (if `ICON_STRATEGY` is `generate_pack`)
- `package.json` with build tooling (Webpack or Vite)

---

### Phase 7: Completion

#### Step 14: Display Summary

Present the generation results:

```
-- Theme Generated --

Theme: {THEME_NAME}
Location: {PROJECT_PATH}/converter/{THEME_NAME}/

Files created: {total count}
  Theme config:    {count} (.info.yml, .libraries.yml, etc.)
  SDC components:  {count} ({list names with atomic levels})
  SCSS files:      {count}
  Config exports:  {count}
  Icon pack:       {count} icons (if applicable)

Module installation:
  composer require drupal/radix drupal/layout_builder_styles {other modules}
  drush en {module_list}
  drush theme:enable {THEME_NAME}
  drush config:set system.theme default {THEME_NAME}

Next steps:
  1. Copy theme to {DRUPAL_PATH}/themes/custom/{THEME_NAME}/ (if Drupal path provided)
  2. Run: cd {theme_path} && npm install
  3. Run: npm run build (production) or npm run dev (watch mode)
  4. Import config exports: drush config:import --partial --source={config_path}
  5. Configure Layout Builder on target content types
  6. Place SDC components in Layout Builder sections

Conversion config saved: {PROJECT_PATH}/converter/radix-sdc.yml
```

---

## Output

- Created: `{PROJECT_PATH}/converter/radix-sdc.yml` (conversion configuration)
- Created: `{PROJECT_PATH}/converter/{THEME_NAME}/` (complete Radix sub-theme)
- Created: SDC components, SCSS, config exports, and optional icon pack within theme directory
