---
description: Extract brand elements from multiple sources and generate brand-philosophy.md. Use when user says "extract brand", "analyze brand", "brand from website", "brand from logo", "brand from screenshot", "get brand colors", "brand philosophy".
allowed-tools: Read, Glob, Write, WebFetch, AskUserQuestion, Task
---

# Brand Extract Command

Analyze brand from multiple sources (files, website, verbal description, pasted guidelines) and generate brand-philosophy.md.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)

## Workflow

1. **Verify project**
   - Check for brand-philosophy.md in current directory
   - If not found: "This doesn't appear to be a brand project. Run /brand-init first."

2. **Scan input folder and report**
   Use Glob to find files in:
   - `input/screenshots/*.{png,jpg,jpeg,gif,webp}`
   - `input/documents/*.{pdf,docx,doc,txt,md}`
   - `input/logos/*.{png,jpg,svg,ai,eps}`
   - `input/fonts/*.{ttf,otf,woff,woff2}`

   Summarize what was found (e.g., "I found 3 screenshots, 1 PDF, 2 logo files, and 2 font files.")

3. **Ask for additional sources (conversational)**
   Based on what was found, ask an open question:

   **If files found:**
   > "I found [summary of files] in your input/ folder. What else should I use to understand your brand?
   > - Paste a website URL
   > - Describe your brand verbally
   > - Paste existing brand guidelines
   > - Or just say 'use the files' to proceed with what I found"

   **If no files found:**
   > "The input/ folder is empty. How would you like to provide brand information?
   > - Paste a website URL
   > - Describe your brand (colors, voice, personality, etc.)
   > - Paste existing brand guidelines"

4. **Gather all sources**
   Based on user response, collect source list:
   - **Files**: List of images, PDFs, documents from input/
   - **Website**: URL(s) provided by user
   - **Verbal description**: User's brand description text
   - **Pasted guidelines**: Existing brand doc content

   Note: User may provide multiple sources in one response. Parse and collect all.

5. **Delegate analysis to brand-analyst agent**
   Use the Task tool to spawn the `brand-analyst` agent for heavy analysis.

   **Why delegate:** Asset analysis (images, PDFs, websites) consumes significant context.
   Running in a separate agent preserves the main conversation's context window.

   **Task prompt should include:**
   - List of all files to analyze (full paths)
   - Website URL(s) if provided
   - Verbal description if provided
   - Pasted guidelines if provided
   - Request structured output matching brand-philosophy-template.md format

   **Example Task call:**
   ```
   Task tool with subagent_type: "brand-content-design:brand-analyst"
   Prompt: "Analyze these brand assets and return structured brand elements:

   Files to analyze:
   - /path/to/project/input/screenshots/homepage.png
   - /path/to/project/input/logos/logo.svg
   - /path/to/project/input/documents/brand-guide.pdf

   Website: https://example.com

   User description: [paste user's verbal description]

   Return analysis in brand-philosophy-template.md format with:
   - Visual Identity (colors with hex, typography, imagery style)
   - Verbal Identity (voice traits, tone, vocabulary)
   - Core Principles (always/never patterns)
   - Brand Depth sections:
     - Aaker Personality scores (0-5) with evidence per dimension
     - Color Profile (harmony type, temperature, saturation)
     - Emotional Profile (emotion words, visual mood)
     - Spatial & Surface Profile (spacing, radius, shadows, density)
     - Brand Maturity (growing/established/iconic)"
   ```

6. **Read agent results from file**
   The agent writes its findings to `brand-analysis-results.md` in the brand project root. Read this file to get the structured brand elements.

   **Fallback:** If the agent resume fails (concurrency error, API issue), the file still exists. Read it directly — don't depend on the agent's return message.

   After successfully generating brand-philosophy.md, delete `brand-analysis-results.md` — it's an intermediate artifact.

7. **Copy brand assets to assets/ folder**
   - Copy logo files from `input/logos/` to `assets/`
   - **Logo format requirement**: reportlab requires PNG or JPG (not SVG)
     - If logo is SVG: Convert to PNG using `cairosvg` and save as PNG
     - If logo is PNG or JPG: Copy directly
     - Always store the final PNG/JPG path in brand-philosophy.md
   - If multiple logos found, ask user which is the primary logo
   - Record the primary logo path in brand-philosophy.md (must be .png or .jpg)
   - Copy font files from `input/fonts/` to `assets/fonts/`
   - Record font file paths in brand-philosophy.md typography section

   **SVG to PNG conversion:**
   ```python
   import cairosvg
   cairosvg.svg2png(
       url="input/logos/logo.svg",
       write_to="assets/logo.png",
       output_width=800  # Scale up for crisp rendering
   )
   ```

8. **Generate brand-philosophy.md**
   Use `references/brand-philosophy-template.md` as template.
   Fill in agent results + `logo_path` from step 7.

9. **Present for review**
   Show generated brand philosophy.
   Highlight the Aaker personality scores specifically — these are the most subjective part:
   > "Here are the personality scores I derived from your brand assets. Do these feel right?"
   Show the Aaker table and primary/secondary dimensions.
   Ask: "Does this capture your brand accurately? What would you like to adjust?"

10. **Refine if needed**
    Update brand-philosophy.md based on feedback. Repeat until confirmed.

11. **Suggest next steps**
    Once user confirms, explain what to do next:

    > "Your brand philosophy is ready! Here's what you can do next:
    >
    > **Option A: Create a template first (recommended)**
    > Templates make future content creation faster and more consistent.
    > - `/template-presentation` - create a reusable presentation structure
    > - `/template-carousel` - create a reusable carousel structure
    >
    > **Option B: Jump straight to content**
    > If you need something now, skip templates and create directly.
    > - `/presentation` or `/presentation-quick`
    > - `/carousel` or `/carousel-quick`
    >
    > What would you like to do?"

## Output

- Updated: `brand-philosophy.md` with extracted brand elements
- User confirmation of accuracy
- Clear guidance on next steps

## Font Detection from Websites

When analyzing a website, the brand-analyst agent should:

1. **Identify fonts used** - Look for:
   - CSS `font-family` declarations
   - Google Fonts, Adobe Fonts, or other web font services
   - Custom @font-face declarations

2. **Report font names** - Include in analysis:
   - Heading font(s)
   - Body font(s)
   - Any accent/special fonts

3. **Auto-download Google Fonts** - If Google Fonts detected:
   - Download TTF files directly using the Google Fonts API:
     ```bash
     # Download font family (all weights)
     mkdir -p "{PROJECT_PATH}/assets/fonts"
     curl -L "https://fonts.google.com/download?family={Font+Name}" -o /tmp/{font-name}.zip
     unzip -o /tmp/{font-name}.zip -d /tmp/{font-name}/
     cp /tmp/{font-name}/*.ttf "{PROJECT_PATH}/assets/fonts/" 2>/dev/null
     cp /tmp/{font-name}/static/*.ttf "{PROJECT_PATH}/assets/fonts/" 2>/dev/null
     ```
   - Report what was downloaded:
     > "Downloaded brand fonts to `assets/fonts/`:
     > - **Heading**: {font name} ({N} weights)
     > - **Body**: {font name} ({N} weights)
     >
     > These will be used automatically in presentations, carousels, and infographics."

4. **Non-Google fonts** - If Adobe Fonts, custom @font-face, or proprietary:
   > "I detected these fonts but cannot auto-download them:
   > - **Heading**: {font name} ({source})
   > - **Body**: {font name} ({source})
   >
   > Please add the TTF/OTF files to `input/fonts/` manually.
   > Without brand fonts, generated content will fall back to system fonts."

5. **Verify fonts were loaded** - After extraction, check:
   ```bash
   ls "{PROJECT_PATH}/assets/fonts/"/*.ttf "{PROJECT_PATH}/assets/fonts/"/*.otf 2>/dev/null
   ```
   - If no font files found: warn prominently
     > "⚠️ No brand fonts in assets/fonts/. Generated content will use system font fallbacks.
     > Run `/brand-assets` to add fonts, or download from Google Fonts."

## Notes

- All source types are optional - use whatever the user provides
- Multiple sources produce richer, more accurate brand philosophy
- When sources conflict, ask user to clarify preference
- Font files in `input/fonts/` are automatically used for visual content generation
