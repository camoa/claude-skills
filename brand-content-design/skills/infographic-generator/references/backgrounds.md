# Custom Background Reference

## Contents
- Background Limitations
- Simple Backgrounds
- Gradient Types
- Pattern Types
- Layered Backgrounds
- Preset Reference
- Custom Configuration

## Background Limitations

ANTV's `colorBg` only supports solid colors. For gradients and patterns, use post-render injection via `extractSVGBuffer()`.

## Simple Backgrounds

### Using Presets

```javascript
const bg = renderer.createBackgroundPreset('spotlight', brandColors);
const svgBuffer = renderer.extractSVGBuffer(dom, { customBackground: bg });
```

### Available Simple Presets

| Preset | Type | Effect |
|--------|------|--------|
| `spotlight` | radial-gradient | Center spotlight fade |
| `diagonal-fade` | linear-gradient | Corner to corner fade |
| `top-down` | linear-gradient | Vertical fade |
| `subtle-dots` | pattern | Light dot pattern |
| `tech-grid` | pattern | Grid lines |
| `crosshatch` | pattern | Diagonal crosshatch |

## Gradient Types

### Radial Gradient

```javascript
{
  type: 'radial-gradient',
  cx: '50%',    // Center X
  cy: '40%',    // Center Y
  r: '80%',     // Radius
  stops: [
    { offset: '0%', color: '#194582' },
    { offset: '50%', color: '#0D2B5C' },
    { offset: '100%', color: '#020810' }
  ]
}
```

### Linear Gradient

```javascript
{
  type: 'linear-gradient',
  x1: '0%', y1: '0%',     // Start point
  x2: '100%', y2: '100%', // End point
  stops: [
    { offset: '0%', color: '#194582' },
    { offset: '100%', color: '#020810' }
  ]
}
```

## Pattern Types

### Dots

```javascript
{
  pattern: 'dots',
  size: 20,           // Grid size
  dotSize: 1,         // Dot radius
  foregroundColor: '#00f3ff',
  backgroundColor: 'transparent',
  opacity: 0.08
}
```

### Grid

```javascript
{
  pattern: 'grid',
  size: 30,
  strokeWidth: 0.5,
  foregroundColor: '#00f3ff',
  opacity: 0.06
}
```

### Diagonal Lines

```javascript
{
  pattern: 'diagonal',
  size: 15,
  strokeWidth: 1,
  foregroundColor: '#00f3ff',
  opacity: 0.08
}
```

### Crosshatch

```javascript
{
  pattern: 'crosshatch',
  size: 15,
  strokeWidth: 0.5,
  foregroundColor: '#00f3ff',
  opacity: 0.06
}
```

## Layered Backgrounds

Combine gradient base + pattern overlay:

```javascript
const layered = renderer.createLayeredPreset('spotlight-dots', {
  primary: '#194582',
  dark: '#0D2B5C',
  darker: '#061120',
  accent: '#00f3ff'
});

const svgBuffer = renderer.extractSVGBuffer(dom, {
  layeredBackground: layered
});
```

### Available Layered Presets

| Preset | Gradient | Pattern |
|--------|----------|---------|
| `spotlight-dots` | Radial spotlight | Subtle dots |
| `spotlight-grid` | Radial spotlight | Grid lines |
| `diagonal-crosshatch` | Diagonal fade | Crosshatch |
| `tech-matrix` | Tech gradient | Dense grid |

## Preset Reference

### Brand Colors Object

```javascript
const brandColors = {
  primary: '#194582',   // Main brand blue
  dark: '#0D2B5C',      // Dark blue
  darker: '#061120',    // Darkest (near black)
  accent: '#00f3ff'     // Cyan accent
};
```

### Getting Available Presets

```javascript
// Simple presets
const simple = renderer.getBackgroundPresets();
// ['spotlight', 'diagonal-fade', 'top-down', 'subtle-dots', 'tech-grid', 'crosshatch']

// Layered presets
const layered = renderer.getLayeredPresets();
// ['spotlight-dots', 'spotlight-grid', 'diagonal-crosshatch', 'tech-matrix']
```

## Custom Configuration

### Full Custom Layered Background

```javascript
const custom = {
  gradient: {
    type: 'radial-gradient',
    cx: '50%',
    cy: '30%',
    r: '90%',
    stops: [
      { offset: '0%', color: '#194582' },
      { offset: '40%', color: '#0D2B5C' },
      { offset: '100%', color: '#020810' }
    ]
  },
  pattern: {
    pattern: 'dots',
    size: 16,
    dotSize: 1.2,
    foregroundColor: '#00f3ff',
    opacity: 0.12
  }
};

const svgBuffer = renderer.extractSVGBuffer(dom, {
  layeredBackground: custom
});
```

### Gradient-Only Background

```javascript
const gradientOnly = renderer.createBackgroundPreset('spotlight', brandColors);
const svgBuffer = renderer.extractSVGBuffer(dom, {
  customBackground: gradientOnly
});
```

### Pattern-Only Background

```javascript
const patternOnly = {
  pattern: 'dots',
  size: 20,
  dotSize: 1,
  foregroundColor: '#00f3ff',
  backgroundColor: '#0D2B5C',  // Solid base
  opacity: 0.1
};

const svgBuffer = renderer.extractSVGBuffer(dom, {
  customBackground: patternOnly
});
```
