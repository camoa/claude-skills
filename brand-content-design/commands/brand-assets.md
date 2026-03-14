---
description: Manage brand assets - add, review, and copy assets to the project without re-running full extraction. Use when user says "add logo", "update fonts", "brand assets", "add brand image", "manage assets".
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Brand Assets Command

Manage brand assets (logos, icons, images, fonts) without re-running full brand extraction.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

## Asset Types and Locations

**Input folder structure** (`input/`):
```
input/
├── logos/          # Logo files (SVG, PNG, AI, EPS)
├── icons/          # Icon sets, favicons
├── images/         # Brand photography, illustrations
├── fonts/          # Custom font files (TTF, OTF, WOFF)
├── screenshots/    # Website/app screenshots (for extraction)
└── documents/      # Brand guidelines PDFs, etc. (for extraction)
```

**Assets folder** (`assets/`) - processed assets ready for use:
```
assets/
├── logo.svg        # Primary logo
├── logo-dark.svg   # Logo variant for dark backgrounds
├── logo-icon.svg   # Icon-only version
├── favicon.png     # Favicon
└── fonts/          # Fonts copied for use
```

## Workflow

1. **Verify project**
   - Check for brand-philosophy.md
   - Load current brand philosophy

2. **Scan for assets**
   Scan both `input/` and `assets/` folders:
   - `input/logos/*`
   - `input/icons/*`
   - `input/images/*`
   - `input/fonts/*`
   - `assets/*`

3. **Show asset status**
   ```
   📁 Brand Assets

   In input/ (source files):
   - logos/: logo.svg, logo-white.png
   - icons/: favicon.ico, icon-set.svg
   - images/: hero-photo.jpg
   - fonts/: CustomFont-Regular.ttf

   In assets/ (ready to use):
   - logo.svg (primary)

   Not yet copied: 3 files
   ```

4. **Ask what to do**
   Use AskUserQuestion:
   - "Review and copy new assets to assets/"
   - "Set primary logo"
   - "Add asset descriptions to brand-philosophy.md"
   - "Just show status (done)"

5. **If "Review and copy new assets":**
   For each file in input/ not yet in assets/:
   - Show the file (read if image)
   - Ask: "Copy to assets/? If yes, what name/role?"
     - Primary logo
     - Dark mode logo
     - Icon only
     - Secondary logo
     - Background image
     - Skip
   - Copy selected files to assets/ with appropriate names

6. **If "Set primary logo":**
   - List all logo files in assets/
   - Ask which should be primary
   - Update brand-philosophy.md Brand Assets section

7. **If "Add asset descriptions":**
   - For each asset in assets/, ask for description if missing
   - Update brand-philosophy.md with asset inventory

8. **Update brand-philosophy.md**
   Update the Brand Assets section:
   ```markdown
   ## Brand Assets

   ### Logo
   - **Primary logo**: `assets/logo.svg`
   - **Dark mode**: `assets/logo-dark.svg`
   - **Icon only**: `assets/logo-icon.svg`

   ### Other Assets
   - **Favicon**: `assets/favicon.png`
   - **Hero image**: `assets/hero.jpg`
   ```

## Output

- Copied: New assets to `assets/`
- Updated: `brand-philosophy.md` with asset inventory
- Status: Summary of all brand assets

## Notes

- This command is for asset management only - does not re-analyze brand
- Use `/brand-extract` if you need to re-analyze brand from new source materials
- Assets in `assets/` are referenced by templates and content commands
