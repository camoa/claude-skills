# Bootstrap Accommodation Framework

## Contents
- The 6px threshold rule
- Decision categories
- Research methodology
- SCSS best practices

## The 6px Threshold Rule

When comparing Figma design values to Bootstrap defaults:

| Difference | Decision | Action |
|------------|----------|--------|
| < 6px | **ACCOMMODATE** | Use Bootstrap as-is |
| >= 6px | **Evaluate** | EXTEND, CUSTOMIZE, or CREATE |

This applies to: spacing, font sizes, border radius, margins, padding.

## Decision Categories

### ACCOMMODATE
Use Bootstrap exactly as it exists.

```scss
// Figma: padding 15px, Bootstrap: p-3 (16px)
// Difference: 1px < 6px → ACCOMMODATE
.component {
  // Use Bootstrap utility: class="p-3"
  // Or variable: padding: $spacer;
}
```

### EXTEND
Add to Bootstrap without changing defaults.

```scss
// Figma: spacing 28px, Bootstrap max: 48px (3rem)
// Need new spacing value
$spacers: map-merge($spacers, (
  "7": 1.75rem,  // 28px
));
```

### CUSTOMIZE
Modify Bootstrap's default values.

```scss
// Figma: base font 18px, Bootstrap: 16px
// Difference: 2px < 6px but design-wide change
$font-size-base: 1.125rem;  // 18px
```

### CREATE
Build from scratch when Bootstrap doesn't cover it.

```scss
// Figma: complex gradient not in Bootstrap
.hero-gradient {
  background: linear-gradient(
    135deg,
    var(--bs-primary) 0%,
    var(--bs-secondary) 100%
  );
}
```

## Research Methodology

Before writing custom CSS, always check Bootstrap first:

### 1. Check Spacing Scale
```scss
// Bootstrap spacing: 0, 0.25rem, 0.5rem, 1rem, 1.5rem, 3rem
// Figma value: 24px (1.5rem)
// Match found: use $spacer-4 or class="p-4"
```

### 2. Check Typography Scale
```scss
// Bootstrap: 1rem, 1.25rem, 1.5rem, 1.75rem, 2rem, 2.5rem
// Figma: 28px (1.75rem)
// Match: use fs-3 or $h3-font-size
```

### 3. Check Color System
```scss
// Bootstrap: primary, secondary, success, danger, warning, info, light, dark
// Figma: #0066CC
// Check if close to $primary, if not → CREATE
```

### 4. Check Components
```scss
// Figma: rounded button
// Bootstrap: .btn with .rounded-pill
// Use Bootstrap component if structure matches
```

## Mapping Figma to Bootstrap

### Spacing

| Figma px | Bootstrap Class | Bootstrap Var |
|----------|-----------------|---------------|
| 0 | p-0, m-0 | 0 |
| 4 | p-1, m-1 | $spacer * 0.25 |
| 8 | p-2, m-2 | $spacer * 0.5 |
| 16 | p-3, m-3 | $spacer |
| 24 | p-4, m-4 | $spacer * 1.5 |
| 48 | p-5, m-5 | $spacer * 3 |

### Font Sizes

| Figma px | Bootstrap Class | Bootstrap Var |
|----------|-----------------|---------------|
| 12 | fs-6, small | $font-size-sm |
| 14 | - | $font-size-base * 0.875 |
| 16 | fs-5 | $font-size-base |
| 20 | fs-4 | $h4-font-size |
| 24 | fs-3 | $h3-font-size |
| 28-32 | fs-2 | $h2-font-size |
| 36-40 | fs-1 | $h1-font-size |

### Border Radius

| Figma px | Bootstrap Class | Bootstrap Var |
|----------|-----------------|---------------|
| 0 | rounded-0 | 0 |
| 4 | rounded-1 | $border-radius-sm |
| 8 | rounded-2 | $border-radius |
| 12-16 | rounded-3 | $border-radius-lg |
| 50% | rounded-circle | 50% |
| pill | rounded-pill | $border-radius-pill |

## SCSS Best Practices

### Never Use @extend
```scss
// BAD
.my-button {
  @extend .btn;
  @extend .btn-primary;
}

// GOOD - use in template
// class="btn btn-primary my-button"
```

### Never Use !important
```scss
// BAD
.override {
  color: red !important;
}

// GOOD - increase specificity properly
.component .override {
  color: red;
}
```

### Use Bootstrap Variables
```scss
// BAD
.component {
  padding: 16px;
  color: #0d6efd;
}

// GOOD
.component {
  padding: $spacer;
  color: $primary;
}
```

### Use CSS Custom Properties
```scss
// Component-scoped customization
.hero {
  --hero-padding: #{$spacer * 2};
  padding: var(--hero-padding);
}
```

## Decision Flowchart

```
Figma Value
    │
    ▼
Is there a Bootstrap equivalent?
    │
    ├── YES → Is difference < 6px?
    │             │
    │             ├── YES → ACCOMMODATE (use Bootstrap)
    │             │
    │             └── NO → Is it a site-wide change?
    │                          │
    │                          ├── YES → CUSTOMIZE ($variable)
    │                          │
    │                          └── NO → EXTEND (add new value)
    │
    └── NO → CREATE (custom CSS)
```

## Examples

### Example 1: Button
```
Figma: padding 12px 24px, border-radius 8px
Bootstrap: .btn has padding ~10px 20px, border-radius 6px

Padding diff: 2-4px < 6px → ACCOMMODATE
Radius diff: 2px < 6px → ACCOMMODATE

Decision: Use .btn class with minor utility adjustments
```

### Example 2: Hero Section
```
Figma: padding 80px, custom gradient

Padding: 80px not in Bootstrap scale → EXTEND or CREATE
Gradient: No Bootstrap equivalent → CREATE

Decision: Add custom hero styles with CSS custom properties
```

### Example 3: Typography
```
Figma: heading 32px, body 17px
Bootstrap: h2 ~32px, body 16px

Heading diff: ~0px → ACCOMMODATE (use h2)
Body diff: 1px < 6px → ACCOMMODATE (use default)

Decision: Use Bootstrap typography as-is
```
