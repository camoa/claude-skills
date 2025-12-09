---
description: Generate an outline template and prompt for a presentation or carousel template
allowed-tools: Read, Write, Glob, AskUserQuestion
argument-hint: <template-name>
---

# Outline Command

Generate a structured outline template and AI prompt for a specific presentation or carousel template.

## Purpose

Help users prepare content that maps perfectly to a template's structure. Users can:
1. Use the outline template as a fill-in-the-blank guide
2. Use the prompt in any AI chat (Claude Projects, etc.) to transform their raw content into the structured outline

## Workflow

1. **Find project (PROJECT_PATH)**
   Search in this order:
   - Check `./brand-philosophy.md` (current directory)
   - Check `../brand-philosophy.md` (parent directory)
   - Run `find . -maxdepth 2 -name "brand-philosophy.md"` to find nearby
   - If multiple found, ask user which project
   - If none found, tell user to run `/brand-init` first and stop
   - **Set PROJECT_PATH** = directory containing brand-philosophy.md

2. **Check for template argument**
   - If `$ARGUMENTS` provided, use as template name
   - If not provided, continue to step 3

3. **Find all available templates**
   - Run `find {PROJECT_PATH}/templates/presentations -name "template.md" 2>/dev/null`
   - Run `find {PROJECT_PATH}/templates/carousels -name "template.md" 2>/dev/null`
   - Build list with type indicator: "presentation: {name}" or "carousel: {name}"

4. **Ask user to select template**
   - If argument was provided, search for it in both presentations and carousels
   - If found in only one location, use that
   - If found in both, ask user which type
   - If not found, show error with available templates
   - If no argument provided, show all templates and ask user to select

4. **Load template structure**
   - Read the template.md file
   - Extract slide/card sequence with:
     - Type (Title, Content, Image, Data, Quote, CTA, Hook, etc.)
     - Purpose of each slide/card
     - Expected content elements

5. **Generate outline template**
   Create `outline-template.md` in the template folder:

   **For presentations:**
   ```markdown
   # Presentation Outline: {Template Name}

   Use this template to structure your content before creating the presentation.
   Fill in each section to match the slide structure.

   ---

   ## Slide 1: {Slide Type}
   **Purpose:** {What this slide should achieve}

   - {Content element 1}: ___
   - {Content element 2}: ___

   ## Slide 2: {Slide Type}
   **Purpose:** {What this slide should achieve}

   - {Content element 1}: ___
   - {Content element 2}: ___

   ...
   ```

   **For carousels:**
   ```markdown
   # Carousel Outline: {Template Name}

   Use this template to structure your content before creating the carousel.
   Fill in each section to match the card structure.

   ---

   ## Card 1: {Card Type}
   **Purpose:** {What this card should achieve}

   - {Content element 1}: ___
   - {Content element 2}: ___

   ## Card 2: {Card Type}
   **Purpose:** {What this card should achieve}

   - {Content element 1}: ___
   - {Content element 2}: ___

   ...
   ```

6. **Generate AI prompt**
   Create `outline-prompt.txt` in the template folder.

   **IMPORTANT**: The prompt must include slide/card type definitions so the external AI understands what content each type needs.

   **For presentations:**
   ```
   I need help structuring my presentation content. I have a template with a specific slide structure.

   ## SLIDE TYPE DEFINITIONS

   Each slide type has specific content requirements:

   - **Title Slide**: Set context, make first impression. Content: title, subtitle, presenter. Words: under 10.
   - **Content Slide**: Convey one key idea. Content: one concept, expressed visually when possible. Words: 10-20 max.
   - **Image Slide**: Visual storytelling, emotional connection. Words: 5-10 (labels or headline only).
   - **Data/Chart Slide**: Communicate ONE insight from data. Content: one chart, one insight. Words: headline + data labels only.
   - **Quote Slide**: Add authority or emphasis. Content: quote text + attribution.
   - **CTA Slide**: Bridge content to action. Content: clear direction, reason to act, easy next step. Words: 10-15.
   - **Transition Slide**: Signal section changes. Content: section title only. Words: 3-5.

   ## MY TEMPLATE STRUCTURE

   {List each slide with type and purpose from template.md}

   ## MY RAW CONTENT

   [PASTE YOUR CONTENT HERE]

   ## INSTRUCTIONS

   Please organize my content into this outline format. For each slide:
   1. Extract or suggest the most relevant content from what I provided
   2. Respect the word limits for each slide type
   3. If I'm missing content for a slide, suggest what I should include
   4. Each slide should have ONE clear message (3-second comprehension test)

   OUTPUT FORMAT:

   ## Slide 1: {Type}
   - {element}: {filled content}

   ## Slide 2: {Type}
   - {element}: {filled content}

   ...
   ```

   **For carousels:**
   ```
   I need help structuring my carousel content. I have a template with a specific card structure.

   ## CARD TYPE DEFINITIONS

   Each card type has specific content requirements (mobile-first, 2-second comprehension):

   - **Hook Card**: Stop the scroll, create curiosity. Content: one compelling promise or question. Words: 5-15.
   - **Content Card**: Deliver value, one idea at a time. Content: one key concept. Words: 10-30.
   - **Data Card**: Share one insight with evidence. Content: one statistic, visualized. Words: 10-20.
   - **Story Card**: Connect emotionally through narrative. Content: one scene or moment. Words: 10-25.
   - **CTA Card**: Drive specific action. Content: clear direction, easy next step. Words: 10-20.

   ## MY TEMPLATE STRUCTURE

   {List each card with type and purpose from template.md}

   ## MY RAW CONTENT

   [PASTE YOUR CONTENT HERE]

   ## INSTRUCTIONS

   Please organize my content into this outline format. For each card:
   1. Extract or suggest the most relevant content from what I provided
   2. Respect the word limits for each card type
   3. If I'm missing content for a card, suggest what I should include
   4. Each card must work on mobile (short, punchy, one clear message)

   OUTPUT FORMAT:

   ## Card 1: {Type}
   - {element}: {filled content}

   ## Card 2: {Type}
   - {element}: {filled content}

   ...
   ```

7. **Save files**
   Save to template folder (`templates/presentations/{name}/` or `templates/carousels/{name}/`):
   - `outline-template.md`
   - `outline-prompt.txt`

8. **Show user the outputs**
   - Display the outline template
   - Display the prompt
   - Explain usage:
     1. Copy the prompt to your Claude Project (or any AI chat)
     2. Paste your raw content where indicated
     3. Get back a structured outline
     4. Use the outline with `/presentation`, `/presentation-quick`, `/carousel`, or `/carousel-quick`

## Output

- Created: `templates/{type}/{name}/outline-template.md`
- Created: `templates/{type}/{name}/outline-prompt.txt`
- Displayed both to user with usage instructions

## Notes

- The outline structure must match the template's slide/card sequence exactly
- Content elements should be specific to each type (e.g., "Hook question" for opening, "3 key benefits" for solution slide/card)
- The prompt should guide users to think about what content fits where
- For carousels, remind users content must work on mobile (short, punchy text)
