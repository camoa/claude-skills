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

1. **Check for template argument**
   - If `$ARGUMENTS` provided, use as template name
   - If not provided, continue to step 2

2. **Find all available templates**
   - Glob `templates/presentations/*/template.md` for presentation templates
   - Glob `templates/carousels/*/template.md` for carousel templates
   - Build list with type indicator: "presentation: {name}" or "carousel: {name}"

3. **Ask user to select template**
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
   Create `outline-prompt.txt` in the template folder:

   **For presentations:**
   ```
   I need help structuring my presentation content. I have a template with the following slide structure:

   {List each slide with type and purpose}

   Here's my raw content/ideas:

   [PASTE YOUR CONTENT HERE]

   Please help me organize this content into the following outline format. For each slide, extract or suggest the most relevant content from what I provided. If I'm missing content for a slide, suggest what I should include.

   OUTPUT FORMAT:

   ## Slide 1: {Type}
   - {element}: {filled content}

   ## Slide 2: {Type}
   - {element}: {filled content}

   ...

   Keep the content concise and impactful. Each slide should have a single clear message.
   ```

   **For carousels:**
   ```
   I need help structuring my carousel content. I have a template with the following card structure:

   {List each card with type and purpose}

   Here's my raw content/ideas:

   [PASTE YOUR CONTENT HERE]

   Please help me organize this content into the following outline format. For each card, extract or suggest the most relevant content from what I provided. If I'm missing content for a card, suggest what I should include.

   OUTPUT FORMAT:

   ## Card 1: {Type}
   - {element}: {filled content}

   ## Card 2: {Type}
   - {element}: {filled content}

   ...

   Keep the content concise and scroll-stopping. Each card should have a single clear message that works on mobile.
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
