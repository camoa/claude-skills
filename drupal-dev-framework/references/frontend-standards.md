# Frontend Standards for Drupal

Frontend patterns enforced during implementation.

## Quick Reference

| Area | Standard | Tool |
|------|----------|------|
| CSS | BEM naming, no `!important` | Stylelint |
| JS | ES6+, behaviors pattern | ESLint |
| Components | SDC (Single Directory Components) | Drupal core |
| Accessibility | WCAG 2.1 AA minimum | axe-core |

## CSS Standards

### BEM Naming Convention

```css
/* Block */
.card {}

/* Element (part of block) */
.card__title {}
.card__body {}
.card__footer {}

/* Modifier (variation) */
.card--featured {}
.card--compact {}
```

### Mobile-First Approach

```scss
// Start with mobile styles
.component {
  padding: 1rem;

  // Then add breakpoints for larger screens
  @include media-breakpoint-up(md) {
    padding: 2rem;
  }

  @include media-breakpoint-up(lg) {
    padding: 3rem;
  }
}
```

### Forbidden Patterns

| Pattern | Why | Alternative |
|---------|-----|-------------|
| `!important` | Breaks cascade | Increase specificity properly |
| `@extend` | Bloats CSS, unpredictable | Use mixins or utility classes |
| ID selectors | Too specific | Use classes |
| Deep nesting (>3 levels) | Hard to maintain | Flatten with BEM |

### Checklist

- [ ] BEM naming used consistently
- [ ] Mobile-first breakpoints
- [ ] No `!important` declarations
- [ ] No `@extend` usage
- [ ] Nesting depth ≤ 3 levels
- [ ] Partials prefixed with `_`

## JavaScript Standards

### Drupal Behaviors Pattern

```javascript
(function ($, Drupal, once) {
  'use strict';

  Drupal.behaviors.myModuleBehavior = {
    attach: function (context, settings) {
      once('my-behavior', '.my-element', context).forEach(function (element) {
        // Initialize your component
        element.addEventListener('click', handleClick);
      });
    },
    detach: function (context, settings, trigger) {
      // Cleanup when elements are removed
      if (trigger === 'unload') {
        // Remove event listeners, etc.
      }
    }
  };

  function handleClick(event) {
    // Handle the click
  }

})(jQuery, Drupal, once);
```

### Key Patterns

| Pattern | Use For |
|---------|---------|
| `once()` | Prevent re-initialization |
| `attach()` | Initialize on page load and AJAX |
| `detach()` | Cleanup when DOM changes |
| `Drupal.t()` | Translatable strings |

### Forbidden Patterns

| Pattern | Why | Alternative |
|---------|-----|-------------|
| Global variables | Pollution | Use Drupal.behaviors namespace |
| Inline `onclick` | Unmaintainable | Event listeners |
| `document.write()` | Dangerous | DOM manipulation |
| jQuery without once | Re-initialization bugs | Always use `once()` |

### Checklist

- [ ] Uses Drupal behaviors pattern
- [ ] `once()` prevents double-initialization
- [ ] Event listeners properly attached/detached
- [ ] No global variable pollution
- [ ] Translatable strings use `Drupal.t()`

## Component Architecture

### Single Directory Components (SDC)

Structure:
```
components/
  my-card/
    my-card.component.yml    # Metadata
    my-card.twig             # Template
    my-card.css              # Styles
    my-card.js               # Behavior (optional)
    README.md                # Documentation (optional)
```

### Component YML

```yaml
name: My Card
status: stable
props:
  type: object
  properties:
    title:
      type: string
      title: Card Title
    image:
      type: object
      title: Card Image
    link:
      type: object
      title: Card Link
  required:
    - title
slots:
  content:
    title: Card Content
```

### Component Usage

```twig
{{ include('my_theme:my-card', {
  title: node.label,
  image: node.field_image,
  link: { url: node.toUrl, title: 'Read more' },
}) }}
```

### Checklist

- [ ] Component has single responsibility
- [ ] Props clearly defined in YAML
- [ ] Slots used for variable content
- [ ] CSS scoped to component
- [ ] JS uses behaviors pattern

## Accessibility

### Minimum Requirements (WCAG 2.1 AA)

| Requirement | Check |
|-------------|-------|
| Color contrast | 4.5:1 for text, 3:1 for large text |
| Keyboard navigation | All interactive elements focusable |
| Screen readers | Meaningful alt text, ARIA labels |
| Focus visibility | Clear focus indicators |

### Common Patterns

```html
<!-- Skip link -->
<a href="#main-content" class="visually-hidden focusable">
  Skip to main content
</a>

<!-- Icon buttons need labels -->
<button aria-label="Close menu">
  <span class="icon icon--close"></span>
</button>

<!-- Form labels -->
<label for="email">Email address</label>
<input type="email" id="email" name="email" required>

<!-- Error messages linked -->
<input aria-describedby="email-error" aria-invalid="true">
<div id="email-error" role="alert">Please enter a valid email</div>
```

### Checklist

- [ ] All images have appropriate alt text
- [ ] Form fields have labels
- [ ] Color is not only indicator
- [ ] Keyboard navigation works
- [ ] Focus states visible
- [ ] Error messages accessible

## Asset Libraries

### Defining Libraries

```yaml
# my_module.libraries.yml
my-component:
  version: 1.x
  css:
    component:
      css/my-component.css: {}
  js:
    js/my-component.js: {}
  dependencies:
    - core/drupal
    - core/once
```

### Attaching Libraries

```twig
{# In Twig #}
{{ attach_library('my_module/my-component') }}
```

```php
// In preprocess
$variables['#attached']['library'][] = 'my_module/my-component';
```

### Checklist

- [ ] Libraries defined for component assets
- [ ] Dependencies declared (core/drupal, core/once, etc.)
- [ ] Libraries attached where needed
- [ ] No inline styles/scripts

## Implementation Checklist

Before `/complete`:

```markdown
## Frontend Verification

### CSS
- [ ] BEM naming throughout
- [ ] Mobile-first approach
- [ ] No !important
- [ ] No @extend

### JavaScript
- [ ] Behaviors pattern used
- [ ] once() prevents re-init
- [ ] Proper attach/detach

### Components
- [ ] SDC structure if applicable
- [ ] Props documented
- [ ] Single responsibility

### Accessibility
- [ ] Alt text on images
- [ ] Form labels present
- [ ] Keyboard navigable
- [ ] Focus states visible

### Assets
- [ ] Libraries properly defined
- [ ] Dependencies declared
```
