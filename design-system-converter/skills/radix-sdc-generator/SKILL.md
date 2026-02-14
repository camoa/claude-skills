---
name: radix-sdc-generator
description: Use when generating a Drupal Radix sub-theme with SDC components from HTML analysis. Creates theme scaffolding, foundation layer (image styles, icons, LB styles), SDC components in design-system-first order per page, template overrides, Layout Builder config, and a styleguide page.
version: 1.1.0
model: opus
user-invocable: false
---

# Radix SDC Generator

Generate a complete Drupal Radix 6.0.2 sub-theme from the analysis output produced by `html-to-radix-analyzer`. Produce a fully scaffolded theme with SDC components, Bootstrap-mapped SCSS, template overrides with field-to-prop mapping, Layout Builder config, and a styleguide page for visual verification.

### Generation Flow

```
Analysis (with layout extraction) → Tokens → Foundation → Layouts → Components → Templates → Config → Report
                                      ↓          ↓           ↓         ↓
                                   styleguide grows with each layer (sub-template includes)
```

## Inputs

- **Analysis output** -- YAML with: `designTokens`, `components`, `pageLayouts`, `classifications`, `backendReuse`, `icons`, `imageContexts`, `templateSuggestions`, `existingTheme`
- **THEME_NAME** -- machine name (lowercase, underscores)
- **THEME_LABEL** -- human-readable label
- **DRUPAL_PATH** -- (optional) absolute path to Drupal installation root
- **PROJECT_PATH** -- project directory for output when DRUPAL_PATH is not set
- **HTML_FILE** -- path to the source HTML file (needed for icon extraction)
- **SITE_INVENTORY** -- (optional) existing theme data from analyzer: templates, settings, views, modules
- **PAGE_ORDER** -- ordered list of pages to process (home first, then additive)

## Output Location

- If `DRUPAL_PATH` is provided: write to `{DRUPAL_PATH}/themes/custom/{THEME_NAME}/`
- Otherwise: write to `{PROJECT_PATH}/converter/output/{THEME_NAME}/`

Set `THEME_DIR` to the chosen output path.

## External Guide Discovery (MANDATORY)

**MANDATORY first step**: WebFetch `https://camoa.github.io/dev-guides/llms.txt` to discover current guide pages.

1. Fetch `llms.txt` and list the discovered pages before proceeding
2. Validate that at least 3 guide sections were discovered (e.g., `design-systems/`, `drupal/`)
3. If WebFetch fails or validation fails, STOP and warn the user -- do not fall back to local references only
4. Consult these sections as generation progresses:
   - `design-systems/bootstrap/` for token-to-variable mapping details
   - `design-systems/radix-sdc/` for sub-theme architecture, build tools, SDC development
   - `design-systems/radix-components/` for component API and override patterns
   - `drupal/sdc/` for YAML schema, props/slots conventions

---

## Part 1: Theme Scaffolding

### When DRUPAL_PATH is provided (preferred):

Use the Radix CLI to create the scaffold -- do NOT generate it manually from the reference file.

1. **Check Radix is installed**:
   - Verify `{DRUPAL_PATH}/themes/contrib/radix/` exists
   - If not: `composer require drupal/radix` from `{DRUPAL_PATH}`

2. **Check required modules**:
   - Get enabled modules from `SITE_INVENTORY.modules` or `drush pm:list --status=enabled --type=module`
   - Required: `layout_builder`, `layout_builder_styles`
   - Run `composer require {missing_packages}` for any not present

3. **Create sub-theme via Radix CLI**:
   ```
   drush --include="{DRUPAL_PATH}/themes/contrib/radix" radix:create {THEME_NAME} "{THEME_LABEL}"
   ```
   This generates the complete scaffold with correct structure, webpack.mix.js, package.json, etc.

4. **Overlay customizations only** (on top of CLI-generated scaffold):
   - `src/scss/base/_variables.scss` -- populated in Part 2
   - `src/scss/base/_typography.scss` -- populated in Part 2
   - `src/scss/base/_elements.scss` -- custom properties from design tokens
   - `src/scss/_init.scss` -- add `$theme-colors: map-merge($theme-colors, $custom-colors);` after `@import "~bootstrap/scss/maps";`
   - Verify `webpack.mix.js` does NOT contain `mix.version()` -- remove if present (breaks Drupal asset paths)
   - Verify `src/scss/_bootstrap.scss` does NOT duplicate `@import "~bootstrap/scss/utilities"` or `@import "~bootstrap/scss/root"` (already in `_init.scss`)

5. **Existing site logo/favicon**:
   - If `SITE_INVENTORY` contains logo settings, read the logo path from `{current_theme}.settings` config
   - Do NOT copy content images into `src/assets/images/` -- content images come from Drupal fields, not the theme

6. Write section template overrides:
   - `templates/layout/layout--onecol.html.twig`
   - `templates/layout/layout--twocol-section.html.twig`
   - `templates/layout/layout--threecol-section.html.twig`

7. **Create styleguide directory structure**:
   ```
   {THEME_DIR}/templates/styleguide/
   {THEME_DIR}/templates/styleguide/includes/
   {THEME_DIR}/templates/styleguide/includes/tokens/
   {THEME_DIR}/templates/styleguide/includes/foundation/
   {THEME_DIR}/templates/styleguide/includes/layouts/
   {THEME_DIR}/templates/styleguide/includes/atoms/
   {THEME_DIR}/templates/styleguide/includes/molecules/
   {THEME_DIR}/templates/styleguide/includes/organisms/
   ```

### When DRUPAL_PATH is NOT provided (fallback):

1. Use `references/radix-theme-scaffold.md` as the generation template
2. Create all directories and files per the reference
3. Warn in the report: "Radix CLI is preferred -- run `drush radix:create` when deploying to a Drupal site"
4. Apply same overlay customizations as above

---

## Part 2: Token to Bootstrap SCSS

**CRITICAL**: Read `references/drupal-best-practices.md` before generating any SCSS.

Apply the 6px threshold framework to convert design tokens into Bootstrap SCSS overrides. Consult external guide pages at `design-systems/bootstrap/` for detailed mapping tables.

1. For each design token, determine the mapping action: accommodate, extend, customize, or create.

2. Generate `src/scss/base/_variables.scss`:
   - Color overrides: `$primary`, `$secondary`, etc.
   - `$custom-colors` map for brand-specific colors -- **custom color keys must NOT include the utility prefix** (use `"alt"` not `"bg-alt"`, because Bootstrap generates `bg-{key}` classes, so `"bg-alt"` produces `bg-bg-alt`)
   - Typography: `$font-family-base`, `$font-family-heading`, heading sizes
   - Spacing: `$spacer`, `$spacers` map extensions
   - Layout: `$border-radius`, `$container-max-widths`, `$box-shadow` variants
   - Section header comments for each category
   - Include `$theme-colors: map-merge($theme-colors, $custom-colors);` in `_init.scss` after `@import "~bootstrap/scss/maps";` (the merge MUST happen after maps are loaded)

3. Generate `src/scss/base/_typography.scss`:
   - `@import url(...)` for Google Fonts
   - Heading font-family rule applying `$font-family-heading`

4. Update `src/scss/base/_elements.scss`:
   - `:root` block with CSS custom properties for interaction tokens

5. Record every mapping decision in a `tokenMapping` array for the report.

### Styleguide Token Includes

After generating SCSS variables, generate styleguide includes in `templates/styleguide/includes/tokens/`:

- **`color-swatches.html.twig`** -- renders each color as a swatch div with soft background (`bg-opacity-75` or inline `rgba()`), shows variable name, hex value, and Bootstrap mapping
- **`typography.html.twig`** -- renders h1-h6, body sizes, font families with live text samples
- **`spacing.html.twig`** -- visualizes spacer scale as colored bars with captions
- **`interaction.html.twig`** -- shows transition/timing tokens with animated examples

Each include uses the `test-section` wrapper pattern:

```twig
<div class="test-section test-section--colors">
  <h3>Color Tokens</h3>
  <div class="row g-3">
    <div class="col-md-3">
      <div class="rounded p-3 border" style="background-color: rgba({r},{g},{b}, 0.85);">
        <strong>$primary</strong><br><small>#2563eb</small>
      </div>
    </div>
    ...
  </div>
</div>
```

Use soft colored backgrounds with transparency and borders on all visual elements for clarity.

---

## Part 3: Foundation

Consolidate foundational elements that must exist BEFORE atoms, since atoms depend on image styles, icons, and LB style groups.

### 3a: Image Styles (moved from former Part 5b)

Generate Drupal image style and responsive image style configs from `imageContexts` in the analysis output.

1. For each unique image context, compare suggested styles against `SITE_INVENTORY.image_styles`:
   - Matching ratio + similar size (within 50px) → reuse existing style, skip generation
   - No match → generate new `image.style.{name}.yml` in `pass1/`

2. **Focal point**: Check if `focal_point` module is in `SITE_INVENTORY.modules`. If enabled, use `focal_point_scale_and_crop` effect instead of `image_scale_and_crop`. If not enabled, recommend `focal_point` in the report's Required Modules section.

3. **WebP conversion**: Add `image_convert` effect (target format: `webp`) as the LAST effect in every image style chain. Drupal 10.1+ supports this natively. Each style has 2 effects: (1) crop/scale, (2) convert to webp.

4. For contexts with 2+ breakpoint sizes, generate a `responsive_image.styles.{name}.yml`

5. Naming convention: `{context}_{breakpoint}` (e.g., `hero_xl`, `hero_md`, `card_md`, `avatar`)

### 3b: Breakpoints

If the theme needs custom breakpoints beyond Radix defaults, generate `{THEME_NAME}.breakpoints.yml`.

### 3c: Icon Pack (moved from former Part 5)

If the analysis found icons, generate a Drupal Icon API icon pack.

1. Run the extraction script:
   ```
   node "$DESIGN_SYSTEM_CONVERTER_DIR/scripts/extract-icons.js" extract {HTML_FILE} {THEME_DIR}/icons/
   ```
2. Verify SVG files in `{THEME_DIR}/icons/`
3. Generate `{THEME_NAME}.icons.yml` at theme root with svg extractor config

### 3d: LB Style Groups (moved from former Part 6)

Generate `layout_builder_styles.group.*.yml` and `layout_builder_styles.style.*.yml` configs. See `references/layout-builder-config.md` for templates.

### 3e: Base Element Styles

Generate `src/scss/base/_elements.scss` with `:root` custom properties, link styles, list styles from design tokens.

### Styleguide Foundation Includes

Generate in `templates/styleguide/includes/foundation/`:

- **`image-styles.html.twig`** -- visual thumbnail gallery of each image style: placeholder image at proportional size (max 200px wide) preserving actual aspect ratio. Each shown as a bordered card with image preview, caption (style name, dimensions, ratio, effect type), "WebP" badge, context label (e.g., "Hero banner", "Card thumbnail"). If focal_point enabled, show crosshair indicator on thumbnail center. Responsive image style groupings shown as a row of member styles with breakpoint annotations.
- **`breakpoints.html.twig`** -- responsive breakpoint visualization as colored bars at each width with border and caption
- **`icons.html.twig`** -- icon gallery grid showing all extracted icons with names, bordered cards with captions
- **`layout-styles.html.twig`** -- visual demo of each LB style: bg colors as soft swatches with borders, padding levels as nested boxes, container widths as proportional indicators with labels

---

## Part 4: Layout Wireframes

For each page in `pageLayouts`, generate a styleguide include at `templates/styleguide/includes/layouts/{page-name}.html.twig`.

Each wireframe renders the page sections as stacked blocks using soft transparent backgrounds:

```twig
{# Layout Wireframe: Home Page #}
<div class="test-section test-section--layout">
  <h3>Home Page Layout</h3>
  <div class="layout-wireframe">

    {# Section 1: Full width #}
    <div class="layout-section mb-2 p-3 rounded" style="background: rgba(var(--bs-primary-rgb), 0.1); border: 1px solid rgba(var(--bs-primary-rgb), 0.2);">
      <div class="d-flex align-items-center justify-content-between">
        <small class="text-muted fw-semibold">Section 1</small>
        <small class="text-muted">One Column | bg-primary | py-5</small>
      </div>
      <div class="mt-2 p-2 rounded" style="background: rgba(var(--bs-primary-rgb), 0.15);">
        <small class="text-muted">[hero]</small>
      </div>
    </div>

    {# Section 2: Two columns 67/33 #}
    <div class="layout-section mb-2 p-3 rounded" style="background: rgba(var(--bs-secondary-rgb), 0.1); border: 1px solid rgba(var(--bs-secondary-rgb), 0.2);">
      <div class="d-flex align-items-center justify-content-between">
        <small class="text-muted fw-semibold">Section 2</small>
        <small class="text-muted">Two Column (67/33) | bg-white | py-4</small>
      </div>
      <div class="row mt-2 g-2">
        <div class="col-8">
          <div class="p-2 rounded" style="background: rgba(var(--bs-secondary-rgb), 0.15);">
            <small class="text-muted">[blog-listing]</small>
          </div>
        </div>
        <div class="col-4">
          <div class="p-2 rounded" style="background: rgba(var(--bs-secondary-rgb), 0.15);">
            <small class="text-muted">[sidebar-cta]</small>
          </div>
        </div>
      </div>
    </div>

  </div>
</div>
```

### Visual rules:
- Each section gets a distinct soft transparent background (cycle through `primary-rgb`, `secondary-rgb`, `success-rgb`, `info-rgb` at 0.1 opacity)
- Light borders on all section and region boxes
- Captions on every element: section number + layout type in top-left, style properties in top-right
- Columns use Bootstrap grid with actual proportions (`col-8` + `col-4` for 67/33)
- Component labels inside regions as placeholders — initially just names, linked to component sections after Part 5

---

## Part 5: SDC Component Generation

Generate components in **design-system-first order**: process pages sequentially per `PAGE_ORDER`, and within each page, generate components sorted by atomic level (atoms first, then molecules, then organisms). This ensures dependencies are always available:
- Atoms reference only tokens (guaranteed from Part 2)
- Molecules can `include` atoms (generated earlier in the same page or a previous page)
- Organisms can `include` molecules (generated earlier)

**CRITICAL**: Read `references/drupal-best-practices.md` for mandatory SCSS variable discipline rules.

### Generation Loop

```
For each page in PAGE_ORDER:
  For each component on this page, sorted by atomic level (atoms → molecules → organisms):
    If component already generated by a previous page → skip
    Generate .component.yml, .twig, .scss
    Generate styleguide include
```

### Per-Component Generation

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

### Styleguide Component Includes

For each generated component, also generate `templates/styleguide/includes/{level}/{component-name}.html.twig`:

```twig
<div class="test-section test-section--{{ component_name }}">
  <h3>{{ component_label }} <span class="badge bg-info">{{ atomic_level }}</span></h3>
  <p class="text-muted">{{ description }}</p>

  {# Default variant #}
  <h5>Default</h5>
  <div class="border rounded p-3 mb-3" style="background: rgba(var(--bs-light-rgb), 0.5);">
    {% include '{THEME_NAME}:{component-name}' with {
      prop1: 'Sample value',
      prop2: 'Sample value',
    } %}
  </div>

  {# Props reference #}
  <div class="alert alert-info mt-3">
    <h6>Props</h6>
    <ul class="mb-0 small">
      <li><code>prop1</code> (string) — Description</li>
    </ul>
  </div>
</div>
```

Create representative prop values from:
- The component's analysis data (original HTML content provides real sample text)
- Default/placeholder values for images, links, etc.

---

## Part 6: Template Overrides

Generate Twig template overrides that map Drupal entity fields to SDC component props. Follow patterns from `references/template-matching-patterns.md`.

**CRITICAL entity access rules** (from `references/drupal-best-practices.md`):
- Block content templates: entity via `content['#block_content']` — assign `{% set block_entity = content['#block_content'] %}` at top
- Node templates: entity via `node`
- NEVER use `content.field_*['#items']` — always entity-level access
- ALL block content templates MUST embed `radix:block` — no exceptions

**Existing template handling**: When `SITE_INVENTORY` includes existing templates, do NOT generate templates for components where `existingTemplate: true`. Only generate NEW templates.

### Block Content Templates

For each component classified as `block_type` (skip if `existingTemplate: true`):

1. Create `templates/block/block--block-content--type--{name}.html.twig`
2. **ALWAYS** start with `{% set block_entity = content['#block_content'] %}`
3. **ALWAYS** embed `radix:block` as the outer wrapper
4. Inside the `{% block content %}`, include the custom SDC
5. Map fields using entity-level access: `block_entity.field_name.value` for scalars, `file_url(block_entity.field_image.entity.uri.value)` for images

### View Templates

For each component classified as `content_type_with_view` (skip if `existingTemplate: true`):

1. Create `templates/node/node--{type}--teaser.html.twig` for view row display
2. Map node fields using entity-level access: `node.field_name.value`, `file_url(node.field_image.entity.uri.value)`

### Navigation and Footer

1. Create `templates/block/block--system-menu-block--main.html.twig` if navbar component exists (skip if existing)
2. Create `templates/block/block--system-menu-block--footer.html.twig` if footer component exists (skip if existing)
3. Embed radix:navbar or custom SDC with menu render array as slot

---

## Part 7: Config Exports

Generate Drupal config YAML for backend entities identified by the analyzer. Config is split into two passes for safe import ordering.

**CRITICAL rules**:
- Field storage configs MUST include ALL keys: `module`, `dependencies`, `locked`, `translatable`, `indexes`, `persist_with_no_fields`, `custom_storage` (see `references/layout-builder-config.md` for complete template)
- `module` value by field type: `string`/`integer` → `core`, `text_long` → `text`, `image` → `image`, `link` → `link`, `list_string` → `options`
- NEVER generate config for existing field storages — only new ones (check `SITE_INVENTORY`)
- Only generate config for field types from enabled modules (check `SITE_INVENTORY.modules`)
- Generate ALL field storages and instances for ALL block types, not just the first one
- Do NOT default to Paragraphs for multi-value structured content — use multi-value fields on block types instead

### Pass 1: `config/converter-exports/pass1/`

Block types, field storages, LB styles, views — entities that other config depends on.

**Block types** (curated content):
- `block_content.type.{name}.yml` for each classified block type

**Field storages** (for ALL block types and content types):
- `field.storage.block_content.field_{prop_name}.yml` — with complete YAML (module, locked, translatable, etc.)
- `field.storage.node.field_{prop_name}.yml` — for content type fields
- Multi-value fields: `cardinality: -1`

**Content types** (repeating content):
- `node.type.{name}.yml`

**Views**:
- `views.view.{name}.yml` with block display for LB embedding

**LB Styles**:
- `layout_builder_styles.group.*.yml` for background, padding, container width
- `layout_builder_styles.style.*.yml` for each style option

**Image Styles** (from Part 3):
- `image.style.*.yml` for each new image style
- `responsive_image.styles.*.yml` for responsive image style groupings

### Pass 2: `config/converter-exports/pass2/`

Field instances — they reference storages from pass 1.

- `field.field.block_content.{block_type}.field_{prop_name}.yml`
- `field.field.node.{type}.field_{prop_name}.yml`

### Backend reuse:
- Do NOT generate config for components matching existing backend entities
- Do NOT generate field storage for fields that already exist in `SITE_INVENTORY`
- Record all reuse decisions in the report

See `references/layout-builder-config.md` for complete config templates and two-pass import instructions.

---

## Part 8: Conversion Report

Generate `conversion-report.md` at the root of the output directory.

### Required Sections

1. **Generated Files** -- table of every file with relative path and description
2. **Required Modules** -- Drupal modules needed (include `focal_point` recommendation if not already enabled)
3. **Token Mapping** -- every mapping decision from Part 2
4. **Components** -- table with component name, atomic level, SDC path (flat), Radix base, classification
5. **Template Overrides** -- table of template files with field-to-prop mapping
6. **Backend Reuse Summary** -- reuse/create_new actions per component
7. **Image Styles** -- table of generated image styles with context, dimensions, aspect ratio, effect type (focal_point or standard), WebP conversion, and responsive groupings. Note which are new vs reused from existing site.
8. **Layout Composition Instructions** -- see `references/layout-builder-config.md` for instruction format:
   - Prerequisites (config import, LB enable)
   - Section-by-section table (layout type, background, padding, block placements) -- sourced from `pageLayouts`
   - Navigation/footer (outside LB, in theme regions)
   - Post-setup checklist
9. **Styleguide Setup** -- instructions for visual verification:
   - Create a basic page node at `/styleguide` (empty body)
   - Rename `node--styleguide.html.twig` to `node--{nid}.html.twig` (matching the created node's ID)
   - Visit `/styleguide` to verify tokens, foundation, layouts, and components
10. **Manual Steps** -- actions the developer must perform after generation
11. **Warnings and Recommendations** -- issues, borderline mappings, accessibility concerns

### Master Styleguide Template

Generate `templates/styleguide/node--styleguide.html.twig` following the Palcera pattern: accordion-based ToC + accordion sections for each layer.

```twig
<style>
  .test-section { background-color: rgba(var(--bs-light-rgb), 0.3); border-radius: 8px; padding: 2rem; margin-bottom: 2rem; }
  .test-section h3 { border-bottom: 2px solid rgba(var(--bs-primary-rgb), 0.3); padding-bottom: 0.5rem; margin-bottom: 1.5rem; }
  .layout-wireframe .layout-section { min-height: 60px; }
  html { scroll-behavior: smooth; }
  section[id] { scroll-margin-top: 2rem; }
</style>

<div class="styleguide-wrapper">
  <div class="container-fluid py-5">
    <h1 class="display-4 mb-3">{{ THEME_LABEL }} Styleguide</h1>
    <p class="lead text-muted mb-5">Design system components generated from brand analysis.</p>

    {# Table of Contents - Accordion #}
    <div class="accordion mb-5" id="styleguideToC">...</div>

    {# Main Accordion #}
    <div class="accordion" id="mainStyleguide">
      {# Tokens Section: color-swatches, typography, spacing, interaction #}
      {# Foundation Section: image-styles, breakpoints, icons, layout-styles #}
      {# Layout Wireframes Section: one sub-section per page #}
      {# Atoms Section #}
      {# Molecules Section #}
      {# Organisms Section #}
    </div>
  </div>
</div>
```

Each accordion section includes all sub-template files for that layer via `{% include '@{THEME_NAME}/styleguide/includes/{category}/{name}.html.twig' %}`.

The template is named generically as `node--styleguide.html.twig`. The report instructs the user to create a basic page node and rename the template to `node--{nid}.html.twig`.

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
