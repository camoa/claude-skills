# Technical Implementation

Code patterns for PDF generation with reportlab.

## Contents

- Asset preparation (SVG conversion, font loading)
- PDF generation patterns (presentations, carousels)
- Color parsing from brand-philosophy.md
- Positioning patterns (centered, asymmetric, grid)
- Full workflow example

---

## Asset Preparation

**Before generating any visual content**, prepare assets for PDF embedding.

### SVG to PNG Conversion

SVG logos must be converted to PNG for reliable PDF embedding:

```python
# Using cairosvg (recommended for quality)
import cairosvg

cairosvg.svg2png(
    url="assets/logo.svg",
    write_to="assets/logo.png",
    output_width=800,  # Scale up for crisp rendering
    output_height=None  # Maintain aspect ratio
)

# Or using Inkscape CLI
# inkscape assets/logo.svg --export-filename=assets/logo.png --export-width=800
```

**Why PNG over JPG?**
- PNG preserves transparency (essential for logos)
- PNG is lossless (no compression artifacts)
- JPG only for photographs where file size matters

### Font Handling

Load fonts from project's `assets/fonts/` directory:

```python
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
import os

def load_brand_fonts(project_path):
    """Load custom fonts from project assets."""
    fonts_dir = os.path.join(project_path, "assets", "fonts")

    if os.path.exists(fonts_dir):
        for font_file in os.listdir(fonts_dir):
            if font_file.endswith(('.ttf', '.otf')):
                font_name = os.path.splitext(font_file)[0]
                font_path = os.path.join(fonts_dir, font_file)
                try:
                    pdfmetrics.registerFont(TTFont(font_name, font_path))
                    print(f"Loaded font: {font_name}")
                except Exception as e:
                    print(f"Failed to load {font_file}: {e}")

# Load fonts before generating PDF
load_brand_fonts("/path/to/project")
```

---

## PDF Generation Patterns

### Presentation Slide (1920x1080)

```python
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor

SLIDE_WIDTH = 1920
SLIDE_HEIGHT = 1080
SLIDE_SIZE = (SLIDE_WIDTH, SLIDE_HEIGHT)

def create_presentation_pdf(output_path, slides_content, brand_colors, logo_path):
    """Generate multi-page presentation PDF."""
    c = canvas.Canvas(output_path, pagesize=SLIDE_SIZE)

    primary = HexColor(brand_colors['primary'])
    text_color = HexColor(brand_colors['text'])
    bg_color = HexColor(brand_colors['background'])

    for slide in slides_content:
        # Background
        c.setFillColor(bg_color)
        c.rect(0, 0, SLIDE_WIDTH, SLIDE_HEIGHT, fill=True, stroke=False)

        # Safe zones: 50px from edges
        safe_left = 50
        safe_right = SLIDE_WIDTH - 50
        safe_top = SLIDE_HEIGHT - 50
        safe_bottom = 50

        # Headline (positioned in top third)
        c.setFillColor(text_color)
        c.setFont("Helvetica-Bold", 72)
        c.drawString(safe_left, safe_top - 100, slide['headline'])

        # Logo (bottom right, respecting safe zone)
        if logo_path:
            logo_width = 150
            logo_height = 60
            logo_x = safe_right - logo_width
            logo_y = safe_bottom + 20
            c.drawImage(logo_path, logo_x, logo_y,
                       width=logo_width, height=logo_height,
                       preserveAspectRatio=True, mask='auto')

        c.showPage()

    c.save()
```

### Carousel Card (1080x1350)

```python
CARD_WIDTH = 1080
CARD_HEIGHT = 1350
CARD_SIZE = (CARD_WIDTH, CARD_HEIGHT)

def create_carousel_pdf(output_path, cards_content, brand_colors, logo_path):
    """Generate multi-page carousel PDF."""
    c = canvas.Canvas(output_path, pagesize=CARD_SIZE)

    text_color = HexColor(brand_colors['text'])
    bg_color = HexColor(brand_colors['background'])

    for card in cards_content:
        # Background
        c.setFillColor(bg_color)
        c.rect(0, 0, CARD_WIDTH, CARD_HEIGHT, fill=True, stroke=False)

        # Safe zones: 5% from edges (mobile-friendly)
        margin = CARD_WIDTH * 0.05

        # Headline (large, bold, thumb-stopping)
        c.setFillColor(text_color)
        c.setFont("Helvetica-Bold", 64)

        # Center text horizontally
        text_width = c.stringWidth(card['headline'], "Helvetica-Bold", 64)
        x = (CARD_WIDTH - text_width) / 2
        c.drawString(x, CARD_HEIGHT * 0.6, card['headline'])

        c.showPage()

    c.save()
```

---

## Color Parsing

Extract colors from brand-philosophy.md:

```python
import re

def parse_brand_colors(brand_philosophy_path):
    """Extract colors from brand-philosophy.md."""
    colors = {}
    with open(brand_philosophy_path, 'r') as f:
        content = f.read()

    # Parse the color table
    # Look for lines like: | Primary | Blue | #3B82F6 | ... |
    color_pattern = r'\|\s*(Primary|Secondary|Tertiary|Text|Background)\s*\|[^|]+\|\s*(#[A-Fa-f0-9]{6})\s*\|'

    for match in re.finditer(color_pattern, content):
        role = match.group(1).lower()
        hex_code = match.group(2)
        colors[role] = hex_code

    return colors
```

---

## Positioning Patterns

### Centered Layout (Ma, Minimal styles)

```python
def position_centered(canvas, text, font, size, y_position, canvas_width):
    """Center text horizontally on canvas."""
    text_width = canvas.stringWidth(text, font, size)
    x = (canvas_width - text_width) / 2
    canvas.setFont(font, size)
    canvas.drawString(x, y_position, text)
```

### Asymmetric Layout (Dramatic, Iki styles)

```python
def position_asymmetric(canvas, text, font, size, canvas_width, canvas_height):
    """Position text with dynamic tension (rule of thirds)."""
    x = canvas_width * 0.1  # Left third anchor
    y = canvas_height * 0.67  # Upper third
    canvas.setFont(font, size)
    canvas.drawString(x, y, text)
```

### Grid Layout (Swiss style)

```python
def create_grid(canvas_width, canvas_height, columns=12, rows=8):
    """Create Swiss-style grid coordinates."""
    col_width = canvas_width / columns
    row_height = canvas_height / rows

    def grid_pos(col, row):
        return (col * col_width, canvas_height - (row * row_height))

    return grid_pos
```

---

## Full Workflow

```python
def generate_visual_content(
    canvas_philosophy,
    style_constraints,
    content_outline,
    brand_philosophy_path,
    output_format,  # 'presentation' or 'carousel'
    output_path
):
    # 1. Load brand assets
    colors = parse_brand_colors(brand_philosophy_path)
    logo_path = get_logo_path(brand_philosophy_path)
    load_brand_fonts(os.path.dirname(brand_philosophy_path))

    # 2. Convert SVG logo if needed
    if logo_path and logo_path.endswith('.svg'):
        png_path = logo_path.replace('.svg', '.png')
        convert_svg_to_png(logo_path, png_path)
        logo_path = png_path

    # 3. Generate PDF based on format
    if output_format == 'presentation':
        create_presentation_pdf(output_path, content_outline, colors, logo_path)
    else:
        create_carousel_pdf(output_path, content_outline, colors, logo_path)

    return output_path
```

## PPTX Conversion

After PDF generation, use the `pptx` skill:
- Maintains design from PDF
- Creates editable text boxes
- Presentations only (carousels stay as PDF)
