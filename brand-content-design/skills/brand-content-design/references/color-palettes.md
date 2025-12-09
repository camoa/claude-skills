# Color Palettes

Reference for generating alternative color palettes from brand colors.

---

## Palette Types

### Harmony-Based (Color Wheel)

| Type | When to Use | Character | Learn More |
|------|-------------|-----------|------------|
| **Monochromatic** | Safe, cohesive, single-brand focus | One hue, varying lightness | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Monochromatic) |
| **Analogous** | Harmonious, comfortable, low energy | Adjacent colors on wheel | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Analogous) |
| **Complementary** | High contrast, CTAs, attention | Opposite colors on wheel | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Complementary) |
| **Split-Complementary** | Contrast with less visual tension | Base + two adjacent to complement | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Split-complementary) |
| **Triadic** | Balanced, vibrant, energetic | Three equally spaced | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Triadic) |
| **Tetradic** | Rich, complex, multi-element designs | Four colors (rectangle) | [Wikipedia](https://en.wikipedia.org/wiki/Color_scheme#Tetradic) |

### Tonal Variations

| Type | When to Use | Character | Learn More |
|------|-------------|-----------|------------|
| **Tints** | Lighter backgrounds, softer feel | Base + white | [Wikipedia](https://en.wikipedia.org/wiki/Tint,_shade_and_tone) |
| **Shades** | Darker accents, emphasis, depth | Base + black | [Wikipedia](https://en.wikipedia.org/wiki/Tint,_shade_and_tone) |
| **Tones** | Muted, sophisticated, subtle | Base + gray | [Wikipedia](https://en.wikipedia.org/wiki/Tint,_shade_and_tone) |

### Custom

| Type | When to Use | Character |
|------|-------------|-----------|
| **Custom** | Specific mood or campaign | User describes, AI generates |

---

## Quick Decision Guide

| Need | Recommended Palette |
|------|---------------------|
| Professional, safe | Monochromatic |
| Warm, inviting | Analogous (warm side) |
| Call-to-action pop | Complementary |
| Vibrant but balanced | Triadic |
| Complex infographic | Tetradic |
| Subtle backgrounds | Tints |
| Bold headlines | Shades |
| Sophisticated muted | Tones |
| "Summer campaign feel" | Custom |

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

### Complementary
- Primary: #2563EB
- Complement: #EB8225
- Accent: #F59E0B

### Summer Campaign (Custom)
- Base: #F59E0B
- Secondary: #10B981
- Accent: #EC4899
```

---

*Based on standard color theory. See linked Wikipedia articles for detailed explanations.*
