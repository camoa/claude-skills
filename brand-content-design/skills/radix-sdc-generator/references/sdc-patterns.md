# SDC Component Patterns

Templates and conventions for generating Single Directory Components (SDC) in a Radix sub-theme. Use these patterns when creating `component.yml`, `.twig`, and `.scss` files from analysis output.

## Contents

- component.yml Template
  - Required Props on Every Component
  - Prop Type Reference
- Example 1: Atom -- Button
- Example 2: Molecule -- Card
- Example 3: Organism -- Feature Grid
- Twig Template Patterns
  - Attribute Handling
  - Utility Classes Merge
  - Slot Rendering
  - Dual-Mode Content (Prop and Slot)
  - Conditional Wrapper
- SCSS Patterns
  - Import Convention
  - BEM Methodology
  - Use Bootstrap Variables and Mixins
- Radix-Specific Conventions
  - Bootstrap Classes in Twig
  - Extending a Radix Base Component
  - Component Library Discovery

## component.yml Template

Every SDC has a `component.yml` that declares its metadata, props (JSON Schema), and slots.

```yaml
$schema: https://git.drupalcode.org/project/drupal/-/raw/HEAD/core/assets/schemas/v1/metadata.schema.json
name: Component Name
status: experimental
group: Theme Name
description: 'Brief description of what this component renders.'
props:
  type: object
  properties:
    attributes:
      type: Drupal\Core\Template\Attribute
    {component_name}_utility_classes:
      type: array
      items:
        type: string
      default: []
    # Additional props from analysis...
slots:
  # Slots from analysis...
```

### Required Props on Every Component

1. **`attributes`** -- typed as `Drupal\Core\Template\Attribute`. Drupal passes HTML attributes (id, class, data-*) through this object. Always render it on the outermost element.

2. **`{component_name}_utility_classes`** -- array of strings. Allows editors and parent templates to inject Bootstrap utility classes without modifying the component. Merge into the outermost element's class list.

### Prop Type Reference

| Analysis Type | JSON Schema Type | Notes |
|---|---|---|
| string | `type: string` | Plain text value |
| text | `type: string` | Longer text, may contain HTML |
| url | `type: string, format: uri` | Link href |
| number | `type: number` | Numeric value |
| boolean | `type: boolean` | Toggle |
| image | `type: string, format: uri` | Image src URL |
| enum | `type: string, enum: [...]` | Fixed set of values |
| color | `type: string` | CSS color value |

## Example 1: Atom -- Button

### button.component.yml

```yaml
$schema: https://git.drupalcode.org/project/drupal/-/raw/HEAD/core/assets/schemas/v1/metadata.schema.json
name: Button
status: experimental
group: theme_name
description: 'Call-to-action button with brand styling and variant support.'
props:
  type: object
  properties:
    attributes:
      type: Drupal\Core\Template\Attribute
    button_utility_classes:
      type: array
      items:
        type: string
      default: []
    label:
      type: string
      title: Label
      description: 'Button text'
    url:
      type: string
      format: uri
      title: URL
      description: 'Link destination'
    variant:
      type: string
      title: Variant
      enum:
        - primary
        - secondary
        - outline
      default: primary
    size:
      type: string
      title: Size
      enum:
        - sm
        - md
        - lg
      default: md
  required:
    - label
```

### button.twig

```twig
{#
/**
 * @file
 * Button atom.
 *
 * Props:
 *   - label: Button text.
 *   - url: Link destination (renders <a> when provided, <button> otherwise).
 *   - variant: primary | secondary | outline.
 *   - size: sm | md | lg.
 *   - button_utility_classes: Additional CSS classes.
 *   - attributes: Drupal HTML attributes.
 */
#}

{% set variant_class = 'btn-' ~ (variant ?? 'primary') %}
{% if variant == 'outline' %}
  {% set variant_class = 'btn-outline-primary' %}
{% endif %}

{% set size_class = (size and size != 'md') ? 'btn-' ~ size : '' %}

{% set classes = [
  'btn',
  variant_class,
  size_class,
]|merge(button_utility_classes ?? [])
|filter(c => c is not empty) %}

{% if url %}
  <a{{ attributes.addClass(classes) }} href="{{ url }}" role="button">
    {{- label -}}
  </a>
{% else %}
  <button{{ attributes.addClass(classes) }} type="button">
    {{- label -}}
  </button>
{% endif %}
```

### button.scss

```scss
@import '../../../src/scss/init';

.btn {
  // Brand overrides applied via _variables.scss.
  // Only add custom styles that go beyond Bootstrap's .btn here.
  font-weight: 600;
  letter-spacing: 0.01em;
  transition: all var(--transition-duration, 0.2s) var(--transition-easing, ease);

  &:focus-visible {
    outline: var(--focus-ring-width, 2px) solid var(--focus-ring-color, rgba($primary, 0.5));
    outline-offset: 2px;
  }
}
```

## Example 2: Molecule -- Card

### card.component.yml

```yaml
$schema: https://git.drupalcode.org/project/drupal/-/raw/HEAD/core/assets/schemas/v1/metadata.schema.json
name: Card
status: experimental
group: theme_name
description: 'Content card with image, heading, body text, and optional CTA.'
props:
  type: object
  properties:
    attributes:
      type: Drupal\Core\Template\Attribute
    card_utility_classes:
      type: array
      items:
        type: string
      default: []
    image:
      type: string
      format: uri
      title: Image
      description: 'Card image URL'
    image_alt:
      type: string
      title: Image Alt
      description: 'Image alt text for accessibility'
    heading:
      type: string
      title: Heading
    body:
      type: string
      title: Body
      description: 'Card body text, may contain HTML'
  required:
    - heading
slots:
  card_footer:
    title: Card Footer
    description: 'Optional footer area, typically a CTA button or link'
```

### card.twig

```twig
{#
/**
 * @file
 * Card molecule.
 *
 * Extends Bootstrap card pattern with brand styling.
 *
 * Props:
 *   - image, image_alt: Card image.
 *   - heading: Card title.
 *   - body: Card text content.
 *   - card_utility_classes: Additional CSS classes.
 *   - attributes: Drupal HTML attributes.
 *
 * Slots:
 *   - card_footer: Footer area for CTA.
 */
#}

{% set classes = [
  'card',
  'card--brand',
  'h-100',
]|merge(card_utility_classes ?? []) %}

<div{{ attributes.addClass(classes) }}>
  {% if image %}
    <img src="{{ image }}" alt="{{ image_alt ?? '' }}" class="card-img-top" loading="lazy">
  {% endif %}

  <div class="card-body">
    {% if heading %}
      <h3 class="card-title h5">{{ heading }}</h3>
    {% endif %}

    {% if body %}
      <div class="card-text">{{ body }}</div>
    {% endif %}
  </div>

  {% block card_footer %}
    {% if card_footer is not empty %}
      <div class="card-footer bg-transparent border-0">
        {{ card_footer }}
      </div>
    {% endif %}
  {% endblock %}
</div>
```

### card.scss

```scss
@import '../../../src/scss/init';

.card--brand {
  border: 0;
  border-radius: $border-radius-lg;
  box-shadow: $box-shadow-sm;
  overflow: hidden;
  transition: transform var(--transition-duration, 0.2s) var(--transition-easing, ease),
              box-shadow var(--transition-duration, 0.2s) var(--transition-easing, ease);

  &:hover {
    transform: translateY(-2px);
    box-shadow: $box-shadow;
  }

  &__img-top {
    aspect-ratio: 16 / 9;
    object-fit: cover;
  }
}
```

## Example 3: Organism -- Feature Grid

### feature-grid.component.yml

```yaml
$schema: https://git.drupalcode.org/project/drupal/-/raw/HEAD/core/assets/schemas/v1/metadata.schema.json
name: Feature Grid
status: experimental
group: theme_name
description: 'Grid of feature cards with section heading. Used in Layout Builder sections.'
props:
  type: object
  properties:
    attributes:
      type: Drupal\Core\Template\Attribute
    feature_grid_utility_classes:
      type: array
      items:
        type: string
      default: []
    heading:
      type: string
      title: Section Heading
    subheading:
      type: string
      title: Section Subheading
    columns:
      type: integer
      title: Columns
      enum:
        - 2
        - 3
        - 4
      default: 3
slots:
  items:
    title: Feature Items
    description: 'Collection of card molecules or feature items'
```

### feature-grid.twig

```twig
{#
/**
 * @file
 * Feature grid organism.
 *
 * Renders a responsive grid of feature items within a page section.
 * Designed for placement in Layout Builder one-column sections.
 *
 * Props:
 *   - heading, subheading: Section header text.
 *   - columns: Grid column count (2, 3, or 4).
 *   - feature_grid_utility_classes: Additional CSS classes.
 *   - attributes: Drupal HTML attributes.
 *
 * Slots:
 *   - items: Collection of feature cards.
 */
#}

{% set col_class = 'col-md-' ~ (12 // (columns ?? 3)) %}

{% set classes = [
  'feature-grid',
]|merge(feature_grid_utility_classes ?? []) %}

<section{{ attributes.addClass(classes) }}>
  {% if heading or subheading %}
    <div class="feature-grid__header text-center mb-5">
      {% if heading %}
        <h2 class="feature-grid__heading">{{ heading }}</h2>
      {% endif %}
      {% if subheading %}
        <p class="feature-grid__subheading lead text-muted">{{ subheading }}</p>
      {% endif %}
    </div>
  {% endif %}

  <div class="row g-4">
    {% block items %}
      {% if items is not empty %}
        {% for item in items %}
          <div class="col-12 {{ col_class }}">
            {{ item }}
          </div>
        {% endfor %}
      {% endif %}
    {% endblock %}
  </div>
</section>
```

### feature-grid.scss

```scss
@import '../../../src/scss/init';

.feature-grid {
  &__header {
    max-width: 720px;
    margin-inline: auto;
  }

  &__heading {
    font-family: $font-family-heading;
    margin-bottom: $spacer;
  }

  &__subheading {
    font-size: $font-size-lg;
  }
}
```

## Twig Template Patterns

### Attribute Handling

Always render `attributes` on the outermost element:

```twig
{% set classes = ['component-name']|merge(component_name_utility_classes ?? []) %}
<div{{ attributes.addClass(classes) }}>
  {# content #}
</div>
```

### Utility Classes Merge

The `*_utility_classes` array prop allows injecting classes from the parent context. Merge it into the base class list:

```twig
{% set classes = [
  'base-class',
  'variant-' ~ (variant ?? 'default'),
]|merge(my_component_utility_classes ?? [])
|filter(c => c is not empty) %}
```

### Slot Rendering

Slots are rendered as Twig blocks. This allows both direct content injection and template-level overrides:

```twig
{% block slot_name %}
  {% if slot_name is not empty %}
    {{ slot_name }}
  {% endif %}
{% endblock %}
```

### Dual-Mode Content (Prop and Slot)

When a component accepts content as both a prop (simple string) and a slot (complex markup):

```twig
{% block content %}
  {% if content is not empty %}
    {{ content }}
  {% else %}
    {{ body_text }}
  {% endif %}
{% endblock %}
```

### Conditional Wrapper

Wrap optional elements only when the prop has a value:

```twig
{% if url %}
  <a href="{{ url }}" class="card-link">{{ label }}</a>
{% else %}
  <span class="card-label">{{ label }}</span>
{% endif %}
```

## SCSS Patterns

### Import Convention

Every component SCSS file imports `_init.scss` relative to its location in the components directory:

```scss
// Atom (components/atoms/button/)
@import '../../../src/scss/init';

// Molecule (components/molecules/card/)
@import '../../../src/scss/init';

// Organism (components/organisms/feature-grid/)
@import '../../../src/scss/init';
```

The import depth is the same for all levels because atoms, molecules, and organisms are all one directory deep under `components/`.

### BEM Methodology

Use Block-Element-Modifier naming:

```scss
.component-name {
  // Block styles

  &__element {
    // Element styles
  }

  &__element--modifier {
    // Modifier styles
  }

  &--variant {
    // Block variant
  }
}
```

### Use Bootstrap Variables and Mixins

Reference Bootstrap SCSS variables (which include brand overrides from `_variables.scss`) and mixins instead of hardcoding values:

```scss
.component-name {
  padding: $spacer * 2;
  border-radius: $border-radius-lg;
  color: $body-color;
  background-color: $gray-100;

  @include media-breakpoint-up(md) {
    padding: $spacer * 3;
  }
}
```

## Radix-Specific Conventions

### Bootstrap Classes in Twig

Use Bootstrap utility classes directly in Twig templates for layout and spacing. Reserve component SCSS for brand-specific styling only:

```twig
<div class="d-flex align-items-center gap-3 mb-4">
  <div class="flex-shrink-0">{{ icon }}</div>
  <div class="flex-grow-1">{{ content }}</div>
</div>
```

### Extending a Radix Base Component

When the analysis identifies a Radix base component to extend:

1. The sub-theme component keeps the same `component.yml` prop schema.
2. Override the `.twig` template to apply brand markup.
3. Override the `.scss` to apply brand styles.
4. Drupal's SDC discovery automatically uses the sub-theme version.

When the analysis finds no Radix match, create a new component from scratch following the patterns above.

### Component Library Discovery

SDC components are discovered automatically by Drupal when placed in `components/`. No manual registration is required. The `component.yml` file is the discovery mechanism. Verify:

- `component.yml` has a valid `$schema` reference.
- Component directory name matches the component machine name.
- `group` value matches the theme machine name.
- `status` is set (`experimental`, `stable`, or `deprecated`).
