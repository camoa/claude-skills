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
| **Extended Harmony** | Rich palette from existing brand colors | Harmonies from all brand colors merged | - |

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
| Complex infographic | Derived | Tetradic, Extended Harmony |
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
Analogous: Primary ± 30° on wheel
Complementary: Primary + 180°
Split-Complementary: Primary + 150°, Primary + 210°
Triadic: Primary + 120°, Primary + 240°
Tetradic: Primary + 90°, Primary + 180°, Primary + 270°
Extended Harmony: Apply Triadic to each brand color, merge unique results
```

### Tonal

```
Tints: Mix with white at 25%, 50%, 75%
Shades: Mix with black at 25%, 50%, 75%
Tones: Mix with gray at 25%, 50%, 75%
Interpolation: Blend primary → secondary at 25%, 50%, 75%
```

---

## Alternative Palette Generation

For mood-based alternatives, analyze brand personality and translate to new colors:

1. **Extract brand feeling** - What emotions does the current palette evoke?
2. **Map to new colors** - Find colors that evoke the same emotions in the target mood
3. **Maintain relationships** - If brand has high contrast, maintain that in alternative
4. **Test coherence** - Ensure the alternative still "feels like" the brand

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
