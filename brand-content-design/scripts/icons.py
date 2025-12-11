#!/usr/bin/env python3
"""
Icon helper module for brand-content-design carousels and presentations.
Provides Lucide icons as PNG for reportlab embedding.

Usage:
    import os
    from pathlib import Path

    # The plugin sets BRAND_CONTENT_DESIGN_DIR via SessionStart hook
    plugin_dir = os.environ.get('BRAND_CONTENT_DESIGN_DIR')
    if plugin_dir:
        import sys
        sys.path.insert(0, str(Path(plugin_dir) / "scripts"))

    from icons import get_icon_png, search_icons, list_icons, ICON_CATEGORIES

    # Get icon as PNG path for reportlab
    icon_path = get_icon_png('rocket', color='#3B82F6', size=48)
    canvas.drawImage(icon_path, x, y, width=48, height=48, mask='auto')

    # Search icons by keyword
    matches = search_icons('chart')  # ['chart-bar', 'chart-line', ...]

    # List all icons in a category
    business_icons = ICON_CATEGORIES['business']

Requirements:
    - cairosvg: pip install cairosvg
    - lucide-static icons (from infographic-generator/node_modules)
    - BRAND_CONTENT_DESIGN_DIR environment variable (set by plugin hook)
"""

import os
import tempfile
import hashlib
from pathlib import Path

# Try to import cairosvg, provide helpful error if missing
try:
    import cairosvg
    CAIROSVG_AVAILABLE = True
except ImportError:
    CAIROSVG_AVAILABLE = False


def _get_plugin_dir() -> Path:
    """Get plugin directory from environment or fallback to script location."""
    # First, try environment variable (set by SessionStart hook)
    env_dir = os.environ.get('BRAND_CONTENT_DESIGN_DIR')
    if env_dir:
        return Path(env_dir)

    # Fallback: derive from this script's location
    # scripts/icons.py -> parent.parent = plugin root
    return Path(__file__).parent.parent


# Path to Lucide icons (from infographic-generator's node_modules)
ICONS_DIR = _get_plugin_dir() / "skills" / "infographic-generator" / "node_modules" / "lucide-static" / "icons"

# Cache directory for converted PNGs
CACHE_DIR = Path(tempfile.gettempdir()) / "brand-content-design-icons"

# Common icon categories for carousels/presentations
ICON_CATEGORIES = {
    'business': ['briefcase', 'building', 'building-2', 'landmark', 'store', 'factory', 'warehouse'],
    'growth': ['trending-up', 'trending-down', 'chart-bar', 'chart-line', 'chart-pie', 'target', 'award', 'trophy'],
    'people': ['user', 'users', 'user-plus', 'user-check', 'contact', 'smile', 'heart'],
    'communication': ['mail', 'message-circle', 'message-square', 'phone', 'video', 'radio', 'megaphone'],
    'technology': ['laptop', 'smartphone', 'tablet', 'monitor', 'server', 'cloud', 'database', 'cpu', 'wifi'],
    'actions': ['check', 'check-circle', 'x', 'x-circle', 'plus', 'minus', 'edit', 'trash-2', 'save'],
    'navigation': ['arrow-right', 'arrow-left', 'arrow-up', 'arrow-down', 'chevron-right', 'chevron-left', 'external-link'],
    'time': ['clock', 'calendar', 'timer', 'hourglass', 'history', 'calendar-days', 'alarm-clock'],
    'documents': ['file', 'file-text', 'folder', 'clipboard', 'book', 'notebook', 'newspaper', 'file-check'],
    'security': ['lock', 'unlock', 'shield', 'shield-check', 'key', 'eye', 'eye-off'],
    'money': ['dollar-sign', 'credit-card', 'wallet', 'coins', 'banknote', 'receipt', 'piggy-bank'],
    'nature': ['sun', 'moon', 'cloud', 'zap', 'droplet', 'leaf', 'tree', 'flower', 'globe'],
    'transport': ['car', 'truck', 'plane', 'ship', 'train', 'bike', 'bus'],
    'misc': ['star', 'heart', 'flag', 'bookmark', 'tag', 'gift', 'lightbulb', 'rocket', 'sparkles', 'thumbs-up']
}


def _ensure_cache_dir():
    """Create cache directory if it doesn't exist."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)


def _get_cache_path(name: str, color: str, size: int) -> Path:
    """Generate cache path for an icon with specific parameters."""
    # Create hash of parameters for unique filename
    params = f"{name}-{color}-{size}"
    hash_str = hashlib.md5(params.encode()).hexdigest()[:8]
    return CACHE_DIR / f"{name}_{size}_{hash_str}.png"


def list_icons() -> list:
    """
    List all available Lucide icon names.

    Returns:
        List of icon names (without .svg extension)
    """
    if not ICONS_DIR.exists():
        print(f"Warning: Icons directory not found: {ICONS_DIR}")
        return []

    return [f.stem for f in ICONS_DIR.glob("*.svg")]


def search_icons(keyword: str) -> list:
    """
    Search icons by keyword.

    Args:
        keyword: Search term (case-insensitive)

    Returns:
        List of matching icon names
    """
    icons = list_icons()
    term = keyword.lower()
    return [name for name in icons if term in name.lower()]


def get_icons_by_category(category: str) -> list:
    """
    Get icons in a specific category.

    Args:
        category: Category name from ICON_CATEGORIES

    Returns:
        List of icon names in that category
    """
    return ICON_CATEGORIES.get(category, [])


def list_categories() -> list:
    """List all available icon categories."""
    return list(ICON_CATEGORIES.keys())


def get_icon_svg(name: str, color: str = 'currentColor', size: int = 24) -> str:
    """
    Get icon as SVG string with color and size applied.

    Args:
        name: Icon name (e.g., 'rocket', 'check-circle')
        color: Stroke color (hex code or named color)
        size: Width and height in pixels

    Returns:
        SVG string or None if not found
    """
    svg_path = ICONS_DIR / f"{name}.svg"

    if not svg_path.exists():
        print(f"Icon not found: {name}")
        return None

    svg_content = svg_path.read_text()

    # Strip license comments
    import re
    svg_content = re.sub(r'<!--[\s\S]*?-->\s*', '', svg_content).strip()

    # Update color and size
    svg_content = svg_content.replace('width="24"', f'width="{size}"')
    svg_content = svg_content.replace('height="24"', f'height="{size}"')
    svg_content = svg_content.replace('stroke="currentColor"', f'stroke="{color}"')

    return svg_content


def get_icon_png(name: str, color: str = '#000000', size: int = 48) -> str:
    """
    Get icon as PNG file path for reportlab embedding.

    Converts SVG to PNG and caches the result.

    Args:
        name: Icon name (e.g., 'rocket', 'check-circle')
        color: Stroke color (hex code)
        size: Width and height in pixels

    Returns:
        Path to PNG file, or None if conversion fails

    Example:
        icon_path = get_icon_png('lightbulb', color='#3B82F6', size=48)
        canvas.drawImage(icon_path, x, y, width=48, height=48, mask='auto')
    """
    if not CAIROSVG_AVAILABLE:
        print("Error: cairosvg not installed. Run: pip install cairosvg")
        return None

    _ensure_cache_dir()

    # Check cache first
    cache_path = _get_cache_path(name, color, size)
    if cache_path.exists():
        return str(cache_path)

    # Get SVG content
    svg_content = get_icon_svg(name, color, size)
    if not svg_content:
        return None

    # Convert to PNG
    try:
        cairosvg.svg2png(
            bytestring=svg_content.encode('utf-8'),
            write_to=str(cache_path),
            output_width=size,
            output_height=size
        )
        return str(cache_path)
    except Exception as e:
        print(f"Error converting icon {name} to PNG: {e}")
        return None


def get_icon_data_uri(name: str, color: str = '#000000', size: int = 24) -> str:
    """
    Get icon as data URI (for inline embedding).

    Args:
        name: Icon name
        color: Stroke color
        size: Width and height

    Returns:
        Data URI string or None if not found
    """
    svg_content = get_icon_svg(name, color, size)
    if not svg_content:
        return None

    import urllib.parse
    encoded = urllib.parse.quote(svg_content)
    return f"data:image/svg+xml,{encoded}"


def clear_cache():
    """Clear the icon PNG cache."""
    if CACHE_DIR.exists():
        import shutil
        shutil.rmtree(CACHE_DIR)
        print(f"Cleared icon cache: {CACHE_DIR}")


# Quick test when run directly
if __name__ == "__main__":
    print("Icon Helper for brand-content-design")
    print("=" * 40)

    # Check icons directory
    if ICONS_DIR.exists():
        icons = list_icons()
        print(f"Found {len(icons)} icons in {ICONS_DIR}")
    else:
        print(f"Icons directory not found: {ICONS_DIR}")
        print("Make sure infographic-generator has npm dependencies installed.")
        exit(1)

    # Show categories
    print(f"\nCategories: {', '.join(list_categories())}")

    # Test search
    print(f"\nSearch 'chart': {search_icons('chart')}")

    # Test PNG conversion
    if CAIROSVG_AVAILABLE:
        png_path = get_icon_png('rocket', color='#3B82F6', size=48)
        if png_path:
            print(f"\nGenerated PNG: {png_path}")
    else:
        print("\ncairosvg not installed - PNG conversion unavailable")
