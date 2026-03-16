# Theme Configuration Reference

> **⚠️ BIAS WARNING:** All color and font values in this file are **illustrative placeholders**.
> Derive actual values from the project's `brand-philosophy.md`. Never copy hex codes or font names from these examples.

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
  colorPrimary: '{brand-primary}',  // Main accent color (titles, highlights) — Illustrative — derive from brand-philosophy.md
  colorBg: '{brand-bg}',            // Background color (solid only) — Illustrative — derive from brand-philosophy.md
}
```

### Color Palette

The `palette` array cycles through colors for items:

```javascript
themeConfig: {
  palette: ['{brand-primary}', '{brand-palette-2}', '{brand-palette-3}', '{brand-palette-4}'],
  // Illustrative — derive from brand-philosophy.md. Items cycle through palette colors.
}
```

## Typography Settings

### Base Text

```javascript
themeConfig: {
  base: {
    text: {
      'font-family': '{brand-heading-font}, sans-serif',  // Illustrative — derive from brand-philosophy.md
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
    'fill': '{brand-primary}',  // Illustrative — derive from brand-philosophy.md
    'font-weight': 'bold',
    'font-size': 28,
    'font-family': '{brand-heading-font}, sans-serif'  // Illustrative — derive from brand-philosophy.md
  },
  desc: {
    'fill': '{brand-palette-4}',  // Illustrative — derive from brand-philosophy.md
    'font-size': 16,
    'font-family': '{brand-heading-font}, sans-serif'  // Illustrative — derive from brand-philosophy.md
  }
}
```

### Item Labels and Descriptions

```javascript
themeConfig: {
  item: {
    label: {
      'fill': '{brand-primary}',  // Illustrative — derive from brand-philosophy.md
      'font-weight': 'bold',
      'font-size': 18
    },
    desc: {
      'fill': '{brand-palette-4}',  // Illustrative — derive from brand-philosophy.md
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
      'stroke': '{brand-primary}',  // Illustrative — derive from brand-philosophy.md
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
    colors: ['{brand-primary}', '{brand-dark}']  // Illustrative — derive from brand-philosophy.md
  }
}
```

## Complete Example

Brand theme (all values illustrative — derive from brand-philosophy.md):

```javascript
const brandTheme = {
  colorPrimary: '{brand-primary}',
  colorBg: '{brand-bg}',
  palette: ['{brand-primary}', '{brand-palette-2}', '{brand-palette-3}', '{brand-palette-4}'],
  base: {
    text: {
      'font-family': '{brand-heading-font}, sans-serif',
      'fill': '#FFFFFF'
    },
    shape: {
      'stroke': '{brand-primary}',
      'stroke-width': 1
    }
  },
  title: {
    'fill': '{brand-primary}',
    'font-weight': 'bold',
    'font-size': 28
  },
  desc: {
    'fill': '{brand-palette-4}',
    'font-size': 16
  },
  item: {
    label: {
      'fill': '{brand-primary}',
      'font-weight': 'bold',
      'font-size': 18
    },
    desc: {
      'fill': '{brand-palette-4}',
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
