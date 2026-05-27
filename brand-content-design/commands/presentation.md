---
description: Create a presentation using an existing template (detailed, guided mode). Use when user says "create presentation", "make slides", "presentation from template", "guided presentation".
allowed-tools: Read, Write, Glob, AskUserQuestion, Skill
---

# Presentation Command (Detailed Mode)

Create a presentation from an existing template with user-provided content.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)
- Must have at least one presentation template (run `/template-presentation` first)

## Workflow

1. **Find project (PROJECT_PATH)**
   Search in this order:
   - Check `./brand-philosophy.md` (current directory)
   - Check `../brand-philosophy.md` (parent directory)
   - Run `find . -maxdepth 2 -name "brand-philosophy.md"` to find nearby
   - If multiple found, ask user which project
   - If none found, tell user to run `/brand-init` first and stop
   - **Set PROJECT_PATH** = directory containing brand-philosophy.md
   - Load brand-philosophy.md

2. **Find available templates**
   - Run `find {PROJECT_PATH}/templates/presentations -name "template.md" 2>/dev/null`
   - Parse results to get template names (parent folder name)
   - If none found: Tell user to run `/template-presentation` first and stop

3. **Ask template selection**
   Use AskUserQuestion:
   - Header: "Template"
   - Question: "Which template would you like to use?"
   - Options: List each template by name

4. **Load template files**
   - Read `{PROJECT_PATH}/templates/presentations/{template-name}/template.md`
   - Read `{PROJECT_PATH}/templates/presentations/{template-name}/canvas-philosophy.md`
   - Read plugin `references/presentations-guide.md` for Zen principles
   - Read plugin `references/style-constraints.md` for style enforcement
   - Read plugin `references/slide-composition-rules.md` for composition defaults (fallback if template lacks Composition Rules)
   - Note the slide structure (types, purposes, content elements)
   - **Identify the template's style** from canvas-philosophy.md (look for "Style:" at bottom or enforcement block)

5. **Ask for content**
   Use AskUserQuestion:
   - Header: "Content"
   - Question: "How would you like to provide content?"
   - Options:
     - "Paste outline" - I have a prepared outline (from `/outline` or elsewhere)
     - "Enter slide-by-slide" - Guide me through each slide
     - "Paste all content" - I'll paste raw content for you to organize

6. **Collect content based on selection**

   **If "Paste outline":**
   - Ask user to paste their outline
   - Parse and validate against template structure
   - Show mapping: "Slide 1 (Title) → {their content}"
   - Ask to confirm or adjust

   **If "Enter slide-by-slide":**
   - For each slide in template structure:
     - Show: "Slide {n}: {type} - {purpose}"
     - Show: "Content needed: {elements from template}"
     - Ask user for content
     - Confirm before next slide

   **If "Paste all content":**
   - Ask user to paste their raw content
   - Analyze and map to template slides
   - Show proposed mapping
   - Ask to confirm or adjust

7. **Ask presentation details**
   - "What is the title of this presentation?"
   - "Any subtitle or date to include?"

8. **Generate presentation PDF**
   Use the **visual-content** skill:
   - **IMPORTANT:** Use the template's existing canvas-philosophy.md as the design philosophy - do NOT create a new philosophy
   - Pass the canvas-philosophy.md content directly to visual-content as the design direction
   - Provide the presentations-guide.md principles (Zen, visual hierarchy, etc.)
   - Provide brand-philosophy.md for colors, fonts, logo
   - **Load brand assets**:
     - Read logo file from brand-philosophy.md Brand Assets section
     - If logo is SVG, convert to PNG first (visual-content handles this)
     - Load fonts from `{PROJECT_PATH}/assets/fonts/` if present

   **ENFORCE STYLE CONSTRAINTS based on template's style:**

   - Look up the template's style in `style-constraints.md`
   - Copy the exact **Enforcement Block** for that style
   - Pass it to visual-content as hard constraints

   The enforcement block format is:
   ```
   STYLE: [Style Name] ([Family])
   - HARD LIMIT: Max X words/slide. Truncate if exceeded.
   - HARD LIMIT: Min X% whitespace.
   - HARD LIMIT: Max X elements.
   - Layout: [Layout directive]
   - Typography: [Typography directive]
   - Color: [Color directive]
   - NEVER: [Anti-patterns]
   ```

   **All 18 styles have enforcement blocks in style-constraints.md:**
   - Japanese Zen: Minimal, Dramatic, Organic, Wabi-Sabi, Shibui, Iki, Ma
   - Scandinavian: Hygge, Lagom
   - European: Swiss, Memphis
   - East Asian: Yeo-baek, Feng Shui
   - Contemporary Professional: Tech-Modern, Data-Forward, Corporate-Confident, Pitch-Velocity, Narrative-Clean

   **PASS COMPOSITION RULES to visual-content:**

   - If canvas-philosophy.md has a "## Composition Rules" section → use it (already style-adapted)
   - If canvas-philosophy.md LACKS Composition Rules (legacy template) → load defaults from `references/slide-composition-rules.md` and apply the style's modifiers from Section 3
   - For each slide: identify type → look up blueprint → apply composition rules → then generate

   - For each slide in the template structure:
     - Describe the slide type and purpose
     - Provide the user's content for that slide
     - Reference the sample.pdf for visual style (but generate fresh content)
   - Request output as multi-page PDF at 1920x1080 (16:9)
   - Save to workspace

9. **Convert PDF to PPTX**
   Use the **pptx** skill:
   - Use the "Creating without a template" (html2pptx) workflow
   - Match the PDF design exactly
   - Create editable text boxes for each content element
   - Incorporate logo from brand-philosophy.md assets
   - Save as PPTX

10. **Save local outputs**
    Create folder: `{PROJECT_PATH}/presentations/{YYYY-MM-DD}-{topic-slug}/`
    Save:
    - `{topic-slug}.pdf`
    - `{topic-slug}.pptx`

    The folder created here is `LOCAL_DIR` for the next step.

11. **Render Google Slides deck (Drive)**

    Reference: `references/slides-batchupdate-authoring.md` (sibling
    `slides_llm_authoring` subtask) — load it from the plugin's `references/`
    directory. It documents how to translate the PDF + reportlab Python
    source into a Slides API `batchUpdate` request list while obeying the
    canvas-philosophy.md design rules.

    **11a. Detect prior render.** Run the shell:
    ```
    python -m slides.cli replace_render <<EOF
    ...
    EOF
    ```
    BEFORE calling `replace_render`, check if `LOCAL_DIR` already contains a
    `*.slides.url` pointer file. If it does, use AskUserQuestion:
    - Header: "Existing Slides deck"
    - Question: "A Slides deck already exists in Drive for this
      presentation. What would you like to do?"
    - Options:
      - **Trash and recreate** (default) — soft-delete the old Drive folder
        (recoverable from Drive Trash for 30 days), then create fresh
      - **Keep alongside** — leave the old folder, create a new
        `-v2`/`-v3`/... versioned sibling
      - **Cancel** — stop, do not render Slides
    Map: "Trash and recreate" → `"strategy": "trash"`,
         "Keep alongside" → `"strategy": "keep_alongside"`,
         "Cancel" → skip step 11 entirely (the PDF + PPTX outputs already
         exist).

    **11b. Author the batchUpdate JSON.** Following the authoring guide:
    - Use the freshly rendered `{topic-slug}.pdf` and the reportlab Python
      source that produced it as visual ground truth
    - Apply the template's canvas-philosophy.md design rules (palette,
      spacing, typography)
    - Produce a `requests: [...]` list (Slides API `batchUpdate` payload)
    - Persist the payload to `{LOCAL_DIR}/{topic-slug}.slides.batchupdate.json`
      so the diff-against-PDF iteration loop is available later

    **11c. Create the deck.** Shell out:
    ```
    echo '{"title": "{presentation-title}"}' \
      | python -m slides.cli create_deck
    ```
    Capture `deck_id` from the JSON response.

    **11d. Apply the layout.** Shell out:
    ```
    echo '{"deck_id": "...", "requests": [...]}' \
      | python -m slides.cli apply_batch_update
    ```
    Use the persisted `{topic-slug}.slides.batchupdate.json` as input.

    **11e. Mirror to Drive.** Shell out:
    ```
    echo '{
      "brand": "{BRAND_NAME}",
      "render_slug": "{YYYY-MM-DD}-{topic-slug}",
      "kind": "presentations",
      "local_dir": "{LOCAL_DIR}",
      "deck_id": "{deck_id}",
      "pdf_path": "{LOCAL_DIR}/{topic-slug}.pdf",
      "outline_path": "{LOCAL_DIR}/outline.md",
      "strategy": "trash"
    }' | python -m slides.cli replace_render
    ```
    Pass the user's strategy choice from 11a. The runner:
    - Trashes the existing render folder (or picks a `-vN` slug if keeping)
    - Creates `brand-content/{brand}/presentations/{date}-{slug}/` in Drive
      (idempotent — intermediate folders are reused)
    - Reparents the deck into that folder
    - Uploads `{topic-slug}.pdf` and `outline.md` into the same folder
    - Writes `{LOCAL_DIR}/{topic-slug}.slides.url` (JSON pointer file
      mapping local → Drive ids/urls)
    - Returns `{folder_id, folder_url, deck_id, deck_url, ...}`

    Credentials come from environment vars per
    `references/slides-credentials.md` (`BCD_SLIDES_*`). Optional
    `BRAND_CONTENT_DRIVE_ROOT_ID` overrides where `brand-content/` lives in
    Drive (defaults to My Drive root).

    **11f. Save outline locally if missing.** If `{LOCAL_DIR}/outline.md`
    does not exist (e.g. user pasted content slide-by-slide), write a
    minimal outline.md from the collected content before step 11e so the
    Drive mirror has something to upload.

12. **Present results**
    Show:
    - Local output location: `{LOCAL_DIR}/`
    - Local file paths: `{topic-slug}.pdf`, `{topic-slug}.pptx`,
      `{topic-slug}.slides.batchupdate.json`, `{topic-slug}.slides.url`
    - Drive folder URL (from step 11e)
    - Slides deck URL (from step 11e)
    - Preview of first slide
    - "Open the Slides deck for live editing, or the PPTX for offline edits"

## Output

- Created: `presentations/{date}-{name}/{name}.pdf`
- Created: `presentations/{date}-{name}/{name}.pptx` (transitional — PPTX is
  on the deprecation path)
- Created: `presentations/{date}-{name}/{name}.slides.batchupdate.json` (NEW)
- Created: `presentations/{date}-{name}/{name}.slides.url` (NEW — local
  pointer file mapping to Drive)
- Created in Drive (NEW):
  `brand-content/{brand}/presentations/{date}-{name}/` containing
  `{name}.pdf`, `outline.md`, and the live Slides deck

## Notes

- This command requires an existing template - use `/template-presentation` to create one first
- For best results, use `/outline <template>` to prepare content that matches the template structure
- The PDF is the source of truth - PPTX is generated from it for editability
- visual-content ensures brand consistency and Zen principles are followed
