---
name: converting-figma-to-sdc
description: Convert Figma designs to Drupal components. Use when user provides a Figma URL and wants to create an SDC (Twig) or Canvas (JSX) component. Extracts design data, identifies props/slots/static elements, and generates component files.
version: 0.2.0
model: sonnet
---

# Converting Figma to Drupal Components

Convert Figma designs into Drupal Single Directory Components (SDC) or Canvas JavaScriptComponents.

## When to Use

- User provides a Figma component URL
- User asks to convert a design to Drupal component
- User mentions "Figma to SDC" or "Figma to component"
- NOT for: General Figma questions without conversion intent

## Workflow Overview

```
1. Input     → Get Figma URL + target format + description
2. Extract   → Fetch component data from Figma API
3. Analyze   → Categorize elements (props/slots/static)
4. Review    → Present analysis for user confirmation
5. Generate  → Create component files
6. Output    → Write to specified location
```

## Step 1: Gather Input

Collect from user:

| Required | Optional |
|----------|----------|
| Figma component URL | Component description |
| Target format (sdc/canvas/both) | Theme location (for SDC) |
| Component name | |

**Parse Figma URL** to extract:
- `fileKey`: The file identifier (e.g., `abc123XYZ`)
- `nodeId`: The node/component ID (from `?node-id=X:Y`)

## Step 2: Extract from Figma

Use the `mcp__figma-mcp__get_figma_data` tool:

```
mcp__figma-mcp__get_figma_data(fileKey, nodeId)
```

Extract and organize:
- **Structure**: Layers, frames, groups, hierarchy
- **Text**: Content, font, size, weight, color
- **Colors**: Fills, strokes, backgrounds
- **Spacing**: Padding, margins, gaps
- **Layout**: Flex, grid, absolute positioning
- **Images**: Image fills, icons (use `mcp__figma-mcp__download_figma_images`)

## Step 3: Analyze and Categorize

For each element, determine its category:

| Category | Criteria | Examples |
|----------|----------|----------|
| **PROP** | Content that varies per instance | Headings, button text, URLs, colors |
| **SLOT** | Area for nested content/components | Body content, action areas, lists |
| **STATIC** | Fixed content, never changes | Decorative elements, fixed icons |

### Decision Rules

1. **Text content** → Usually PROP (string)
2. **Repeated text patterns** → SLOT (for iteration)
3. **Color/style variants** → PROP (enum)
4. **Interactive elements** → PROP + note behavior
5. **Decorative/structural** → STATIC

### Prop Type Inference

| Figma Element | Prop Type |
|---------------|-----------|
| Text layer | `string` |
| Boolean visibility | `boolean` |
| Color variations | `enum` (variant names) |
| Number in text | `number` |
| Image fill | `object` (src, alt, width, height) |
| URL-like text | `string` with `format: uri` |

### Apply Bootstrap Accommodation Framework

For styling decisions, apply the 6px threshold:
- **< 6px difference** from Bootstrap → Use Bootstrap utilities
- **>= 6px difference** → Custom styling needed

See `references/bootstrap-accommodation.md` for detailed framework.

## Step 4: Present Analysis for Review

Present findings in clear format:

```markdown
## Component Analysis: [Name]

### Props (Configurable)
| Name | Type | Required | Default | Source |
|------|------|----------|---------|--------|
| heading | string | yes | "Welcome" | Text layer "Title" |
| buttonVariant | enum[primary,secondary] | no | "primary" | Detected variants |

### Slots (Content Areas)
| Name | Description | Source |
|------|-------------|--------|
| content | Main body content | Frame "Content Area" |

### Static Elements
- Background gradient (decorative)
- Logo placement (fixed position)

### Detected Interactions
- Button click (needs handler)

### Styling Notes
- Uses Bootstrap `.btn` (ACCOMMODATE)
- Custom gradient (CREATE)
```

**Ask user to confirm or modify** before proceeding.

## Step 5: Generate Component

Based on target format:

### For Traditional SDC (Twig)

Generate these files:

**component-name.component.yml**
```yaml
name: Component Name
props:
  type: object
  properties:
    heading:
      type: string
      title: Heading
      examples: ['Welcome']
  required:
    - heading
slots:
  content:
    title: Content
```

**component-name.twig**
```twig
<div {{ attributes.addClass('component-name') }}>
  <h2>{{ heading }}</h2>
  {% block content %}
    {{ content }}
  {% endblock %}
</div>
```

**component-name.css**
```css
.component-name {
  /* Styles using Bootstrap utilities where possible */
}
```

See `references/sdc-generation.md` for complete patterns.

### For Canvas (JSX)

Generate config entity structure:

```yaml
# js_component.component_name.yml
machineName: component_name
name: Component Name
props:
  heading:
    type: string
    title: Heading
    examples: ['Welcome']
required:
  - heading
slots:
  content:
    title: Content
js:
  original: |
    import { cva } from 'class-variance-authority';
    export default function ComponentName({ heading = "Welcome", children }) {
      return (
        <div className="p-4">
          <h2 className="text-2xl font-bold">{heading}</h2>
          {children}
        </div>
      );
    }
  compiled: ''
css:
  original: ''
  compiled: ''
```

See `references/canvas-generation.md` for complete patterns.

## Step 6: Output

### For SDC
Write files to theme's `components/` directory:
```
themes/[theme]/components/[component-name]/
├── [component-name].component.yml
├── [component-name].twig
└── [component-name].css
```

### For Canvas
Output the config YAML for import or direct creation.

## Quick Reference

| Action | Tool/Method |
|--------|-------------|
| Get Figma data | `mcp__figma-mcp__get_figma_data` |
| Download images | `mcp__figma-mcp__download_figma_images` |
| Write SDC files | `Write` tool to theme directory |
| Canvas config | Output YAML structure |

## Common Patterns

### Image Props
```yaml
# SDC
image:
  type: object
  properties:
    src: { type: string, format: uri }
    alt: { type: string }
```

```javascript
// Canvas
photo: { src: string, alt: string, width: number, height: number }
// Use: <Image {...photo} />
```

### Variant Props (Enum)
```yaml
# SDC
variant:
  type: string
  enum: [primary, secondary, outline]
```

```javascript
// Canvas - use CVA
const styles = cva('btn', {
  variants: {
    intent: {
      primary: 'bg-blue-500 text-white',
      secondary: 'bg-gray-200 text-gray-800',
    }
  }
});
```

## References

- `references/figma-extraction.md` - Detailed Figma API patterns
- `references/sdc-generation.md` - Complete SDC generation guide
- `references/canvas-generation.md` - Canvas/JSX patterns
- `references/bootstrap-accommodation.md` - 6px threshold framework
- `references/prop-type-mapping.md` - Figma to prop type mapping
