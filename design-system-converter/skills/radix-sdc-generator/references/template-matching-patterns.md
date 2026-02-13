# Template-Matching Patterns

Twig template overrides that map Drupal entity fields to SDC component props. Use these patterns when generating the `templates/` directory of a Radix sub-theme. This is the primary strategy for connecting Drupal's data layer to SDC components while preserving the original HTML design's visual output.

## Contents

- Strategy Overview
- Template Suggestion Priority
- Block Content Templates
- Views Templates
- Content Type Templates
- Navigation and Footer Templates
- Field Access Patterns
- CSS Preservation Rules

## Strategy Overview

Template-matching maps entity fields to SDC component props via `include` or `embed` in Twig template overrides. Each template override:

1. Lives in the theme's `templates/` directory (NOT in the component directory).
2. Receives Drupal's render array variables (`content`, `label`, `attributes`).
3. Extracts field values and passes them as typed props to an SDC component.
4. Preserves the HTML structure the component was designed for -- the SDC's SCSS remains identical to the original design.

Use `include()` when passing props only. Use `embed` with `{% block %}` when the component has slots. Always set `with_context = false` on `include()` calls to prevent variable leaking.

## Template Suggestion Priority

Always generate the most specific template available. More specific suggestions win:

| Priority | Pattern | Example |
|---|---|---|
| Highest | `block--block-content--type--{type}` | `block--block-content--type--hero.html.twig` |
| | `node--{type}--{view-mode}` | `node--article--teaser.html.twig` |
| | `views-view--{view-name}` | `views-view--blog.html.twig` |
| | `block--system-menu-block--{menu}` | `block--system-menu-block--main.html.twig` |
| Lowest | `block--block-content` | `block--block-content.html.twig` |

Use `{{ kint() }}` or Twig debug mode (`twig.config.debug: true` in `services.yml`) to discover available suggestions.

## Block Content Templates

Path: `templates/block/block--block-content--type--{block-type-name}.html.twig`

### Hybrid Pattern (embed + include)

Wrap the SDC inside Radix's base block component. Use for most block types:

```twig
{#
/**
 * @file
 * Template for Hero block.
 */
#}
{% embed 'radix:block' with {
  provider: plugin_id|clean_class,
  label: label,
  content: TRUE,
} %}
  {% block content %}
    {{ include('{theme_name}:hero', {
      heading: content.field_heading|render|striptags|trim,
      body: content.field_body,
      image: file_url(content.field_image['#items'].entity.uri.value),
      image_alt: content.field_image['#items'].entity.alt,
      cta_url: content.field_link[0]['#url']|default(''),
      cta_text: content.field_link[0]['#title']|default(''),
      attributes: create_attribute(),
    }, with_context = false) }}
  {% endblock %}
{% endembed %}
```

### Props-Only Pattern

Use when no slots are needed and no Radix block chrome is wanted (e.g., full-width sections):

```twig
{{ include('{theme_name}:cta-banner', {
  heading: content.field_heading|render|striptags|trim,
  body: content.field_body,
  cta_url: content.field_link[0]['#url']|default(''),
  cta_text: content.field_link[0]['#title']|default(''),
  background_variant: content.field_variant['#items'].value|default('primary'),
  attributes: create_attribute(),
}, with_context = false) }}
```

### Slots Pattern

Use when the component has slots that receive rendered Drupal content:

```twig
{% embed '{theme_name}:feature-grid' with {
  heading: content.field_heading|render|striptags|trim,
  columns: content.field_columns['#items'].value|default(3),
  attributes: create_attribute(),
} only %}
  {% block items %}
    {{ content.field_features }}
  {% endblock %}
{% endembed %}
```

## Views Templates

### View Wrapper

Path: `templates/views/views-view--{view-name}.html.twig`

```twig
{% set classes = [
  'view',
  'view--' ~ id|clean_class,
  'view--display-' ~ display_id|clean_class,
] %}
<div{{ attributes.addClass(classes) }}>
  {% if header %}
    <div class="view__header mb-4">{{ header }}</div>
  {% endif %}
  {% if rows %}
    <div class="row g-4">{{ rows }}</div>
  {% endif %}
  {% if pager %}
    <div class="view__pager mt-5">{{ pager }}</div>
  {% endif %}
</div>
```

### View Row (Unformatted)

Path: `templates/views/views-view-unformatted--{view-name}.html.twig`

Wrap each row in a grid column so the view wrapper's `.row` produces a responsive grid:

```twig
{% for row in rows %}
  <div class="col-12 col-md-6 col-lg-4"{{ row.attributes }}>
    {{ row.content }}
  </div>
{% endfor %}
```

## Content Type Templates

### Teaser View Mode

Path: `templates/node/node--{type}--teaser.html.twig`

Map node fields to a card SDC. Used by Views when displaying nodes in a listing:

```twig
{{ include('{theme_name}:card', {
  heading: label|render|striptags|trim,
  body: content.field_summary|render|striptags|trim,
  image: file_url(content.field_image['#items'].entity.uri.value),
  image_alt: content.field_image['#items'].entity.alt,
  url: url,
  attributes: create_attribute(),
}, with_context = false) }}
```

### Full View Mode

Path: `templates/node/node--{type}--full.html.twig`

Use `embed` when the layout component has slots for rendered content:

```twig
{% embed '{theme_name}:article-layout' with {
  heading: label|render|striptags|trim,
  date: node.created.value|date('F j, Y'),
  image: file_url(content.field_image['#items'].entity.uri.value),
  image_alt: content.field_image['#items'].entity.alt,
  attributes: create_attribute(),
} only %}
  {% block body %}
    {{ content.body }}
  {% endblock %}
  {% block tags %}
    {{ content.field_tags }}
  {% endblock %}
{% endembed %}
```

## Navigation and Footer Templates

Navigation and footer map to theme regions, NOT Layout Builder sections. Generate template overrides for system menu blocks placed in those regions.

### Main Navigation

Path: `templates/block/block--system-menu-block--main.html.twig`

```twig
{% embed '{theme_name}:navbar' with {
  site_name: site_name|default(''),
  site_logo: site_logo|default(''),
  attributes: create_attribute(),
} only %}
  {% block menu %}
    {{ content }}
  {% endblock %}
{% endembed %}
```

Pass Drupal's rendered menu tree as a slot (`content`), not as individual link props. The navbar SDC handles responsive behavior (mobile toggle, dropdowns).

### Footer

Path: `templates/block/block--system-menu-block--footer.html.twig`

```twig
{% embed '{theme_name}:footer' with {
  copyright: '&copy; ' ~ 'now'|date('Y') ~ ' ' ~ site_name|default(''),
  attributes: create_attribute(),
} only %}
  {% block menu %}
    {{ content }}
  {% endblock %}
{% endembed %}
```

## Field Access Patterns

Extract field values from Drupal's render arrays. Match the pattern to the field type from config exports.

| Field Type | Access Pattern | Notes |
|---|---|---|
| Plain text (`string`) | `content.field_name\|render\|striptags\|trim` | Strip formatter HTML |
| Formatted text (`text_long`) | `content.field_body` | Keeps text format filter |
| Link URL | `content.field_link[0]['#url']` | First delta |
| Link title | `content.field_link[0]['#title']` | First delta |
| Image (rendered) | `content.field_image` | Full img tag |
| Image URL | `file_url(content.field_image['#items'].entity.uri.value)` | Raw URL for `src` props |
| Image alt | `content.field_image['#items'].entity.alt` | Accessibility text |
| Entity reference | `content.field_ref` | Renders in its view mode |
| Boolean | `content.field_toggle['#items'].value` | Raw 0 or 1 |
| List (select) | `content.field_variant['#items'].value` | Machine name |
| Multi-value (all) | `content.field_items` | All deltas rendered |
| Multi-value (loop) | `for item in node.field_items` | Custom per-item rendering |
| Date | `node.created.value\|date('F j, Y')` | Twig date filter |
| Node title | `label\|render\|striptags\|trim` | Special variable, not in `content` |
| Node URL | `url` | Canonical URL |

### Safe Defaults

Provide fallback values for optional fields to prevent Twig errors:

```twig
{{ content.field_link[0]['#url']|default('') }}
{{ content.field_link[0]['#title']|default('Learn more') }}
{{ content.field_variant['#items'].value|default('primary') }}
```

### Multi-Value Field Loop

Loop over entity fields to render each item as an SDC component:

```twig
{% for item in node.field_features %}
  {{ include('{theme_name}:feature-card', {
    heading: item.entity.field_heading.value,
    body: item.entity.field_body.value,
    icon_id: item.entity.field_icon.value|default(''),
    attributes: create_attribute(),
  }, with_context = false) }}
{% endfor %}
```

## CSS Preservation Rules

1. **Component SCSS stays identical.** Do not modify SDC styles to accommodate Drupal's data layer.

2. **Templates map data flow only.** Extract field values and pass as props. Do not add visual markup or CSS classes beyond what the SDC expects.

3. **Utility classes pass through.** Pass design-specific classes via the `*_utility_classes` prop:
   ```twig
   {{ include('{theme_name}:card', {
     heading: label|render|striptags|trim,
     card_utility_classes: ['shadow-lg', 'border-0'],
     attributes: create_attribute(),
   }, with_context = false) }}
   ```

4. **Responsive behavior lives in SCSS.** Templates do not add responsive wrappers or viewport-conditional markup.

5. **Bootstrap grid lives in templates.** Grid layout (`row`, `col-*`) belongs in template or view templates. Components are grid-agnostic.

## References

- `references/drupal-best-practices.md` -- SCSS variable discipline, SDC schema, component usage methods.
- `references/layout-builder-config.md` -- Section templates and `layout_builder_styles` config.
- External guides at `design-systems/radix-sdc/sdc-component-development/` -- Component `.yml`, `.twig`, and `.scss` patterns (discover via llms.txt).
