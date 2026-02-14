# Figma Data Extraction

## Contents
- Parsing Figma URLs
- Using the Figma MCP tools
- Understanding Figma node structure
- Extracting specific data types

## Parsing Figma URLs

Figma URLs follow this pattern:
```
https://www.figma.com/design/{fileKey}/{fileName}?node-id={nodeId}
https://www.figma.com/file/{fileKey}/{fileName}?node-id={nodeId}
```

Extract:
- **fileKey**: Alphanumeric string after `/design/` or `/file/`
- **nodeId**: Value of `node-id` parameter (format: `X:Y` or `X-Y`)

```javascript
// Example URL parsing
const url = "https://www.figma.com/design/abc123XYZ/MyDesign?node-id=1:234";
const fileKey = "abc123XYZ";
const nodeId = "1:234";  // or "1-234" - both formats work
```

## Using Figma MCP Tools

### Get Component Data

```
mcp__figma-mcp__get_figma_data
  fileKey: "abc123XYZ"
  nodeId: "1:234"  (optional - omit for full file)
```

Returns comprehensive data including:
- Node tree structure
- Text content
- Styles (fills, strokes, effects)
- Layout properties
- Component metadata

### Download Images

```
mcp__figma-mcp__download_figma_images
  fileKey: "abc123XYZ"
  nodes: [
    { nodeId: "1:234", fileName: "hero-image.png" },
    { nodeId: "1:235", fileName: "icon.svg", imageRef: "..." }
  ]
  localPath: "/path/to/save"
  pngScale: 2  (optional, default 2x)
```

## Figma Node Structure

### Common Node Types

| Type | Description | Drupal Mapping |
|------|-------------|----------------|
| FRAME | Container/layout | Wrapper div |
| TEXT | Text content | Prop (string) or static |
| RECTANGLE | Shape with fills | Background or decorative |
| VECTOR | Icon/graphic | Image or SVG |
| INSTANCE | Component instance | Nested component |
| GROUP | Grouped elements | Structural wrapper |

### Key Properties to Extract

**From TEXT nodes:**
```json
{
  "characters": "Button Text",
  "style": {
    "fontFamily": "Inter",
    "fontSize": 16,
    "fontWeight": 600,
    "textAlignHorizontal": "CENTER"
  },
  "fills": [{ "color": { "r": 1, "g": 1, "b": 1 } }]
}
```

**From FRAME nodes:**
```json
{
  "layoutMode": "VERTICAL",  // or "HORIZONTAL"
  "itemSpacing": 16,
  "paddingLeft": 24,
  "paddingRight": 24,
  "paddingTop": 16,
  "paddingBottom": 16,
  "fills": [...],
  "effects": [...]  // shadows, blur
}
```

**From nodes with images:**
```json
{
  "fills": [{
    "type": "IMAGE",
    "imageRef": "abc123..."  // Use this with download_figma_images
  }]
}
```

## Extracting Specific Data

### Colors
Convert Figma RGB (0-1 range) to CSS:
```javascript
// Figma: { r: 0.2, g: 0.4, b: 0.8, a: 1 }
// CSS: rgb(51, 102, 204) or #3366cc
const toCSS = (c) => `rgb(${Math.round(c.r*255)}, ${Math.round(c.g*255)}, ${Math.round(c.b*255)})`;
```

### Spacing
Figma uses pixels. Map to:
- Bootstrap spacing scale (0, 1, 2, 3, 4, 5, auto)
- Tailwind classes (p-1, p-2, etc.)
- Custom CSS values

### Typography
Map Figma font properties to:
- Bootstrap typography classes
- Tailwind text utilities
- CSS custom properties

### Layout
Map Figma auto-layout to:
- CSS Flexbox
- Bootstrap flex utilities
- CSS Grid (for complex layouts)

## Handling Variants

If the Figma component has variants:
```json
{
  "componentPropertyDefinitions": {
    "Size": { "type": "VARIANT", "variantOptions": ["Small", "Medium", "Large"] },
    "State": { "type": "VARIANT", "variantOptions": ["Default", "Hover", "Active"] }
  }
}
```

Map variants to:
- Enum props (for SDC)
- CVA variants (for Canvas)

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| 403 Forbidden | Invalid/expired token | Check Figma API token |
| 404 Not Found | Invalid fileKey/nodeId | Verify URL parsing |
| Empty response | Node doesn't exist | Confirm node-id format |
