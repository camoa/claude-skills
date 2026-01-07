# SDC Generation Patterns

## Contents
- SDC file structure
- Component YAML schema
- Twig template patterns
- CSS patterns
- Props and slots

## SDC File Structure

```
components/
└── component-name/
    ├── component-name.component.yml  # Required: metadata + schema
    ├── component-name.twig           # Required: template
    ├── component-name.css            # Optional: styles
    └── component-name.js             # Optional: behaviors
```

## Component YAML Schema

### Minimal Example
```yaml
name: Button
props:
  type: object
  properties:
    label:
      type: string
      title: Button Label
```

### Complete Example
```yaml
name: Hero Banner
status: stable
description: A hero banner with heading, subheading, and call-to-action.

props:
  type: object
  properties:
    heading:
      type: string
      title: Heading
      description: Main headline text
      examples:
        - 'Welcome to Our Site'
    subheading:
      type: string
      title: Subheading
      examples:
        - 'Discover amazing things'
    button_text:
      type: string
      title: Button Text
      default: 'Learn More'
    button_url:
      type: string
      format: uri
      title: Button URL
    variant:
      type: string
      title: Variant
      enum:
        - primary
        - secondary
        - dark
      default: primary
    image:
      type: object
      title: Background Image
      properties:
        src:
          type: string
          format: uri
        alt:
          type: string
  required:
    - heading

slots:
  content:
    title: Additional Content
    description: Optional content below the heading

libraryOverrides:
  css:
    component:
      css/component-name.css: {}
  js:
    component:
      js/component-name.js: {}
```

## Props Type Reference

| JSON Schema Type | Twig Usage | Example |
|------------------|------------|---------|
| `string` | `{{ prop }}` | Text, URLs |
| `boolean` | `{% if prop %}` | Toggles |
| `number` | `{{ prop }}` | Counts |
| `integer` | `{{ prop }}` | Whole numbers |
| `array` | `{% for item in prop %}` | Lists |
| `object` | `{{ prop.key }}` | Complex data |

### String Formats
```yaml
url_prop:
  type: string
  format: uri

email_prop:
  type: string
  format: email

date_prop:
  type: string
  format: date
```

### Enum (Select List)
```yaml
size:
  type: string
  enum:
    - small
    - medium
    - large
  default: medium
```

## Twig Template Patterns

### Basic Structure
```twig
{#
/**
 * @file
 * Component: Hero Banner
 */
#}
<div {{ attributes.addClass('hero-banner', 'hero-banner--' ~ variant) }}>
  {% if image.src %}
    <img src="{{ image.src }}" alt="{{ image.alt }}" class="hero-banner__image">
  {% endif %}

  <div class="hero-banner__content">
    <h1 class="hero-banner__heading">{{ heading }}</h1>

    {% if subheading %}
      <p class="hero-banner__subheading">{{ subheading }}</p>
    {% endif %}

    {% block content %}
      {{ content }}
    {% endblock %}

    {% if button_text and button_url %}
      <a href="{{ button_url }}" class="btn btn-{{ variant }}">
        {{ button_text }}
      </a>
    {% endif %}
  </div>
</div>
```

### Using Attributes
```twig
{# Add classes #}
{{ attributes.addClass('my-class') }}

{# Add with condition #}
{{ attributes.addClass(variant ? 'variant--' ~ variant : '') }}

{# Add data attributes #}
{{ attributes.setAttribute('data-component', 'hero') }}
```

### Slots
```twig
{# Named slot #}
{% block actions %}
  {{ actions }}
{% endblock %}

{# With default content #}
{% block footer %}
  {% if footer %}
    {{ footer }}
  {% else %}
    <p>Default footer content</p>
  {% endif %}
{% endblock %}
```

### Loops
```twig
{% if items %}
  <ul class="item-list">
    {% for item in items %}
      <li class="item-list__item">{{ item.title }}</li>
    {% endfor %}
  </ul>
{% endif %}
```

## CSS Patterns

### BEM Methodology
```css
/* Block */
.hero-banner {
  position: relative;
}

/* Element */
.hero-banner__heading {
  font-size: 2rem;
  font-weight: bold;
}

.hero-banner__content {
  padding: var(--spacing-4);
}

/* Modifier */
.hero-banner--primary {
  background-color: var(--color-primary);
}

.hero-banner--dark {
  background-color: var(--color-dark);
  color: white;
}
```

### Using Bootstrap Utilities
```css
/* Prefer Bootstrap utilities in Twig when possible */
/* Only add custom CSS when Bootstrap doesn't cover it */

.hero-banner {
  /* Custom only - Bootstrap doesn't have this */
  background: linear-gradient(135deg, var(--bs-primary), var(--bs-secondary));
}

/* Let Bootstrap handle common patterns in Twig:
   class="d-flex flex-column gap-3 p-4"
*/
```

### CSS Custom Properties
```css
.hero-banner {
  --hero-spacing: var(--spacing-4, 1rem);
  --hero-radius: var(--radius-lg, 0.5rem);

  padding: var(--hero-spacing);
  border-radius: var(--hero-radius);
}
```

## JavaScript Patterns

### Drupal Behaviors
```javascript
(function (Drupal) {
  Drupal.behaviors.heroBanner = {
    attach: function (context, settings) {
      const banners = once('hero-banner', '.hero-banner', context);

      banners.forEach(function (banner) {
        // Initialize component
        const button = banner.querySelector('.hero-banner__button');
        if (button) {
          button.addEventListener('click', handleClick);
        }
      });
    },
    detach: function (context, settings, trigger) {
      // Cleanup if needed
    }
  };

  function handleClick(event) {
    // Handle interaction
  }
})(Drupal);
```

## Common Component Patterns

### Card Component
```yaml
name: Card
props:
  type: object
  properties:
    title: { type: string }
    image:
      type: object
      properties:
        src: { type: string, format: uri }
        alt: { type: string }
    link: { type: string, format: uri }
slots:
  body:
    title: Card Body
```

### Button Component
```yaml
name: Button
props:
  type: object
  properties:
    label: { type: string }
    url: { type: string, format: uri }
    variant:
      type: string
      enum: [primary, secondary, outline]
      default: primary
    size:
      type: string
      enum: [sm, md, lg]
      default: md
  required: [label]
```

### List Component
```yaml
name: Item List
props:
  type: object
  properties:
    items:
      type: array
      items:
        type: object
        properties:
          title: { type: string }
          description: { type: string }
```
