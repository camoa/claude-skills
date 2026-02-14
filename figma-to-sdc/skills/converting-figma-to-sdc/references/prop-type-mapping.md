# Figma to Prop Type Mapping

## Contents
- Element categorization rules
- Type inference from Figma
- Common patterns

## Categorization Decision Tree

```
Figma Element
    │
    ├── TEXT node
    │       │
    │       ├── Looks like heading/title → PROP (string, required)
    │       ├── Looks like body content → SLOT or PROP
    │       ├── Looks like label → PROP (string) or STATIC
    │       ├── Looks like placeholder → PROP with default
    │       └── Fixed text (copyright, etc.) → STATIC
    │
    ├── FRAME/GROUP (container)
    │       │
    │       ├── Contains varied content → SLOT
    │       ├── Repeating structure → SLOT (for list iteration)
    │       └── Structural only → STATIC (wrapper)
    │
    ├── RECTANGLE/SHAPE
    │       │
    │       ├── Has image fill → PROP (image object)
    │       ├── Background color → PROP (enum) or STATIC
    │       └── Decorative → STATIC
    │
    ├── VECTOR/ICON
    │       │
    │       ├── Meaningful icon → PROP (icon name/component)
    │       └── Decorative → STATIC
    │
    └── INSTANCE (component)
            │
            ├── Varies per use → SLOT (nested component)
            └── Always same → STATIC
```

## Text Element Analysis

### Signals for PROP
- Layer name suggests variability: "Title", "Heading", "Button Text"
- Text is specific/meaningful content
- Different variants have different text
- Text would change per instance

### Signals for STATIC
- Layer name suggests fixed: "Logo Text", "Copyright"
- Text is structural: "or", "and", separators
- Same across all variants
- Part of design, not content

### Signals for SLOT
- Layer named "Content", "Body", "Description"
- Large text area
- Contains multiple paragraphs
- Would contain user-provided markup

## Type Inference Rules

| Figma Characteristic | Inferred Type | Notes |
|---------------------|---------------|-------|
| Short text (<50 chars) | `string` | Headings, labels |
| Long text (>50 chars) | `string` or slot | May need slot for rich content |
| Number in text | `number` or `string` | Depends on if used for calculation |
| "true"/"false" text | `boolean` | Or use for toggle state |
| URL-like text | `string` with `format: uri` | Links |
| Email text | `string` with `format: email` | Contact |
| Date/time text | `string` with `format: date` | Temporal |
| Color variations | `enum` | List variant names |
| Size variations | `enum` | small, medium, large |

## From Figma Variants

If Figma component has variants:

```
Variant Property: "Size"
Options: Small, Medium, Large
→ Prop: size (enum: [small, medium, large])

Variant Property: "State"
Options: Default, Hover, Active, Disabled
→ May not need prop (CSS handles states)
→ Unless "Disabled" should be controllable → PROP (boolean)

Variant Property: "Type"
Options: Primary, Secondary, Outline
→ Prop: variant (enum: [primary, secondary, outline])
```

## Common Patterns

### Button Component
```yaml
# From Figma button with text "Click Me", variants Primary/Secondary
props:
  label:
    type: string
    title: Label
    # From text layer content
    examples: ['Click Me']
  url:
    type: string
    format: uri
    title: URL
    # Inferred from button purpose
  variant:
    type: string
    enum: [primary, secondary]
    # From Figma variants
```

### Card Component
```yaml
# From Figma card with image, title, description
props:
  title:
    type: string
    title: Title
  image:
    type: object
    properties:
      src: { type: string, format: uri }
      alt: { type: string }
  link:
    type: string
    format: uri
slots:
  description:
    title: Description
    # Long text area → slot for rich content
```

### Hero Component
```yaml
# From Figma hero with heading, subheading, CTA, background
props:
  heading:
    type: string
    title: Heading
  subheading:
    type: string
    title: Subheading
  ctaText:
    type: string
    title: CTA Text
  ctaUrl:
    type: string
    format: uri
  backgroundImage:
    type: object
    properties:
      src: { type: string, format: uri }
      alt: { type: string }
```

### Navigation Component
```yaml
# From Figma nav with menu items
props:
  items:
    type: array
    items:
      type: object
      properties:
        label: { type: string }
        url: { type: string, format: uri }
        isActive: { type: boolean }
```

## Naming Conventions

### SDC (snake_case)
```yaml
button_text
background_image
is_active
menu_items
```

### Canvas (camelCase)
```yaml
buttonText
backgroundImage
isActive
menuItems
```

## Required vs Optional

### Mark as Required when:
- Component makes no sense without it
- No sensible default exists
- User must always provide value

### Mark as Optional when:
- Has sensible default
- Component works without it
- Conditionally rendered

```yaml
props:
  title:
    type: string
  subtitle:  # Optional - component works without
    type: string
required:
  - title  # Required - must have title
```

## Default Values

Extract from Figma content:
```yaml
# Figma text: "Welcome to Our Site"
heading:
  type: string
  default: 'Welcome to Our Site'

# Figma button: "Learn More"
button_text:
  type: string
  default: 'Learn More'
```

For variants, use most common:
```yaml
# Figma default variant: Primary
variant:
  type: string
  enum: [primary, secondary]
  default: primary
```
