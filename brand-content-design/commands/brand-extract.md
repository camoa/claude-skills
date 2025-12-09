---
description: Extract brand elements from multiple sources and generate brand-philosophy.md
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

   Summarize what was found (e.g., "I found 3 screenshots, 1 PDF, and 2 logo files.")

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
   - Core Principles (always/never patterns)"
   ```

6. **Receive and review agent results**
   The brand-analyst agent returns structured brand elements.

   If user also provided verbal description or pasted guidelines that weren't
   sent to agent, merge those insights with agent results.

7. **Synthesize final brand elements**
   Combine agent analysis with any additional user input into:

   **Visual Identity:**
   - Colors (3-5 dominant colors with hex codes)
   - Typography (font families or style descriptions)
   - Imagery style (patterns, photography style, illustration approach)

   **Verbal Identity:**
   - Voice (3 personality traits)
   - Tone (how voice adapts to context)
   - Key vocabulary (signature words/phrases)

   **Core Principles:**
   - Always (consistent patterns observed)
   - Never (things consistently avoided)

8. **Copy brand assets to assets/ folder**
   - Copy logo files from `input/logos/` to `assets/`
   - Prefer vector formats (SVG) over raster when available
   - If multiple logos found, ask user which is the primary logo
   - Record the primary logo path in brand-philosophy.md

9. **Generate brand-philosophy.md**
   Use plugin `references/brand-philosophy-template.md` as template
   Fill in all extracted values including:
   - `logo_path`: Path to primary logo in assets/ (e.g., `assets/logo.svg`)
   Write to brand-philosophy.md (overwrite placeholder)

10. **Present for review**
    Show the generated brand philosophy to user
    Ask: "Does this capture your brand accurately? What would you like to adjust?"

11. **Refine if needed**
    If user provides feedback, update brand-philosophy.md
    Repeat until user confirms

12. **Suggest next steps**
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

## Notes

- All source types are optional - use whatever the user provides
- Multiple sources produce richer, more accurate brand philosophy
- When sources conflict, ask user to clarify preference
