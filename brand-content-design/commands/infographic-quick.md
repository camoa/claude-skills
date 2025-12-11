---
description: Create an infographic quickly with minimal questions
allowed-tools: Bash, Read, Write, Glob, AskUserQuestion
---

# Infographic Quick Command

Create an infographic with minimal questions - just template and content.

## Prerequisites

- Must be in a brand project folder (contains brand-philosophy.md)
- Must have at least one infographic template (run `/template-infographic` first)

## Workflow

0. **Ensure Node.js dependencies are installed**
   - Set `SKILL_PATH` = path to `skills/infographic-generator/` in the plugin
   - Check if `{SKILL_PATH}/node_modules` exists
   - If not, run:
     ```bash
     cd {SKILL_PATH} && npm install
     ```
   - Wait for installation to complete before proceeding

1. **Find project and templates**
   - Check `./brand-philosophy.md`, then `../brand-philosophy.md`, then `find . -maxdepth 2 -name "brand-philosophy.md"`
   - **Set PROJECT_PATH** = directory containing brand-philosophy.md
   - Run `find {PROJECT_PATH}/templates/infographics -name "config.json" 2>/dev/null`
   - If no project found: Tell user to run `/brand-init` first and stop
   - If no templates found: Tell user to run `/template-infographic` first and stop

2. **Single question for template**
   Use AskUserQuestion:
   - Header: "Template"
   - Question: "Which template?"
   - Options: List each template by name (include type: sequence, list, compare, etc.)

3. **Ask for content**
   Ask: "Paste your content for this infographic (title, items, etc.):"

   **Tip:** Mention `/outline infographic-{template}` if they need help preparing content.

4. **Load template configuration**
   - Read `{PROJECT_PATH}/templates/infographics/{template-name}/config.json`
   - Read `{PROJECT_PATH}/templates/infographics/{template-name}/outline-template.md`
   - Note the data structure requirements
   - **Check if illustrated template** (name ends in `-illus`)

5. **Handle illustrated templates** (skip if not `-illus`)
   If template is illustrated:
   - Warn: "This template requires SVG illustrations for each item."
   - Ask: "Do you have SVGs ready? (yes/no)"
   - If no: Suggest `/infographic` for guided illustration workflow, or continue with placeholders
   - If yes: Ask for folder path containing SVGs

6. **Map content to data structure**
   - Parse the pasted content
   - Map to template's JSON structure:
     ```json
     {
       "title": "...",
       "desc": "...",
       "items": [
         { "label": "...", "desc": "..." }
       ]
     }
     ```
   - Fill any gaps with sensible defaults
   - Keep text concise (1-2 words for labels, short phrases for descriptions)

7. **Infographic name**
   Ask: "What name for this infographic?"
   - Suggest a name derived from the content title (e.g., if title is "Our Services" suggest "our-services")
   - Accept user input or "auto" to use the suggestion
   - Sanitize: lowercase, hyphens, no special chars

8. **Generate infographic**
   Run the Node.js generator with default background (spotlight-dots):
   ```bash
   cd {PLUGIN_PATH}/skills/infographic-generator
   node generate.js \
     --config "{PROJECT_PATH}/templates/infographics/{template-name}/config.json" \
     --data '{data-json}' \
     --background "spotlight-dots" \
     --output "{OUTPUT_PATH}/{infographic-name}.png"
   ```

9. **Save outputs**
   Create folder: `{PROJECT_PATH}/infographics/{YYYY-MM-DD}-{infographic-name}/`
   Save:
   - `{infographic-name}.png`
   - `data.json` - The content data used

10. **Show result**
    Display:
   - Output location
   - "View: open {filename}.png"
   - "Use `/infographic` for more control over background and format"

## Output

- Created: `infographics/{date}-{name}/{name}.png`

## Notes

- This is the fast path - paste content, get infographic
- For step-by-step control (background, format), use `/infographic` instead
- For help preparing content, use `/outline infographic-{template}` first
- For creating new templates, use `/template-infographic`

## Text Guidelines

To avoid text overlap in the generated infographic:
- **Labels**: Keep to 1-2 words max
- **Descriptions**: Keep to 2-4 words
- If content is longer, it will be truncated or may overlap

Example good content:
```
Title: Our Services
Subtitle: What we offer

- Cloud: Infrastructure design
- Security: Vulnerability audit
- Analytics: Business intelligence
- DevOps: CI/CD pipelines
```
