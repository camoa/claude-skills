# Layout Builder Configuration

Configuration patterns for Layout Builder styles, section template overrides, and page composition. Use these patterns during Part 3 (Foundation), Part 4 (Layout Wireframes), and Part 7 (Config Exports) of the generator.

## Contents

- layout_builder_styles Module Configuration
  - Style Group Configuration
  - Background Color Styles
  - Padding Styles
  - Container Width Styles
- Section Template Overrides
  - Nested Container Pattern
- Section-to-Page Mapping
  - Mapping Rules
  - Mapping Output Format
- Config Export Format
  - Block Type Config
  - Field Storage Config
  - Field Instance Config
  - Views Config

## layout_builder_styles Module Configuration

The `layout_builder_styles` module adds CSS class selection to Layout Builder sections and blocks. Generate config entities that map design tokens to selectable style options.

### Style Group Configuration

```yaml
# config/converter-exports/layout_builder_styles.group.background_color.yml
langcode: en
status: true
id: background_color
label: 'Background Color'
weight: 0
multiselect: single
form_type: checkboxes
```

```yaml
# config/converter-exports/layout_builder_styles.group.padding.yml
langcode: en
status: true
id: padding
label: 'Padding'
weight: 1
multiselect: single
form_type: checkboxes
```

```yaml
# config/converter-exports/layout_builder_styles.group.container_width.yml
langcode: en
status: true
id: container_width
label: 'Container Width'
weight: 2
multiselect: single
form_type: checkboxes
```

### Background Color Styles

Generate one style config per brand color token:

```yaml
# config/converter-exports/layout_builder_styles.style.bg_primary.yml
langcode: en
status: true
id: bg_primary
label: 'Primary Background'
classes: 'bg-primary text-white'
group: background_color
weight: 0
```

```yaml
# config/converter-exports/layout_builder_styles.style.bg_secondary.yml
langcode: en
status: true
id: bg_secondary
label: 'Secondary Background'
classes: 'bg-secondary text-white'
group: background_color
weight: 1
```

```yaml
# config/converter-exports/layout_builder_styles.style.bg_light.yml
langcode: en
status: true
id: bg_light
label: 'Light Background'
classes: 'bg-light'
group: background_color
weight: 2
```

```yaml
# config/converter-exports/layout_builder_styles.style.bg_dark.yml
langcode: en
status: true
id: bg_dark
label: 'Dark Background'
classes: 'bg-dark text-white'
group: background_color
weight: 3
```

```yaml
# config/converter-exports/layout_builder_styles.style.bg_white.yml
langcode: en
status: true
id: bg_white
label: 'White Background'
classes: 'bg-white'
group: background_color
weight: 4
```

For custom brand colors, add matching styles. **Important**: Custom color keys in `$custom-colors` must NOT include the Bootstrap utility prefix. Use `"alt"` not `"bg-alt"` — Bootstrap generates utility classes like `bg-{key}`, so `bg-alt` produces `bg-bg-alt` which is incorrect.

```yaml
# config/converter-exports/layout_builder_styles.style.bg_accent.yml
langcode: en
status: true
id: bg_accent
label: 'Accent Background'
classes: 'bg-accent text-white'
group: background_color
weight: 5
```

### Padding Styles

Map spacing tokens to padding classes:

```yaml
# config/converter-exports/layout_builder_styles.style.py_sm.yml
langcode: en
status: true
id: py_sm
label: 'Small Padding'
classes: 'py-3'
group: padding
weight: 0
```

```yaml
# config/converter-exports/layout_builder_styles.style.py_md.yml
langcode: en
status: true
id: py_md
label: 'Medium Padding'
classes: 'py-5'
group: padding
weight: 1
```

```yaml
# config/converter-exports/layout_builder_styles.style.py_lg.yml
langcode: en
status: true
id: py_lg
label: 'Large Padding'
classes: 'py-6'
group: padding
weight: 2
```

```yaml
# config/converter-exports/layout_builder_styles.style.py_none.yml
langcode: en
status: true
id: py_none
label: 'No Padding'
classes: 'py-0'
group: padding
weight: 3
```

### Container Width Styles

```yaml
# config/converter-exports/layout_builder_styles.style.container_full.yml
langcode: en
status: true
id: container_full
label: 'Full Width'
classes: 'container-fluid px-0'
group: container_width
weight: 0
```

```yaml
# config/converter-exports/layout_builder_styles.style.container_default.yml
langcode: en
status: true
id: container_default
label: 'Default Width'
classes: 'container'
group: container_width
weight: 1
```

```yaml
# config/converter-exports/layout_builder_styles.style.container_narrow.yml
langcode: en
status: true
id: container_narrow
label: 'Narrow Width'
classes: 'container' style='max-width: 800px'
group: container_width
weight: 2
```

## Section Template Overrides

### Nested Container Pattern

The core principle: outer div receives full viewport width for background colors and images. Inner `.container` constrains the content to the site max-width.

**One column:**

```twig
{# templates/layout/layout--onecol.html.twig #}
{% set container_classes = ['layout', 'layout--onecol'] %}

<div{{ attributes.addClass(container_classes) }}>
  <div class="container">
    <div{{ content_attributes.addClass('layout__content') }}>
      {{ content.content }}
    </div>
  </div>
</div>
```

**Two column:**

```twig
{# templates/layout/layout--twocol-section.html.twig #}
{% set container_classes = ['layout', 'layout--twocol-section'] %}

<div{{ attributes.addClass(container_classes) }}>
  <div class="container">
    <div class="row">
      <div{{ region_attributes.first.addClass('layout__region', 'layout__region--first', 'col-12', 'col-md-6') }}>
        {{ content.first }}
      </div>
      <div{{ region_attributes.second.addClass('layout__region', 'layout__region--second', 'col-12', 'col-md-6') }}>
        {{ content.second }}
      </div>
    </div>
  </div>
</div>
```

**Three column:**

```twig
{# templates/layout/layout--threecol-section.html.twig #}
{% set container_classes = ['layout', 'layout--threecol-section'] %}

<div{{ attributes.addClass(container_classes) }}>
  <div class="container">
    <div class="row">
      <div{{ region_attributes.first.addClass('layout__region', 'layout__region--first', 'col-12', 'col-md-4') }}>
        {{ content.first }}
      </div>
      <div{{ region_attributes.second.addClass('layout__region', 'layout__region--second', 'col-12', 'col-md-4') }}>
        {{ content.second }}
      </div>
      <div{{ region_attributes.third.addClass('layout__region', 'layout__region--third', 'col-12', 'col-md-4') }}>
        {{ content.third }}
      </div>
    </div>
  </div>
</div>
```

## Section-to-Page Mapping

### Data Source

The mapping now consumes `pageLayouts` from the analyzer output instead of inferring layout from component order. Each section in `pageLayouts.sections[]` provides accurate layout type, column proportions, visual properties, and component placement.

### Mapping Rules

Apply these rules to convert `pageLayouts` into Layout Builder sections:

1. **`pageLayouts.sections[].layout` determines the LB section type:**
   - `onecol` → `layout_onecol`
   - `twocol` → `layout_twocol_section`
   - `threecol` → `layout_threecol_section`
   - `grid` → `layout_onecol` (grid is rendered by the component, not the section)

2. **`pageLayouts.sections[].proportions` determine LB column widths:**
   - `[67, 33]` → twocol with 67/33 split
   - `[50, 50]` → twocol equal
   - `[33, 33, 33]` → threecol equal

3. **`pageLayouts.sections[].classes` map to LB styles:**
   - `bg-*` classes → background color style (e.g., `bg_primary`)
   - `py-*` classes → padding style (e.g., `py_md`, `py_lg`)
   - `container-fluid` → container width style (`container_full`)

4. **`pageLayouts.sections[].regions[].components` determine block placements** per LB region (content, first, second, third).

5. **Navigation and footer live outside Layout Builder.** These are placed in theme regions (`navbar_main`, `footer`) via block placement config, not in LB sections.

6. **Section ordering follows `pageLayouts.sections[].order`** — top-to-bottom.

### Mapping Output Format

Record section-to-LB mapping in the output config:

```yaml
pageLayout:
  - section: 1
    layout: layout_onecol
    styles:
      - bg_primary
      - py_lg
    blocks:
      - component: hero
        region: content
        block_type: block_content:hero

  - section: 2
    layout: layout_onecol
    styles:
      - py_md
    blocks:
      - component: features
        region: content
        block_type: block_content:features

  - section: 3
    layout: layout_twocol_section
    styles:
      - bg_light
      - py_md
    blocks:
      - component: about_image
        region: first
        block_type: block_content:about
      - component: about_text
        region: second
        block_type: block_content:about

  - section: 4
    layout: layout_onecol
    styles:
      - py_lg
    blocks:
      - component: blog_listing
        region: content
        block_type: views_block:blog_listing
```

## Config Export Format

### Block Type Config

```yaml
# config/converter-exports/pass1/block_content.type.{name}.yml
langcode: en
status: true
id: {name}
label: '{Label}'
description: 'Generated from HTML component: {component_name}'
revision: 1
```

### Field Storage Config

**CRITICAL**: Field storage configs MUST include ALL keys shown below. Omitting keys like `module`, `locked`, `translatable`, `indexes`, `persist_with_no_fields`, or `custom_storage` will corrupt existing field storages when imported via `drush config:import --partial`, causing site-breaking 500 errors.

```yaml
# config/converter-exports/pass1/field.storage.block_content.field_{field_name}.yml
langcode: en
status: true
dependencies:
  module:
    - block_content
id: block_content.field_{field_name}
field_name: field_{field_name}
entity_type: block_content
type: string
module: core
locked: false
cardinality: 1
translatable: true
indexes: {}
persist_with_no_fields: false
custom_storage: false
settings:
  max_length: 255
```

**Module values by field type:**

| Field Type | `module` Value | `settings` |
|---|---|---|
| `string` | `core` | `{ max_length: 255 }` |
| `integer` | `core` | `{ unsigned: false, size: normal }` |
| `text_long` | `text` | `{}` |
| `image` | `image` | `{ uri_scheme: public, default_image: { uuid: null, alt: '', title: '', width: null, height: null } }` |
| `link` | `link` | `{}` |
| `list_string` | `options` | `{ allowed_values: [], allowed_values_function: '' }` |
| `boolean` | `core` | `{ on_label: 'On', off_label: 'Off' }` |
| `entity_reference` | `core` | `{ target_type: node }` |

**NEVER generate field storage config for fields that already exist** in the site's config sync directory. Only generate config for NEW fields.

### Field Instance Config

```yaml
# config/converter-exports/pass2/field.field.block_content.{block_type}.field_{field_name}.yml
langcode: en
status: true
dependencies:
  config:
    - block_content.type.{block_type}
    - field.storage.block_content.field_{field_name}
id: block_content.{block_type}.field_{field_name}
field_name: field_{field_name}
entity_type: block_content
bundle: {block_type}
label: '{Field Label}'
required: false
settings: {}
field_type: string
```

### Views Config

```yaml
# config/converter-exports/pass1/views.view.{name}.yml
langcode: en
status: true
id: {name}
label: '{Label}'
module: views
description: 'Generated listing for {content_type}'
tag: ''
base_table: node_field_data
display:
  default:
    id: default
    display_title: Default
    display_plugin: default
    position: 0
    display_options:
      title: '{Label}'
      pager:
        type: some
        options:
          items_per_page: 12
      row:
        type: 'entity:node'
        options:
          view_mode: teaser
      sorts:
        created:
          id: created
          table: node_field_data
          field: created
          order: DESC
          plugin_id: date
      filters:
        type:
          id: type
          table: node_field_data
          field: type
          value:
            {content_type}: {content_type}
          plugin_id: bundle
        status:
          id: status
          table: node_field_data
          field: status
          value: '1'
          plugin_id: boolean
  block_1:
    id: block_1
    display_title: Block
    display_plugin: block
    position: 1
```

### Image Style Config

Generate image styles based on `imageContexts` from the analysis output. Each unique aspect ratio × size combination gets its own image style. Every style uses a two-effect chain: crop/scale + WebP conversion.

**Focal point support**: Check if `focal_point` module is in `SITE_INVENTORY.modules`. If enabled, use `focal_point_scale_and_crop` effect instead of `image_scale_and_crop` — this lets editors set the crop center point per image. If not enabled, use `image_scale_and_crop` and recommend `focal_point` in the report's Required Modules section.

**WebP conversion**: Add `image_convert` effect with `extension: webp` as the LAST effect in every image style chain. Drupal 10.1+ supports this natively.

```yaml
# config/converter-exports/pass1/image.style.{name}.yml
langcode: en
status: true
dependencies: {}
name: {name}
label: '{Label}'
effects:
  {uuid_1}:
    uuid: {uuid_1}
    id: focal_point_scale_and_crop   # or image_scale_and_crop if focal_point not available
    weight: 1
    data:
      width: {width}
      height: {height}
  {uuid_2}:
    uuid: {uuid_2}
    id: image_convert
    weight: 2
    data:
      extension: webp
```

**Effect types by context:**

| Image Context | Crop Effect | Notes |
|---|---|---|
| `hero`, `banner` | `focal_point_scale_and_crop` / `image_scale_and_crop` | Fixed ratio, full-width, always crop to exact dimensions |
| `card_thumbnail` | `focal_point_scale_and_crop` / `image_scale_and_crop` | Fixed ratio, crop to card proportions |
| `avatar` | `focal_point_scale_and_crop` / `image_scale_and_crop` | Square crop (1:1) |
| `gallery` | `focal_point_scale_and_crop` / `image_scale_and_crop` | Uniform sizing for grid display |
| `inline` | `image_scale` | Scale down only, preserve original ratio |

All contexts also get `image_convert` (webp) as the second effect.

**Naming convention:** `{context}_{breakpoint}` (e.g., `hero_xl`, `hero_md`, `hero_sm`, `card_md`, `avatar`)

### Responsive Image Style Config

Group related image styles into responsive image styles with breakpoint mappings.

```yaml
# config/converter-exports/pass1/responsive_image.styles.{name}.yml
langcode: en
status: true
dependencies:
  config:
    - image.style.{style_xl}
    - image.style.{style_md}
    - image.style.{style_sm}
id: {name}
label: '{Label}'
image_style_mappings:
  - image_mapping_type: sizes
    breakpoint_id: responsive_image.viewport_sizing
    multiplier: '1x'
    sizes: '(min-width: 1200px) 1140px, (min-width: 768px) 720px, 100vw'
    sizes_image_styles:
      {style_xl}: {style_xl}
      {style_md}: {style_md}
      {style_sm}: {style_sm}
fallback_image_style: {style_md}
breakpoint_group: responsive_image
```

**When to generate responsive image styles:**
- When an image context has 2+ breakpoint sizes → create a responsive style grouping them
- When only 1 size → a single image style is sufficient, no responsive style needed
- On existing sites: check `SITE_INVENTORY.responsive_image_styles` before generating duplicates

**NEVER generate image styles that already exist.** Compare against `SITE_INVENTORY.image_styles` by ratio and size (within 50px tolerance).

---

## Layout Composition Instructions

Instead of generating entity view display YAML (fragile: UUIDs, style enumeration, deeply nested config), generate human-readable instructions in the conversion report. Config YAML is still generated for block types, fields, views, LB style groups, and LB styles.

### Instruction Format

Include a "Layout Composition Instructions" section in the conversion report with these sub-sections:

#### Prerequisites

Config exports are split into two passes to prevent import ordering errors (field instances reference field storages, so storages must exist first):

```markdown
### Prerequisites

1. Import pass 1 (block types, field storages, LB styles):
   `drush config:import --partial --source=config/converter-exports/pass1/`
2. Import pass 2 (field instances that reference pass 1 storages):
   `drush config:import --partial --source=config/converter-exports/pass2/`
3. Enable Layout Builder on the target content type (e.g., Basic page)
4. Set the theme as default: `drush config:set system.theme default {THEME_NAME}`
5. Clear cache: `drush cr`
```

**pass1/** contains: `block_content.type.*.yml`, `field.storage.*.yml`, `layout_builder_styles.*.yml`, `views.view.*.yml`, `image.style.*.yml`, `responsive_image.styles.*.yml`
**pass2/** contains: `field.field.*.yml`

#### Section-by-Section Table

For each page section, provide a table row:

```markdown
### Page Layout: {page_name}

| Section | Layout | Background | Padding | Block | Region |
|---------|--------|------------|---------|-------|--------|
| 1 | One column | Primary (bg-primary) | Large (py-6) | Hero block | Content |
| 2 | One column | White | Medium (py-5) | Features block | Content |
| 3 | Two column | Light (bg-light) | Medium (py-5) | About image / About text | First / Second |
| 4 | One column | White | Large (py-6) | Blog listing (view block) | Content |
| 5 | One column | Dark (bg-dark) | Medium (py-5) | CTA block | Content |
```

#### Navigation and Footer (Outside LB)

```markdown
### Theme Region Blocks

These blocks are placed in theme regions, NOT in Layout Builder sections:

| Block | Region | Notes |
|-------|--------|-------|
| Navbar component | navbar_branding + navbar_left | Main navigation menu |
| Footer component | footer | Footer menu + copyright |
```

#### Post-Setup Checklist

```markdown
### Post-Setup Checklist

- [ ] Verify each section has correct background color applied via LB Styles
- [ ] Verify padding levels match the design
- [ ] Test responsive behavior at mobile, tablet, desktop breakpoints
- [ ] Verify navigation menu links are correct
- [ ] Check footer content and links
- [ ] Run Lighthouse accessibility audit
```
