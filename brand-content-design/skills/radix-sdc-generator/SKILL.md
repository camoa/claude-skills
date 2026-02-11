---
name: radix-sdc-generator
description: Use when generating a Drupal Radix sub-theme with SDC components from HTML analysis. Creates complete theme scaffolding, SDC components, SCSS with Bootstrap mapping, Layout Builder config, and icon pack.
version: 2.2.0
model: opus
user-invocable: false
---

# Radix SDC Generator

Generate a complete Drupal Radix 6.0.2 sub-theme from the analysis output produced by `html-to-radix-analyzer`. Receive the analysis YAML (design tokens, component inventory with props/slots/atomic levels, pattern classifications, backend reuse matches, and icon list). Produce a fully scaffolded theme with SDC components, Bootstrap-mapped SCSS, Layout Builder config, and an optional icon pack.

## Inputs

Receive from the analyzer or calling command:

- **Analysis output** -- YAML with: `designTokens`, `components` (each with `name`, `variant`, `atomicLevel`, `props`, `slots`, `radixBase`, `classification`), `backendReuse` (existing config matches), `icons` (list of icon names found).
- **THEME_NAME** -- machine name (lowercase, underscores).
- **THEME_LABEL** -- human-readable label.
- **DRUPAL_PATH** -- (optional) absolute path to the Drupal installation root.
- **PROJECT_PATH** -- project directory for output when DRUPAL_PATH is not set.
- **HTML_FILE** -- path to the source HTML file (needed for icon extraction).

## Output Location

- If `DRUPAL_PATH` is provided: write to `{DRUPAL_PATH}/themes/custom/{THEME_NAME}/`.
- Otherwise: write to `{PROJECT_PATH}/converter/output/{THEME_NAME}/`.

Set `THEME_DIR` to the chosen output path for use throughout all parts.

---

## Part 1: Theme Scaffolding

Create the complete Radix sub-theme directory structure using `references/radix-theme-scaffold.md` as the template.

1. Create all directories:
   - `{THEME_DIR}/components/atoms/`
   - `{THEME_DIR}/components/molecules/`
   - `{THEME_DIR}/components/organisms/`
   - `{THEME_DIR}/icons/`
   - `{THEME_DIR}/src/scss/base/`
   - `{THEME_DIR}/src/js/`
   - `{THEME_DIR}/templates/layout/`
   - `{THEME_DIR}/includes/`
   - `{THEME_DIR}/build/`

2. Write each scaffold file from the reference, replacing all `{THEME_NAME}` occurrences with the actual machine name and `{THEME_LABEL}` with the human-readable label:
   - `{THEME_NAME}.info.yml`
   - `{THEME_NAME}.libraries.yml`
   - `webpack.mix.js`
   - `package.json`
   - `src/scss/main.style.scss`
   - `src/scss/_init.scss`
   - `src/scss/_bootstrap.scss`
   - `src/scss/base/_variables.scss` (placeholder -- populated in Part 2)
   - `src/scss/base/_elements.scss`
   - `src/scss/base/_typography.scss` (placeholder -- populated in Part 2)
   - `src/js/main.script.js`
   - `includes/{THEME_NAME}.theme`
   - `.gitignore`

3. Write section template overrides from the scaffold reference:
   - `templates/layout/layout--onecol.html.twig`
   - `templates/layout/layout--twocol-section.html.twig`
   - `templates/layout/layout--threecol-section.html.twig`

Verify all files exist after writing.

---

## Part 2: Token to Bootstrap SCSS

Apply the 6px threshold framework from `references/token-to-bootstrap-mapping.md` to convert design tokens into Bootstrap SCSS overrides.

1. For each design token in `designTokens`, determine the mapping action:
   - **Accommodate**: token value is within 6px (or delta E < 5 for colors) of Bootstrap's default. Do not write an override; add a comment noting the accommodation.
   - **Extend**: token adds to an existing Bootstrap map (colors, spacers, container widths). Write the map extension.
   - **Customize**: token overrides a Bootstrap variable. Write the variable override.
   - **Create**: token has no Bootstrap equivalent. Write a CSS custom property in `:root`.

2. Generate `src/scss/base/_variables.scss`:
   - Write color overrides: `$primary`, `$secondary`, etc.
   - Write `$custom-colors` map for brand-specific colors not in Bootstrap defaults.
   - Write typography overrides: `$font-family-base`, `$font-family-heading`, `$font-size-base`, `$h1-font-size` through `$h6-font-size`.
   - Write spacing overrides: `$spacer` base value, `$spacers` map extensions.
   - Write layout overrides: `$border-radius`, `$container-max-widths`, `$box-shadow` variants.
   - Add section header comments for each category.

3. Generate `src/scss/base/_typography.scss`:
   - Write `@import url(...)` for Google Fonts if font names are recognized Google Fonts.
   - Otherwise write `@font-face` declarations with `font-display: swap`.
   - Write heading font-family rule applying `$font-family-heading`.

4. Update `src/scss/base/_elements.scss`:
   - Populate `:root` block with CSS custom properties for interaction tokens (transition-duration, transition-easing, min-tap-target, focus-ring-width, focus-ring-color).

5. Record every mapping decision in a `tokenMapping` array for the conversion report (see mapping output format in the reference).

---

## Part 3: SDC Component Generation

For each component in the analysis output, generate a complete SDC directory. Follow patterns from `references/sdc-patterns.md`.

1. Determine output directory from `atomicLevel`:
   - atom: `{THEME_DIR}/components/atoms/{component-name}/`
   - molecule: `{THEME_DIR}/components/molecules/{component-name}/`
   - organism: `{THEME_DIR}/components/organisms/{component-name}/`

2. Check the `radixBase` field from the analysis:
   - If a Radix base component is identified (e.g., `card`, `accordion`, `button`), note this in the component.yml description and follow the same prop schema structure.
   - If `radixBase` is null, create the component from scratch.

3. Generate `{component-name}.component.yml`:
   - Set `$schema` to the Drupal core metadata schema URL.
   - Set `name` to the human-readable component name.
   - Set `status` to `experimental`.
   - Set `group` to `{THEME_NAME}`.
   - Add `description` from the analysis.
   - Add `props.properties.attributes` with type `Drupal\Core\Template\Attribute`.
   - Add `props.properties.{component_name}_utility_classes` as array of strings with empty default.
   - For each prop from the analysis, add a JSON Schema property with appropriate type, title, and description.
   - For each slot from the analysis, add a slot entry with title and description.
   - Set `required` array for props marked as required.

4. Generate `{component-name}.twig`:
   - Add file-level comment documenting all props and slots.
   - Set `classes` array: base component class + utility classes merge.
   - Render `attributes.addClass(classes)` on the outermost element.
   - For each prop: render with appropriate HTML element and Bootstrap classes.
   - For each slot: render as `{% block slot_name %}` with content check.
   - Use Bootstrap utility classes for layout (grid, flexbox, spacing).
   - Use BEM class names for component-specific styling.

5. Generate `{component-name}.scss`:
   - Import `_init.scss` at the top.
   - Write BEM-structured styles using Bootstrap variables and mixins.
   - Include responsive breakpoints where the component needs layout changes.
   - Reference CSS custom properties for transitions and interactions.

---

## Part 4: Layout Builder Config

Generate Layout Builder styles and section configuration from `references/layout-builder-config.md`.

1. Generate `layout_builder_styles` group configs:
   - `layout_builder_styles.group.background_color.yml`
   - `layout_builder_styles.group.padding.yml`
   - `layout_builder_styles.group.container_width.yml`

2. Generate `layout_builder_styles` style configs:
   - One background style per color in `$theme-colors` (primary, secondary, light, dark, white, plus any custom brand colors).
   - Padding styles mapped from spacing tokens (small, medium, large, none).
   - Container width styles (full, default, narrow).

3. Create section template overrides if not already created in Part 1. Verify the nested container pattern is applied: outer full-width div, inner `.container`.

4. Map the HTML page structure to Layout Builder sections:
   - Read the page section order from the analysis.
   - For each page section, determine: layout type (onecol, twocol, threecol), style selections (background, padding), and block placements.
   - Navigation and footer components map to theme region block placements, not LB sections.
   - Record the mapping in `pageLayout` format for the report.

5. Write all config YAML files to:
   - `{DRUPAL_PATH}/config/converter-exports/` if Drupal path is provided.
   - `{PROJECT_PATH}/converter/config-exports/` otherwise.

---

## Part 5: Icon Pack

If the analysis found icons (the `icons` list is non-empty), generate a Drupal Icon API icon pack.

1. Run the extraction script:
   ```
   node "$BRAND_CONTENT_DESIGN_DIR/scripts/extract-icons.js" extract {HTML_FILE} {THEME_DIR}/icons/
   ```

2. Verify SVG files were created in `{THEME_DIR}/icons/`. List the directory and confirm each icon from the analysis has a corresponding `.svg` file.

3. Generate `{THEME_NAME}.icons.yml` in the theme root:
   ```yaml
   {THEME_NAME}_icons:
     label: '{THEME_LABEL} Icons'
     description: 'Brand icons extracted from design system'
     extractor: svg
     enabled: true
     template: '<svg xmlns="http://www.w3.org/2000/svg" width="{{ size }}" height="{{ size }}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">{{ content }}</svg>'
     config:
       sources:
         - icons/
       size: 24
   ```

4. If the extraction script reports missing icons, log warnings but continue. The icon pack works with whatever SVGs were successfully extracted.

---

## Part 6: Config Exports

Generate Drupal config YAML for backend entities identified by the analyzer.

### For components classified as block_type (curated content):

1. Generate `block_content.type.{name}.yml` with id, label, and description.
2. For each prop in the component:
   - Generate `field.storage.block_content.field_{prop_name}.yml` with appropriate field type:
     - string props: `type: string`, `max_length: 255`
     - text props: `type: text_long`
     - url props: `type: link`
     - image props: `type: image`
     - number props: `type: integer` or `type: decimal`
   - Generate `field.field.block_content.{block_type}.field_{prop_name}.yml` with label and settings.
   - For multi-value fields (from components with repeated items, 2-3 count): set `cardinality: -1` (unlimited).

### For components classified as content_type_with_view (repeating content):

1. Generate `node.type.{name}.yml` with type, label, description.
2. Generate field storage and field instance configs as above, but with `entity_type: node`.
3. Generate `views.view.{name}.yml` with:
   - Default display: teaser view mode, pager, sort by created date descending.
   - Block display: for embedding in Layout Builder sections.
   - Filter by content type and published status.

### For components classified as webform:

1. Generate a basic `webform.webform.{name}.yml` with:
   - Form elements derived from input fields in the analysis.
   - Email handler configuration stub.

### Backend Reuse

For components where `backendReuse` matched an existing config:
- Do NOT generate new config YAML.
- Record the reuse in the report: "Reusing existing {config_id} for {component_name}."

Write all config files to the config exports directory.

---

## Part 7: Conversion Report

Generate `conversion-report.md` at the root of the output directory.

### File Manifest

List every generated file with its relative path from the theme root:

```markdown
## Generated Files

| File | Description |
|---|---|
| {THEME_NAME}.info.yml | Theme info |
| {THEME_NAME}.libraries.yml | Asset libraries |
| src/scss/base/_variables.scss | Bootstrap overrides |
| components/atoms/button/button.component.yml | Button SDC |
| ... | ... |
```

### Module Requirements

List Drupal modules required for the generated configuration:

```markdown
## Required Modules

- layout_builder (core)
- layout_builder_styles (contrib)
- block_content (core)
- views (core)
- webform (contrib) -- only if webform config generated
```

### Manual Steps

List actions the developer must perform after generation:

```markdown
## Manual Steps

1. Run `composer install` in the Drupal root if missing contrib modules.
2. Run `npm install && npm run build` in the theme directory.
3. Enable the theme: `drush then {THEME_NAME}`.
4. Set as default: `drush config:set system.theme default {THEME_NAME}`.
5. Import config exports: `drush config:import --partial --source=config/converter-exports/`.
6. Enable Layout Builder on the target content type.
7. Review and adjust component styles in the browser.
```

### Token Mapping Table

Display every mapping decision from Part 2:

```markdown
## Token Mapping

| Token | Value | Bootstrap Variable | Action | Reasoning |
|---|---|---|---|---|
| --color-primary | #2563eb | $primary | customize | Delta E 12.4 |
| --font-size-base | 16px | $font-size-base | accommodate | Exact match |
| ... | ... | ... | ... | ... |
```

### Component Inventory

```markdown
## Components

| Component | Atomic Level | SDC Path | Radix Base | Classification |
|---|---|---|---|---|
| hero | organism | components/organisms/hero/ | -- | single_promotional |
| card | molecule | components/molecules/card/ | card (extend) | curated_content |
| button | atom | components/atoms/button/ | button (extend) | -- |
| ... | ... | ... | ... | ... |
```

### Backend Reuse Summary

```markdown
## Backend Reuse

| Component | Action | Config |
|---|---|---|
| blog | reuse | node.type.article (existing) |
| features | create_new | block_content.type.features |
| ... | ... | ... |
```

### Warnings and Recommendations

Include any issues encountered during generation:

- Components where the Radix base extension may need manual adjustment.
- Tokens that were accommodated but are borderline (5-6px difference).
- Missing icons that could not be extracted.
- Ambiguous pattern classifications that defaulted to quick-mode resolution.
- Accessibility concerns (contrast ratios to verify, tap target sizes to check).

---

## Examples

### Example 1: Landing Page Theme (Green-Field)

**Input:** Analysis with 6 components (nav, hero, feature-grid, testimonials, CTA, footer), 15 design tokens, 4 icons. No existing Drupal backend.

**Generation result:**
- Theme scaffold at `converter/my_brand/`
- `_variables.scss` with `$primary`, `$secondary`, `$font-family-base`, `$spacers` overrides
- 6 SDC components: `organisms/navbar/`, `organisms/hero/`, `organisms/feature-grid/`, `molecules/testimonial-card/`, `organisms/cta/`, `organisms/footer/`
- `layout_builder_styles` config: 3 background colors, 3 padding levels, 2 container widths
- Icon pack: `my_brand.icons.yml` + 4 SVG files in `icons/`
- Config exports: 3 block types, 1 view + content type (if testimonials = view)
- Conversion report listing all generated files and next steps

### Example 2: Blog Redesign (Existing Backend)

**Input:** Analysis with 4 components, existing article content type + frontpage view matched. 2 components reuse existing backend.

**Generation result:**
- Theme scaffold with `_variables.scss` mapped from blog design tokens
- 4 SDC components (card extends Radix card, navbar extends Radix navbar)
- No icon pack (no icons in design)
- Config exports: 1 new block type (hero), modified view display config
- Report shows 50% backend reuse, 50% new config

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| extract-icons.js fails | Node.js not available or HTML file not found | Verify `node` is on PATH and HTML file path is correct |
| SCSS import errors | Bootstrap not installed in theme | Run `npm install` in theme directory before compiling |
| component.yml validation fails | Prop type not a valid JSON Schema type | Use `string`, `number`, `boolean`, `array`, `object`, or `Drupal\Core\Template\Attribute` |
| Layout section template not rendering | Template override not registered | Clear Drupal cache: `drush cr` after copying theme |
| Icon pack not discovered | `.icons.yml` file not at theme root | Ensure file is `{THEME_NAME}.icons.yml` at the same level as `.info.yml` |

## References

- `references/radix-theme-scaffold.md` -- Complete theme directory template and file contents.
- `references/token-to-bootstrap-mapping.md` -- 6px threshold framework and mapping tables.
- `references/sdc-patterns.md` -- component.yml, Twig, and SCSS templates with examples.
- `references/layout-builder-config.md` -- Layout Builder styles and section configuration.
- `scripts/extract-icons.js` -- CLI tool for extracting inline SVGs from HTML files.
