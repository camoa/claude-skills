---
name: radix-sdc-generator
description: Use when generating a Drupal Radix sub-theme with SDC components from HTML analysis. Creates complete theme scaffolding, SDC components, SCSS with Bootstrap mapping, template overrides, Layout Builder config, and icon pack.
version: 1.0.0
model: opus
user-invocable: false
---

# Radix SDC Generator

Generate a complete Drupal Radix 6.0.2 sub-theme from the analysis output produced by `html-to-radix-analyzer`. Produce a fully scaffolded theme with SDC components, Bootstrap-mapped SCSS, template overrides with field-to-prop mapping, Layout Builder config, and an optional icon pack.

## Inputs

- **Analysis output** -- YAML with: `designTokens`, `components`, `classifications`, `backendReuse`, `icons`, `templateSuggestions`
- **THEME_NAME** -- machine name (lowercase, underscores)
- **THEME_LABEL** -- human-readable label
- **DRUPAL_PATH** -- (optional) absolute path to Drupal installation root
- **PROJECT_PATH** -- project directory for output when DRUPAL_PATH is not set
- **HTML_FILE** -- path to the source HTML file (needed for icon extraction)

## Output Location

- If `DRUPAL_PATH` is provided: write to `{DRUPAL_PATH}/themes/custom/{THEME_NAME}/`
- Otherwise: write to `{PROJECT_PATH}/converter/output/{THEME_NAME}/`

Set `THEME_DIR` to the chosen output path.

## External Guide Discovery

Before generating, WebFetch `https://camoa.github.io/dev-guides/llms.txt` to discover current guide pages. Consult:
- `design-systems/bootstrap/` for token-to-variable mapping details
- `design-systems/radix-sdc/` for sub-theme architecture, build tools, SDC development
- `design-systems/radix-components/` for component API and override patterns
- `drupal/sdc/` for YAML schema, props/slots conventions

---

## Part 1: Theme Scaffolding

Create the complete Radix sub-theme directory structure using `references/radix-theme-scaffold.md`.

1. Create all directories:
   - `{THEME_DIR}/components/` (flat -- NO atomic subdirs)
   - `{THEME_DIR}/icons/`
   - `{THEME_DIR}/src/scss/base/`
   - `{THEME_DIR}/src/js/`
   - `{THEME_DIR}/src/assets/{images,icons,fonts}/`
   - `{THEME_DIR}/templates/layout/`
   - `{THEME_DIR}/templates/block/`
   - `{THEME_DIR}/templates/node/`
   - `{THEME_DIR}/templates/views/`
   - `{THEME_DIR}/includes/`
   - `{THEME_DIR}/config/`
   - `{THEME_DIR}/build/`

2. Write each scaffold file from the reference, replacing `{THEME_NAME}` and `{THEME_LABEL}`:
   - `{THEME_NAME}.info.yml` -- library is `{THEME_NAME}/style`, includes ckeditor5-stylesheets
   - `{THEME_NAME}.libraries.yml` -- library name `style` (NOT `global`)
   - `{THEME_NAME}.theme` -- auto-loader glob for `includes/*.theme`
   - `webpack.mix.js` -- dotenv, component SCSS/JS globs, asset copy, stylelint
   - `package.json` -- ~16 devDependencies (biome, drupal-radix-cli, stylelint, dotenv, etc.)
   - `src/scss/main.style.scss` -- init, bootstrap, base imports
   - `src/scss/_init.scss` -- custom variables BEFORE bootstrap functions
   - `src/scss/_bootstrap.scss` -- all Bootstrap modules + helpers + utilities/api
   - `src/scss/base/_variables.scss` (placeholder -- populated in Part 2)
   - `src/scss/base/_elements.scss`
   - `src/scss/base/_typography.scss` (placeholder -- populated in Part 2)
   - `src/scss/base/_mixins.scss` (empty placeholder)
   - `src/scss/base/_utilities.scss` (empty placeholder)
   - `src/scss/base/_drupal-overrides.scss` (empty placeholder)
   - `src/scss/base/_functions.scss` (empty placeholder)
   - `src/scss/base/_helpers.scss` (empty placeholder)
   - `src/js/main.script.js`
   - Config files: `.env.example`, `.nvmrc`, `.npmrc`, `.browserslistrc`, `biome.json`, `.stylelintrc.json`
   - `.gitignore`

3. Write section template overrides from the scaffold reference:
   - `templates/layout/layout--onecol.html.twig`
   - `templates/layout/layout--twocol-section.html.twig`
   - `templates/layout/layout--threecol-section.html.twig`

4. Install new modules via composer (when `DRUPAL_PATH` is provided):
   - Check `{DRUPAL_PATH}/composer.json` `require` section
   - Run `composer require {missing_packages}` for any not present
   - If `DRUPAL_PATH` is not set, list the command in the report instead

---

## Part 2: Token to Bootstrap SCSS

**CRITICAL**: Read `references/drupal-best-practices.md` before generating any SCSS.

Apply the 6px threshold framework to convert design tokens into Bootstrap SCSS overrides. Consult external guide pages at `design-systems/bootstrap/` for detailed mapping tables.

1. For each design token, determine the mapping action: accommodate, extend, customize, or create.

2. Generate `src/scss/base/_variables.scss`:
   - Color overrides: `$primary`, `$secondary`, etc.
   - `$custom-colors` map for brand-specific colors
   - Typography: `$font-family-base`, `$font-family-heading`, heading sizes
   - Spacing: `$spacer`, `$spacers` map extensions
   - Layout: `$border-radius`, `$container-max-widths`, `$box-shadow` variants
   - Section header comments for each category

3. Generate `src/scss/base/_typography.scss`:
   - `@import url(...)` for Google Fonts
   - Heading font-family rule applying `$font-family-heading`

4. Update `src/scss/base/_elements.scss`:
   - `:root` block with CSS custom properties for interaction tokens

5. Record every mapping decision in a `tokenMapping` array for the report.

---

## Part 3: SDC Component Generation

For each component in the analysis output, generate a complete SDC in `components/{name}/` (flat directory).

**CRITICAL**: Read `references/drupal-best-practices.md` for mandatory SCSS variable discipline rules.

1. Output directory: `{THEME_DIR}/components/{component-name}/` (flat -- no atomic subdirs)

2. Check the `radixBase` field: if a Radix base component is identified, note it in component.yml description.

3. Generate `{component-name}.component.yml`:
   - `$schema`: Drupal 11 stable URL
   - `name`, `status: experimental`, `group: {THEME_NAME}`
   - `description` including atomic level (e.g., "Hero section organism")
   - `props.properties.attributes` with `Drupal\Core\Template\Attribute`
   - `props.properties.{component_name}_utility_classes` as array
   - Props and slots from analysis

4. Generate `{component-name}.twig`:
   - File-level comment documenting props and slots
   - `classes` array with base class + utility classes merge
   - `attributes.addClass(classes)` on outermost element
   - Bootstrap utility classes for layout

5. Generate `{component-name}.scss`:
   - Import: `@import "../../src/scss/init";` (2 levels up from `components/{name}/`)
   - BEM-structured styles using Bootstrap variables and mixins
   - **MANDATORY**: Bootstrap SCSS variables for ALL values -- no hex colors, font-family literals, hardcoded font-size/font-weight, or inline transitions

---

## Part 4: Template Overrides

Generate Twig template overrides that map Drupal entity fields to SDC component props. Follow patterns from `references/template-matching-patterns.md`.

### Block Content Templates

For each component classified as `block_type`:

1. Create `templates/block/block--block-content--type--{name}.html.twig`
2. Use the hybrid pattern: embed `radix:block` --> override content block --> include custom SDC
3. Map each field to the corresponding component prop using field access patterns

### View Templates

For each component classified as `content_type_with_view`:

1. Create `templates/node/node--{type}--teaser.html.twig` for view row display
2. Map node fields to card/item SDC component props

### Navigation and Footer

1. Create `templates/block/block--system-menu-block--main.html.twig` if navbar component exists
2. Create `templates/block/block--system-menu-block--footer.html.twig` if footer component exists
3. Embed radix:navbar or custom SDC with menu render array as slot

---

## Part 5: Icon Pack

If the analysis found icons, generate a Drupal Icon API icon pack.

1. Run the extraction script:
   ```
   node "$DESIGN_SYSTEM_CONVERTER_DIR/scripts/extract-icons.js" extract {HTML_FILE} {THEME_DIR}/icons/
   ```

2. Verify SVG files in `{THEME_DIR}/icons/`

3. Generate `{THEME_NAME}.icons.yml` at theme root with svg extractor config

---

## Part 6: Config Exports

Generate Drupal config YAML for backend entities identified by the analyzer.

### Block types (curated content):
- `block_content.type.{name}.yml`
- `field.storage.block_content.field_{prop_name}.yml` with appropriate field type
- `field.field.block_content.{block_type}.field_{prop_name}.yml`
- Multi-value fields: `cardinality: -1`

### Content types (repeating content):
- `node.type.{name}.yml`
- Field storage and instance configs with `entity_type: node`
- `views.view.{name}.yml` with block display for LB embedding

### Backend reuse:
- Do NOT generate config for components matching existing backend
- Record reuse in the report

### LB Styles:
- `layout_builder_styles.group.*.yml` for background, padding, container width
- `layout_builder_styles.style.*.yml` for each style option

Write all config to the exports directory. See `references/layout-builder-config.md` for templates.

---

## Part 7: Conversion Report

Generate `conversion-report.md` at the root of the output directory.

### Required Sections

1. **Generated Files** -- table of every file with relative path and description
2. **Required Modules** -- Drupal modules needed
3. **Token Mapping** -- every mapping decision from Part 2
4. **Components** -- table with component name, atomic level, SDC path (flat), Radix base, classification
5. **Template Overrides** -- table of template files with field-to-prop mapping
6. **Backend Reuse Summary** -- reuse/create_new actions per component
7. **Layout Composition Instructions** -- see `references/layout-builder-config.md` for instruction format:
   - Prerequisites (config import, LB enable)
   - Section-by-section table (layout type, background, padding, block placements)
   - Navigation/footer (outside LB, in theme regions)
   - Post-setup checklist
8. **Manual Steps** -- actions the developer must perform after generation
9. **Warnings and Recommendations** -- issues, borderline mappings, accessibility concerns

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| extract-icons.js fails | Node.js not available | Verify `node` is on PATH |
| SCSS import errors | Bootstrap not installed | Run `npm install` in theme directory |
| component.yml validation fails | Invalid prop type | Use valid JSON Schema types |
| npm run build fails | Wrong devDependencies | Ensure package.json matches scaffold reference |

## References

- `references/drupal-best-practices.md` -- **MANDATORY** SCSS variable discipline, SDC schema, JS patterns
- `references/radix-theme-scaffold.md` -- Complete theme directory template (REWRITTEN from real starterkit)
- `references/template-matching-patterns.md` -- Template overrides and field-to-prop mapping
- `references/layout-builder-config.md` -- LB styles, config export format, composition instructions
