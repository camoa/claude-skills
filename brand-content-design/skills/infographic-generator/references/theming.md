# Theme Configuration Reference

## Contents
- Theme Basics
- Color Configuration
- Typography Settings
- Shape Styling
- Stylize Effects
- Complete Example

## Theme Basics

The ANTV infographic supports `light` and `dark` base themes, customizable via `themeConfig`.

```javascript
await createInfographic({
  theme: 'dark',           // Base theme: 'light' or 'dark'
  themeConfig: { ... },    // Custom overrides
  // ... other options
});
```

## Color Configuration

### Primary Colors

```javascript
themeConfig: {
  colorPrimary: '#00f3ff',  // Main accent color (titles, highlights)
  colorBg: '#0D2B5C',       // Background color (solid only)
}
```

### Color Palette

The `palette` array cycles through colors for items:

```javascript
themeConfig: {
  palette: ['#00f3ff', '#78A5D7', '#3773B4', '#B9D2F0'],
  // Item 1: #00f3ff, Item 2: #78A5D7, etc.
}
```

## Typography Settings

### Base Text

```javascript
themeConfig: {
  base: {
    text: {
      'font-family': 'Inter, sans-serif',
      'fill': '#FFFFFF',
      'font-size': 14
    }
  }
}
```

### Title and Description

```javascript
themeConfig: {
  title: {
    'fill': '#00f3ff',
    'font-weight': 'bold',
    'font-size': 28,
    'font-family': 'Inter, sans-serif'
  },
  desc: {
    'fill': '#B9D2F0',
    'font-size': 16,
    'font-family': 'Inter, sans-serif'
  }
}
```

### Item Labels and Descriptions

```javascript
themeConfig: {
  item: {
    label: {
      'fill': '#00f3ff',
      'font-weight': 'bold',
      'font-size': 18
    },
    desc: {
      'fill': '#B9D2F0',
      'font-size': 14
    }
  }
}
```

## Shape Styling

### Base Shape

```javascript
themeConfig: {
  base: {
    shape: {
      'stroke': '#00f3ff',
      'stroke-width': 2,
      'fill': 'transparent'
    }
  }
}
```

## Stylize Effects

ANTV supports special visual effects:

### Rough/Hand-drawn Style

```javascript
themeConfig: {
  stylize: { type: 'rough' }
}
```

### Pattern Fill

```javascript
themeConfig: {
  stylize: {
    type: 'pattern',
    pattern: 'dots'  // or 'lines', 'crosses'
  }
}
```

### Gradient Fill

```javascript
themeConfig: {
  stylize: {
    type: 'linear-gradient',
    colors: ['#00f3ff', '#194582']
  }
}
```

## Complete Example

Palcera brand theme:

```javascript
const palceraTheme = {
  colorPrimary: '#00f3ff',
  colorBg: '#0D2B5C',
  palette: ['#00f3ff', '#78A5D7', '#3773B4', '#B9D2F0'],
  base: {
    text: {
      'font-family': 'Inter, sans-serif',
      'fill': '#FFFFFF'
    },
    shape: {
      'stroke': '#00f3ff',
      'stroke-width': 1
    }
  },
  title: {
    'fill': '#00f3ff',
    'font-weight': 'bold',
    'font-size': 28
  },
  desc: {
    'fill': '#B9D2F0',
    'font-size': 16
  },
  item: {
    label: {
      'fill': '#00f3ff',
      'font-weight': 'bold',
      'font-size': 18
    },
    desc: {
      'fill': '#B9D2F0',
      'font-size': 14
    }
  }
};
```

## Brand Color Mapping

| Brand Element | Theme Property |
|--------------|----------------|
| Primary color | `colorPrimary` |
| Background | `colorBg` (solid) or custom background |
| Accent colors | `palette` array |
| Heading color | `title.fill` |
| Body text | `desc.fill`, `item.desc.fill` |
| Labels | `item.label.fill` |
| Lines/borders | `base.shape.stroke` |
