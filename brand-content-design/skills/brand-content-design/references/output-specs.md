# Output Specifications

Technical specifications for all content types.

---

## Presentations

### Dimensions
- **Standard**: 1920 x 1080 pixels (16:9 aspect ratio)
- **Alternative**: 1280 x 720 pixels (16:9, lower res)

### Output Format
- **Primary**: PDF
- **Conversion**: PDF → PPTX using pptx skill
- **File size**: Under 10 MB recommended

### Typography Minimums
| Element | Minimum | Recommended |
|---------|---------|-------------|
| Title/Headlines | 36pt | 44-60pt |
| Body text | 24pt | 28-32pt |
| Captions/Labels | 18pt | 20-24pt |

### Content Guidelines
| Aspect | Guideline |
|--------|-----------|
| Words per slide | 15-20 maximum |
| Slides total | 8-15 typical |
| Ideas per slide | ONE |
| Comprehension time | 3 seconds |

---

## LinkedIn Carousels

### Dimensions
- **Recommended**: 1080 x 1350 pixels (4:5 portrait ratio)
- **Alternative**: 1080 x 1080 pixels (1:1 square)
- **Maximum**: 4320 x 4320 pixels

### Output Format
- **Primary**: PDF (multi-page, one page per slide)
- **Alternative**: PNG sequence
- **File size**: Under 3 MB recommended

### Typography Minimums
| Element | Minimum | Recommended |
|---------|---------|-------------|
| Headlines | 24pt | 28-36pt |
| Body text | 18pt | 20-24pt |

### Content Guidelines
| Aspect | Guideline |
|--------|-----------|
| Words per slide | 10-30 maximum |
| Slides total | 5-10 optimal |
| Ideas per slide | ONE |
| Comprehension time | 2 seconds |

### Safe Zones
- Keep essential content within central 90%
- LinkedIn may crop edges on some displays
- Leave padding/breathing room around content

---

## Instagram Carousels

### Dimensions
- **Standard**: 1080 x 1080 pixels (1:1 square)
- **Portrait**: 1080 x 1350 pixels (4:5)
- **Landscape**: 1080 x 566 pixels (1.91:1)

### Output Format
- **Primary**: PDF (multi-page)
- **Alternative**: PNG sequence
- **File size**: Under 3 MB recommended

### Typography Minimums
| Element | Minimum | Recommended |
|---------|---------|-------------|
| Headlines | 22pt | 24-32pt |
| Body text | 16pt | 18-22pt |

### Content Guidelines
| Aspect | Guideline |
|--------|-----------|
| Words per slide | 10-25 maximum |
| Slides total | 5-10 optimal |
| Ideas per slide | ONE |
| Comprehension time | 2 seconds |

---

## File Naming Convention

### Template Files
```
templates/{type}/{template-name}/
├── template.md
├── canvas-philosophy.md
└── sample.pdf
```

### Output Files
```
outputs/{type}/{YYYY-MM-DD}-{name}/
├── {name}.pdf
├── {name}.pptx (presentations only)
└── slides/ (optional PNG exports)
```

### Examples
- `outputs/presentations/2025-12-08-q4-results/q4-results.pdf`
- `outputs/carousels/2025-12-08-product-launch/product-launch.pdf`

---

## Quality Standards

### Image Quality
- High resolution only (no pixelation at output size)
- Professional quality reflects on brand
- Authentic over obviously stock

### Contrast
- WCAG 2.1 AA compliance recommended
- Minimum contrast ratio 4.5:1 for text
- Test on actual devices

### Consistency
- Same fonts throughout piece
- Same color palette throughout
- Same layout patterns across slides
- Repetition creates cohesion

---

## Export Checklist

- [ ] Correct dimensions for content type
- [ ] File size under limit
- [ ] Text readable at output size
- [ ] High contrast maintained
- [ ] Safe zones respected
- [ ] Consistent styling throughout
- [ ] Preview checked before final save

---

*Technical specifications for brand-content-design plugin*
