# Token-to-Bootstrap Mapping

6px threshold framework for mapping HTML design tokens (CSS custom properties) to Bootstrap SCSS variables. Apply this framework during Part 2 of the generator to produce `_variables.scss`.

## Contents

- The 6px Threshold Framework
  - When to Accommodate
  - When to Customize
  - When to Extend
  - When to Create
- Color Token Mapping
  - Adding Custom Colors to $theme-colors
- Typography Token Mapping
  - Custom Type Scale
- Spacing Token Mapping
  - Extending the $spacers Map
- Layout Token Mapping
  - Container Width Overrides
- Interaction Token Mapping
- Mapping Output Format

## The 6px Threshold Framework

For each design token extracted from the HTML, calculate the numeric difference from Bootstrap 5.3's default value. Classify the mapping action:

| Category | Action | Criteria |
|---|---|---|
| **Accommodate** | Use Bootstrap default | Difference <= 6px or visually negligible (color delta E < 5) |
| **Extend** | Add to existing map | Token extends Bootstrap (new breakpoint, new color, new spacer step) |
| **Customize** | Override variable | Difference > 6px from default, or color delta E >= 5 |
| **Create** | New custom variable | No Bootstrap equivalent exists |

### When to Accommodate

Do not override Bootstrap when the design token is close enough to the default. This reduces CSS output and keeps the theme aligned with Bootstrap's tested proportions.

Examples:
- Design specifies `font-size: 15px`, Bootstrap default is `16px` (1rem) -- difference is 1px, accommodate.
- Design border-radius is `6px`, Bootstrap default is `0.375rem` (6px at 16px base) -- exact match, accommodate.
- Design primary color is `#0d6efd` -- same as Bootstrap default, accommodate.

### When to Customize

Override the Bootstrap variable with the brand value.

Examples:
- Design specifies `font-size: 18px` for base, Bootstrap default is 16px -- difference is 2px but proportionally significant for base size, customize.
- Design primary color is `#2563eb` -- different from Bootstrap `#0d6efd`, customize.
- Design `$spacer` base is `1.25rem`, Bootstrap default is `1rem` -- customize.

### When to Extend

Add new entries to an existing Bootstrap Sass map without replacing existing ones.

Examples:
- Design has a spacing step `4rem` not in Bootstrap's `$spacers` map -- extend the map.
- Design introduces `$accent` color not in `$theme-colors` -- extend the map.

### When to Create

Define a new SCSS variable or CSS custom property for tokens with no Bootstrap counterpart.

Examples:
- `--transition-base`, `--transition-fast`, `--easing-default` -- no Bootstrap variable, create as CSS custom properties.
- `--min-tap-target` -- accessibility token, create as CSS custom property.

## Color Token Mapping

| HTML Token | Bootstrap Variable | Notes |
|---|---|---|
| `--color-primary` | `$primary` | Direct override |
| `--color-secondary` | `$secondary` | Direct override |
| `--color-accent` | `$info` or custom `$accent` | If delta E < 5 from `$info`, use it; otherwise create `$accent` |
| `--color-bg` | `$body-bg` | Direct override |
| `--color-bg-alt` | `$gray-100` or custom `$bg-alt` | Check proximity to Bootstrap gray scale |
| `--color-text` | `$body-color` | Direct override |
| `--color-text-muted` | `$text-muted` | Direct override |
| `--color-error` | `$danger` | Direct override |
| `--color-success` | `$success` | Direct override |
| `--color-warning` | `$warning` | Direct override |

### Adding Custom Colors to $theme-colors

When a brand color has no Bootstrap equivalent, add it to the theme colors map so Bootstrap utilities (`.bg-accent`, `.text-accent`, `.btn-accent`) are generated automatically:

```scss
// In _variables.scss, AFTER individual variable definitions:
$accent: #8b5cf6;
$bg-alt: #f8f9fb;

$custom-colors: (
  "accent": $accent,
  "bg-alt": $bg-alt,
);

// This merge happens in _init.scss after Bootstrap's maps are loaded.
// Place the $custom-colors definition here; the merge goes in a
// separate partial or at the top of _bootstrap.scss:
// $theme-colors: map-merge($theme-colors, $custom-colors);
```

## Typography Token Mapping

| HTML Token | Bootstrap Variable | Notes |
|---|---|---|
| `--font-heading` | `$font-family-heading` | Radix convention (not core Bootstrap) |
| `--font-body` | `$font-family-base` | Direct override |
| `--font-mono` | `$font-family-monospace` | Direct override |
| `--font-size-base` | `$font-size-base` | Direct override (in rem) |
| `--font-size-sm` | `$font-size-sm` | Usually `$font-size-base * 0.875` |
| `--font-size-lg` | `$font-size-lg` | Usually `$font-size-base * 1.25` |
| `--font-size-h1` | `$h1-font-size` | Override with brand ratio |
| `--font-size-h2` | `$h2-font-size` | Override with brand ratio |
| `--font-size-h3` | `$h3-font-size` | Override with brand ratio |
| `--font-size-h4` | `$h4-font-size` | Override with brand ratio |
| `--font-size-h5` | `$h5-font-size` | Override with brand ratio |
| `--font-size-h6` | `$h6-font-size` | Override with brand ratio |
| `--line-height` | `$line-height-base` | Direct override |
| `--heading-weight` | `$headings-font-weight` | Direct override |

### Custom Type Scale

When the brand uses a type scale that does not align with Bootstrap's default multipliers, define each heading size explicitly:

```scss
$h1-font-size: 3rem;      // Brand: 48px
$h2-font-size: 2.25rem;   // Brand: 36px
$h3-font-size: 1.75rem;   // Brand: 28px
$h4-font-size: 1.375rem;  // Brand: 22px
$h5-font-size: 1.125rem;  // Brand: 18px
$h6-font-size: 1rem;      // Brand: 16px
```

## Spacing Token Mapping

| HTML Token | Bootstrap Default | Bootstrap Variable |
|---|---|---|
| `--space-xs` | `$spacer * 0.25` (4px) | `$spacer` map key `1` |
| `--space-sm` | `$spacer * 0.5` (8px) | `$spacer` map key `2` |
| `--space-md` | `$spacer` (16px) | `$spacer` map key `3` |
| `--space-lg` | `$spacer * 1.5` (24px) | `$spacer` map key `4` |
| `--space-xl` | `$spacer * 3` (48px) | `$spacer` map key `5` |
| `--space-2xl` | No default | Extend map |
| `--space-3xl` | No default | Extend map |

### Extending the $spacers Map

```scss
$spacer: 1rem;

// Add large spacer steps for section padding
$spacers: map-merge($spacers, (
  6: $spacer * 4,    // 64px -- section padding small
  7: $spacer * 5,    // 80px -- section padding medium
  8: $spacer * 6,    // 96px -- section padding large
));
```

## Layout Token Mapping

| HTML Token | Bootstrap Variable | Notes |
|---|---|---|
| `--max-width` | `$container-max-widths` map | Override specific breakpoint values |
| `--border-radius` | `$border-radius` | Apply threshold: <= 6px difference = accommodate |
| `--border-radius-sm` | `$border-radius-sm` | Direct override |
| `--border-radius-lg` | `$border-radius-lg` | Direct override |
| `--border-radius-xl` | `$border-radius-xl` | Direct override if brand uses xl radius |
| `--shadow-sm` | `$box-shadow-sm` | Direct override |
| `--shadow-md` | `$box-shadow` | Direct override |
| `--shadow-lg` | `$box-shadow-lg` | Direct override |

### Container Width Overrides

```scss
$container-max-widths: (
  sm:  540px,
  md:  720px,
  lg:  960px,
  xl:  1140px,
  xxl: 1320px,     // Override if brand uses wider/narrower max-width
);
```

## Interaction Token Mapping

Timing and easing tokens have no direct Bootstrap SCSS variable. Map them to CSS custom properties in `:root` via `_elements.scss`:

| HTML Token | CSS Custom Property | Example Value |
|---|---|---|
| `--timing-normal` | `--transition-base` | `300ms` |
| `--timing-fast` | `--transition-fast` | `150ms` |
| `--easing-default` | `--easing-default` | `cubic-bezier(0.4, 0, 0.2, 1)` |
| `--min-tap-target` | `--min-tap-target` | `44px` |
| `--focus-ring-width` | `--focus-ring-width` | `2px` |
| `--focus-ring-color` | `--focus-ring-color` | `rgba(37, 99, 235, 0.5)` |

These are declared in `_elements.scss` inside `:root {}` and referenced from component SCSS.

## Mapping Output Format

Record every mapping decision in the `radix-sdc.yml` output config so the conversion report can display the full table:

```yaml
tokenMapping:
  - token: "--color-primary"
    value: "#2563eb"
    bootstrapVar: "$primary"
    bootstrapDefault: "#0d6efd"
    action: customize
    reasoning: "Delta E 12.4, exceeds threshold"

  - token: "--font-size-base"
    value: "16px"
    bootstrapVar: "$font-size-base"
    bootstrapDefault: "1rem (16px)"
    action: accommodate
    reasoning: "Exact match"

  - token: "--space-2xl"
    value: "4rem"
    bootstrapVar: "$spacers map"
    bootstrapDefault: "N/A"
    action: extend
    reasoning: "Added as spacer key 6"

  - token: "--timing-normal"
    value: "300ms"
    bootstrapVar: "N/A"
    bootstrapDefault: "N/A"
    action: create
    reasoning: "No Bootstrap SCSS equivalent, mapped to --transition-base CSS custom property"
```
