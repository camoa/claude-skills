# Infographic Data Prompt Template

This template is used to generate prompts that help users structure their data for infographic creation. The prompt is designed to be used with any AI assistant.

## Template Variables

- `{TEMPLATE_NAME}` - The ANTV template name (e.g., "sequence-timeline-simple-illus")
- `{TEMPLATE_TYPE}` - The type of infographic (timeline, list, comparison, chart, hierarchy)
- `{ITEM_COUNT}` - Number of items in the infographic
- `{HAS_ILLUSTRATIONS}` - Whether the template requires illustrations
- `{ASSETS_PATH}` - Path where user should place illustration files

---

## Generated Prompt Format

```
I need help structuring my content for an infographic. I have a specific template that requires data in a particular format.

## TEMPLATE INFORMATION

**Template**: {TEMPLATE_NAME}
**Type**: {TEMPLATE_TYPE}
**Items**: {ITEM_COUNT} items required
**Illustrations**: {HAS_ILLUSTRATIONS ? "Yes - each item needs an illustration" : "No illustrations needed"}

## DATA STRUCTURE

The infographic needs data in this JSON format:

```json
{
  "title": "Main Title (required)",
  "desc": "Subtitle or description (optional)",
  "items": [
    {
      "label": "Item title (required)",
      "desc": "Item description (optional)",
      "value": 123,  // Only for chart templates
      "icon": "icon:name",  // Optional icon from Lucide library
      "illus": "illus:filename"  // For illustration templates
    }
  ]
}
```

### Field Guidelines

- **title**: Clear, concise main heading (3-7 words)
- **desc**: Supporting context or subtitle (10-20 words max)
- **item.label**: Short, descriptive title for each step/item (2-5 words)
- **item.desc**: Brief explanation (10-30 words)
- **item.value**: Numeric data (charts only)
- **item.icon**: Icon reference like "icon:rocket", "icon:users" (see Lucide icons)
- **item.illus**: Illustration filename reference "illus:step-1"

## MY RAW CONTENT

[PASTE YOUR CONTENT HERE - meeting notes, bullet points, research data, etc.]

## INSTRUCTIONS

Please transform my content into the JSON format above. For each item:

1. Extract or create a clear, concise label (2-5 words)
2. Write a brief description if relevant content exists
3. If this is a chart, extract or estimate numeric values
4. Assign illustration filenames in order: step-1, step-2, step-3, etc.
5. Suggest appropriate icons from Lucide library (rocket, users, chart-bar, etc.)

{HAS_ILLUSTRATIONS ? `
## ILLUSTRATION REQUIREMENTS

After you provide the JSON, I will need to create illustrations for each item.

**Required illustrations:**
- step-1.svg (or .png/.jpg) - For item 1
- step-2.svg - For item 2
- ... and so on

**Place files in:** {ASSETS_PATH}

Please also suggest what each illustration should depict based on the content.
` : ""}

## OUTPUT FORMAT

Provide the complete JSON data structure, then list any illustration files needed with descriptions of what each should contain.

---

**JSON Output:**

```json
{
  "title": "...",
  "desc": "...",
  "items": [...]
}
```

**Illustration Requirements:** (if applicable)
1. step-1.svg - [description of what this should show]
2. step-2.svg - [description]
...
```

---

## Template-Specific Variations

### Timeline Templates (sequence-timeline-*)
- Items represent chronological steps/phases
- Labels should be short step names or dates
- Descriptions explain what happens at each step

### List Templates (list-row-*, list-column-*, list-grid-*)
- Items are parallel concepts, not sequential
- Each item should be self-contained
- Good for features, benefits, team members

### Comparison Templates (compare-*)
- Items often have sub-items (children)
- Structure varies by comparison type
- May need "children" array for nested data

### Chart Templates (chart-*)
- Requires "value" field for each item
- Labels are category names
- Descriptions are optional

### Hierarchy Templates (hierarchy-*)
- Uses nested "children" arrays
- Represents organizational or tree structures
- Each level needs label/desc
