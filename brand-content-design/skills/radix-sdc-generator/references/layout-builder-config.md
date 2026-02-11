# Layout Builder Configuration

Configuration patterns for Layout Builder styles, section template overrides, and page composition. Use these patterns during Part 4 and Part 6 of the generator.

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

For custom brand colors (e.g., `$accent`, `$bg-alt`), add matching styles:

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

### Mapping Rules

Apply these rules to convert the HTML page structure into Layout Builder sections:

1. **Each component block maps to a Layout Builder section.** A `<!-- component: hero -->` becomes a one-column section containing the hero SDC block.

2. **Adjacent related components may share a section.** If two components visually belong to the same page area (e.g., a section heading directly above a feature grid), they can be placed in the same LB section.

3. **Full-bleed backgrounds become section styles.** When the HTML shows a section with a colored background spanning the full viewport width, apply a `layout_builder_styles` background class to the LB section's outer div.

4. **Navigation and footer live outside Layout Builder.** These are placed in theme regions (`navbar_main`, `footer`) via block placement config, not in LB sections.

5. **Section ordering follows HTML document order.** Top-to-bottom in the HTML becomes top-to-bottom in the LB layout.

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
# config/converter-exports/block_content.type.{name}.yml
langcode: en
status: true
id: {name}
label: '{Label}'
description: 'Generated from HTML component: {component_name}'
revision: 1
```

### Field Storage Config

```yaml
# config/converter-exports/field.storage.block_content.field_{field_name}.yml
langcode: en
status: true
id: block_content.field_{field_name}
field_name: field_{field_name}
entity_type: block_content
type: string
cardinality: 1
settings:
  max_length: 255
```

### Field Instance Config

```yaml
# config/converter-exports/field.field.block_content.{block_type}.field_{field_name}.yml
langcode: en
status: true
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
# config/converter-exports/views.view.{name}.yml
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
