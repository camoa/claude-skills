# Technical Implementation

Code patterns for PDF generation with reportlab.

## Contents

- Asset preparation (SVG conversion, font loading)
- PDF generation patterns (presentations, carousels)
- Color parsing from brand-philosophy.md
- Positioning patterns (centered, asymmetric, grid)
- **Visual components (cards, gradients, icons)**
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

## Visual Components

Reusable components for enhanced carousel and presentation designs.
Check `style-constraints.md` for which styles support each component type.

### Cards (Rounded Containers)

Content cards group related elements with optional fill, border, and rounded corners.

```python
from reportlab.lib.colors import HexColor

def draw_content_card(canvas, x, y, width, height,
                      fill_color=None, border_color=None,
                      radius=16, border_width=2):
    """
    Draw a content card container.

    Args:
        canvas: reportlab canvas
        x, y: Bottom-left corner position
        width, height: Card dimensions
        fill_color: Hex color for fill (None = transparent)
        border_color: Hex color for border (None = no border)
        radius: Corner radius in pixels (0 = sharp corners)
        border_width: Border thickness in pixels
    """
    canvas.saveState()

    if fill_color:
        canvas.setFillColor(HexColor(fill_color))
    if border_color:
        canvas.setStrokeColor(HexColor(border_color))
        canvas.setLineWidth(border_width)

    canvas.roundRect(x, y, width, height, radius,
                     fill=bool(fill_color),
                     stroke=bool(border_color))

    canvas.restoreState()


def draw_icon_card(canvas, x, y, size, icon_path,
                   fill_color=None, icon_size=48, radius=12):
    """
    Draw a square card with centered icon.

    Args:
        canvas: reportlab canvas
        x, y: Bottom-left corner position
        size: Card width and height (square)
        icon_path: Path to icon PNG
        fill_color: Background color
        icon_size: Icon dimensions
        radius: Corner radius
    """
    canvas.saveState()

    # Draw card background
    if fill_color:
        canvas.setFillColor(HexColor(fill_color))
        canvas.roundRect(x, y, size, size, radius, fill=True, stroke=False)

    # Center icon in card
    icon_x = x + (size - icon_size) / 2
    icon_y = y + (size - icon_size) / 2

    if icon_path:
        canvas.drawImage(icon_path, icon_x, icon_y,
                        width=icon_size, height=icon_size,
                        mask='auto')

    canvas.restoreState()


def draw_feature_card(canvas, x, y, width, height,
                      icon_path, title, description,
                      fill_color, text_color,
                      title_font="Helvetica-Bold", title_size=24,
                      desc_font="Helvetica", desc_size=16,
                      icon_size=48, radius=16, padding=24):
    """
    Draw a feature card with icon, title, and description.

    Layout:
    +------------------------+
    |  [icon]               |
    |  Title                |
    |  Description text     |
    +------------------------+
    """
    canvas.saveState()

    # Draw card background
    if fill_color:
        canvas.setFillColor(HexColor(fill_color))
        canvas.roundRect(x, y, width, height, radius, fill=True, stroke=False)

    # Content area
    content_x = x + padding
    content_top = y + height - padding

    # Icon at top
    if icon_path:
        canvas.drawImage(icon_path, content_x, content_top - icon_size,
                        width=icon_size, height=icon_size, mask='auto')

    # Title below icon
    canvas.setFillColor(HexColor(text_color))
    canvas.setFont(title_font, title_size)
    title_y = content_top - icon_size - 20 - title_size
    canvas.drawString(content_x, title_y, title)

    # Description below title
    canvas.setFont(desc_font, desc_size)
    desc_y = title_y - 10 - desc_size
    canvas.drawString(content_x, desc_y, description)

    canvas.restoreState()
```

### Gradients (Background Transitions)

Linear gradients for background sweeps and visual depth.

```python
from reportlab.lib.colors import linearlyInterpolatedColor, HexColor, Color

def draw_gradient_rect(canvas, x, y, width, height,
                       color1, color2, direction='diagonal', steps=100):
    """
    Draw a rectangle with linear gradient fill.

    Args:
        canvas: reportlab canvas
        x, y: Bottom-left corner position
        width, height: Rectangle dimensions
        color1, color2: Start and end hex colors
        direction: 'horizontal', 'vertical', 'diagonal', 'diagonal-reverse'
        steps: Number of gradient steps (higher = smoother)
    """
    canvas.saveState()

    c1 = HexColor(color1)
    c2 = HexColor(color2)

    if direction == 'horizontal':
        # Left to right
        step_width = width / steps
        for i in range(steps):
            ratio = i / steps
            color = linearlyInterpolatedColor(c1, c2, 0, 1, ratio)
            canvas.setFillColor(color)
            canvas.rect(x + i * step_width, y, step_width + 1, height,
                       fill=True, stroke=False)

    elif direction == 'vertical':
        # Bottom to top
        step_height = height / steps
        for i in range(steps):
            ratio = i / steps
            color = linearlyInterpolatedColor(c1, c2, 0, 1, ratio)
            canvas.setFillColor(color)
            canvas.rect(x, y + i * step_height, width, step_height + 1,
                       fill=True, stroke=False)

    elif direction == 'diagonal-reverse':
        # Top-left to bottom-right
        step_size = max(width, height) * 2 / steps
        for i in range(steps):
            ratio = i / steps
            color = linearlyInterpolatedColor(c1, c2, 0, 1, ratio)
            canvas.setFillColor(color)
            # Draw diagonal strips
            offset = i * step_size - max(width, height)
            canvas.saveState()
            p = canvas.beginPath()
            p.moveTo(x + offset, y + height)
            p.lineTo(x + offset + step_size, y + height)
            p.lineTo(x + width, y + height - (width - offset - step_size))
            p.lineTo(x + width, y + height - (width - offset))
            p.close()
            canvas.clipPath(p, stroke=0)
            canvas.rect(x, y, width, height, fill=True, stroke=False)
            canvas.restoreState()

    else:  # diagonal (default) - bottom-left to top-right
        step_size = max(width, height) * 2 / steps
        for i in range(steps):
            ratio = i / steps
            color = linearlyInterpolatedColor(c1, c2, 0, 1, ratio)
            canvas.setFillColor(color)
            offset = i * step_size - max(width, height)
            canvas.saveState()
            p = canvas.beginPath()
            p.moveTo(x, y + offset)
            p.lineTo(x, y + offset + step_size)
            p.lineTo(x + offset + step_size, y)
            p.lineTo(x + offset, y)
            p.close()
            canvas.clipPath(p, stroke=0)
            canvas.rect(x, y, width, height, fill=True, stroke=False)
            canvas.restoreState()

    canvas.restoreState()


def draw_gradient_background(canvas, width, height, color1, color2, direction='diagonal'):
    """
    Draw full-page gradient background.
    Convenience wrapper for draw_gradient_rect.
    """
    draw_gradient_rect(canvas, 0, 0, width, height, color1, color2, direction)
```

### Icons (Lucide Library)

Load and render icons using the brand-content-design icon helper.

**Setup:** The plugin sets `BRAND_CONTENT_DESIGN_DIR` environment variable via SessionStart hook.

```python
import os
import sys
from pathlib import Path

# Icon setup with fallback paths
ICONS_AVAILABLE = False
plugin_dir = os.environ.get('BRAND_CONTENT_DESIGN_DIR')

# Fallback: try common plugin locations if env var not set
if not plugin_dir:
    possible_paths = [
        Path.home() / ".claude" / "plugins" / "marketplaces" / "camoa-skills" / "brand-content-design",
        Path.home() / "workspace" / "claude_memory" / "marketplaces" / "camoa-skills" / "brand-content-design",
    ]
    for path in possible_paths:
        if (path / "scripts" / "icons.py").exists():
            plugin_dir = str(path)
            break

if plugin_dir:
    scripts_path = str(Path(plugin_dir) / "scripts")
    if scripts_path not in sys.path:
        sys.path.insert(0, scripts_path)
    try:
        from icons import get_icon_png, search_icons, ICON_CATEGORIES, CAIROSVG_AVAILABLE
        ICONS_AVAILABLE = CAIROSVG_AVAILABLE
    except ImportError as e:
        print(f"Warning: Could not import icons module: {e}")
        ICONS_AVAILABLE = False
else:
    print("Warning: brand-content-design plugin directory not found. Icons unavailable.")
```

**Note:** The code tries multiple fallback paths if the environment variable isn't set. Ensure `cairosvg` is installed (`pip install cairosvg`).

```python
def draw_icon(canvas, name, x, y, color='#000000', size=48):
    """
    Draw a Lucide icon on canvas.

    Args:
        canvas: reportlab canvas
        name: Icon name (e.g., 'lightbulb', 'rocket', 'check-circle')
        x, y: Position (bottom-left of icon)
        color: Icon stroke color (hex)
        size: Icon dimensions in pixels

    Returns:
        True if icon was drawn, False if not found
    """
    icon_path = get_icon_png(name, color=color, size=size)

    if icon_path:
        canvas.drawImage(icon_path, x, y, width=size, height=size, mask='auto')
        return True
    return False


# Usage examples:

# Draw single icon
draw_icon(canvas, 'rocket', x=100, y=500, color='#3B82F6', size=64)

# Search for icons
chart_icons = search_icons('chart')  # ['chart-bar', 'chart-line', 'chart-pie', ...]

# Get icons by category
business_icons = ICON_CATEGORIES['business']  # ['briefcase', 'building', ...]

# Draw row of category icons
for i, icon_name in enumerate(ICON_CATEGORIES['growth'][:4]):
    draw_icon(canvas, icon_name, x=100 + i*80, y=400, color='#10B981', size=48)
```

### Combined Example: Feature Card with Gradient

```python
def draw_feature_slide(canvas, title, features, brand_colors):
    """
    Draw a slide with gradient background and feature cards.

    Args:
        canvas: reportlab canvas
        title: Slide headline
        features: List of dicts with 'icon', 'title', 'description'
        brand_colors: Dict with 'primary', 'secondary', 'text', 'background'
    """
    width, height = 1080, 1350  # Carousel card size

    # Gradient background
    draw_gradient_background(
        canvas, width, height,
        brand_colors['primary'],
        brand_colors['secondary'],
        direction='diagonal'
    )

    # Title at top
    canvas.setFillColor(HexColor('#FFFFFF'))
    canvas.setFont("Helvetica-Bold", 48)
    canvas.drawCentredString(width/2, height - 120, title)

    # Feature cards
    card_width = width - 120  # 60px margin each side
    card_height = 200
    card_x = 60
    start_y = height - 250

    for i, feature in enumerate(features):
        card_y = start_y - (i * (card_height + 24))

        # Get icon PNG
        icon_path = get_icon_png(feature['icon'], color=brand_colors['primary'], size=48)

        # Draw feature card
        draw_feature_card(
            canvas, card_x, card_y, card_width, card_height,
            icon_path=icon_path,
            title=feature['title'],
            description=feature['description'],
            fill_color='#FFFFFF',
            text_color=brand_colors['text'],
            radius=16
        )
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
