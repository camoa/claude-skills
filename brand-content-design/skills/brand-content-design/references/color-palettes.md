# Color Palettes

Reference for generating alternative color palettes from brand colors.

---

## Palette Categories

### Derived Palettes (Color Theory)

Mathematical derivations from existing brand colors.

#### Harmony-Based (Color Wheel)

| Type | When to Use | Character | Learn More |
|------|-------------|-----------|------------|
| **Monochromatic** | Safe, cohesive, single-brand focus | One hue, varying lightness | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Monochromatic) |
| **Analogous** | Harmonious, comfortable, low energy | Adjacent colors on wheel | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Analogous) |
| **Complementary** | High contrast, CTAs, attention | Opposite colors on wheel | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Complementary) |
| **Split-Complementary** | Contrast with less visual tension | Base + two adjacent to complement | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Split-complementary) |
| **Triadic** | Balanced, vibrant, energetic | Three equally spaced | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Triadic) |
| **Tetradic** | Rich, complex, multi-element designs | Four colors (rectangle) | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Tetradic) |

#### Tonal Variations

| Type | When to Use | Character | Learn More |
|------|-------------|-----------|------------|
| **Tints** | Lighter backgrounds, softer feel | Base + white | [Wikipedia](https://en.wikipedia.org/wiki/Tint,_shade_and_tone) |
| **Shades** | Darker accents, emphasis, depth | Base + black | [Wikipedia](https://en.wikipedia.org/wiki/Tint,_shade_and_tone) |
| **Tones** | Muted, sophisticated, subtle | Base + gray | [Wikipedia](https://en.wikipedia.org/wiki/Tint,_shade_and_tone) |
| **Interpolation** | Gradients, data viz, smooth transitions | Blend between brand colors | [Color Interpolation](https://en.wikipedia.org/wiki/Color_gradient) |

---

### Alternative Palettes (Mood-Based)

Completely different colors that capture the same brand feeling/energy.

| Type | When to Use | Character | Example Transformation |
|------|-------------|-----------|------------------------|
| **Pastel** | Soft campaigns, gentle messaging | Light, airy, delicate | Professional blue → soft lavender, mint |
| **Bold** | Impact, announcements, CTAs | High saturation, strong contrast | Calm blue → deep navy, gold |
| **Earthy** | Natural, sustainable, authentic | Warm browns, greens, terracotta | Corporate → olive, sienna, cream |
| **Vibrant** | Energy, youth, excitement | Bright, saturated, dynamic | Reserved → coral, electric blue, lime |
| **Muted** | Sophistication, luxury, subtlety | Desaturated, refined | Bright → dusty rose, sage, taupe |
| **Monochrome** | Dramatic, editorial, focused | Grayscale + one accent color | Full palette → B&W + brand accent |
| **Custom** | Specific mood or campaign | User describes, AI generates | "Summer festival" → your interpretation |

---

## Quick Decision Guide

| Need | Category | Recommended |
|------|----------|-------------|
| Expand existing colors mathematically | Derived | Complementary, Triadic |
| Professional, safe variation | Derived | Monochromatic, Tones |
| Subtle backgrounds | Derived | Tints |
| Bold headlines | Derived | Shades |
| Complex infographic | Derived | Tetradic (from all colors) |
| Smooth gradients | Derived | Interpolation |
| Completely different look, same feel | Alternative | Pastel, Bold, Earthy |
| Seasonal campaign | Alternative | Custom |
| Premium/luxury feel | Alternative | Muted, Monochrome |
| Youth/energy campaign | Alternative | Vibrant, Bold |

---

## Derived Palette Calculations

### Harmony (from color wheel)

```
Monochromatic: Same hue, lightness at 30%, 50%, 70%, 90%
Analogous: Source ± 30° on wheel
Complementary: Source + 180°
Split-Complementary: Source + 150°, Source + 210°
Triadic: Source + 120°, Source + 240°
Tetradic: Source + 90°, Source + 180°, Source + 270°

(Source = selected color(s): primary only, all brand colors, or specific picks)
```

### Tonal

```
Tints: Mix source with white at 25%, 50%, 75%
Shades: Mix source with black at 25%, 50%, 75%
Tones: Mix source with gray at 25%, 50%, 75%
Interpolation: Blend between selected source colors at 25%, 50%, 75%
```

---

## Source Color Selection (Derived Palettes)

When generating derived palettes, user can choose:
- **Primary only** - Generate from main brand color (simplest)
- **All brand colors** - Generate from each color, combine results (richest)
- **Pick specific** - Choose which colors to use as sources

If multiple sources selected, results are labeled: "Complementary (from Primary)", "Complementary (from Secondary)"

---

## Alternative Palette Generation

For mood-based alternatives, transform the **entire brand palette**:

1. **Analyze full palette** - How many colors? What relationships? What energy?
2. **Transform each color** - Apply mood transformation to every brand color
3. **Maintain relationships** - Keep same contrast, warmth, and hierarchy
4. **Preserve structure** - 3-color brand = 3-color alternative

Example transformations:
```
Brand: #2563EB (blue), #10B981 (green), #F59E0B (amber)
Pastel: #93C5FD (soft blue), #6EE7B7 (soft green), #FCD34D (soft amber)
Bold: #1E40AF (deep blue), #047857 (deep green), #D97706 (deep amber)
Earthy: #6B7280 (slate), #4B5563 (charcoal), #92400E (brown)
```

---

## Output Format

When displaying palettes, show color boxes with hex codes:

```
██ ██ ██  Palette Name     #HEX1 #HEX2 #HEX3
```

Terminal color boxes use ANSI escape codes:
```bash
echo -e "\033[48;2;R;G;Bm     \033[0m"
```

---

## Storage Format

Save selected palettes to `brand-philosophy.md` under:

```markdown
## Alternative Palettes

### Complementary (Derived)
- Primary: #2563EB
- Complement: #EB8225
- Accent: #F59E0B

### Pastel (Alternative)
- Base: #E0E7FF
- Secondary: #FCE7F3
- Accent: #D1FAE5

### Summer Campaign (Custom)
- Base: #F59E0B
- Secondary: #10B981
- Accent: #EC4899
```

---

*Based on standard color theory. See linked Wikipedia articles for detailed explanations.*
