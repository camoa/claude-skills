/**
 * Prompt Generator Module
 * Generates data prompts for external AI assistants to format user content
 */

/**
 * Template categories and their characteristics
 */
const TEMPLATE_INFO = {
  // Timeline/Sequence templates
  'sequence-timeline-simple': { type: 'timeline', hasIllustrations: false, defaultItems: 5 },
  'sequence-timeline-simple-illus': { type: 'timeline', hasIllustrations: true, defaultItems: 5 },
  'sequence-steps-simple': { type: 'steps', hasIllustrations: false, defaultItems: 4 },
  'sequence-steps-simple-illus': { type: 'steps', hasIllustrations: true, defaultItems: 4 },
  'sequence-zigzag-steps-underline-text': { type: 'steps', hasIllustrations: false, defaultItems: 4 },
  'sequence-roadmap-vertical-badge-card': { type: 'roadmap', hasIllustrations: false, defaultItems: 5 },
  'sequence-color-snake-steps-simple-illus': { type: 'steps', hasIllustrations: true, defaultItems: 4 },

  // List templates
  'list-row-simple': { type: 'list', hasIllustrations: false, defaultItems: 4 },
  'list-row-simple-illus': { type: 'list', hasIllustrations: true, defaultItems: 4 },
  'list-column-simple': { type: 'list', hasIllustrations: false, defaultItems: 3 },
  'list-column-simple-illus': { type: 'list', hasIllustrations: true, defaultItems: 3 },
  'list-grid-simple': { type: 'grid', hasIllustrations: false, defaultItems: 6 },
  'list-grid-simple-illus': { type: 'grid', hasIllustrations: true, defaultItems: 6 },
  'list-row-horizontal-icon-line': { type: 'list', hasIllustrations: false, hasIcons: true, defaultItems: 4 },

  // Comparison templates
  'compare-binary-horizontal-badge-card-vs': { type: 'comparison', hasIllustrations: false, defaultItems: 2 },
  'compare-swot': { type: 'swot', hasIllustrations: false, defaultItems: 4 },

  // Chart templates
  'chart-column-simple': { type: 'chart', hasIllustrations: false, defaultItems: 4 },
  'chart-pie-simple': { type: 'chart', hasIllustrations: false, defaultItems: 4 },

  // Hierarchy templates
  'hierarchy-tree-simple-pill': { type: 'hierarchy', hasIllustrations: false, defaultItems: 3 },

  // Quadrant templates
  'quadrant-simple': { type: 'quadrant', hasIllustrations: false, defaultItems: 4 },
  'quadrant-simple-illus': { type: 'quadrant', hasIllustrations: true, defaultItems: 4 }
};

/**
 * Get template information
 * @param {string} templateName - ANTV template name
 * @returns {Object|null} Template info or null if unknown
 */
function getTemplateInfo(templateName) {
  return TEMPLATE_INFO[templateName] || null;
}

/**
 * Get all available templates
 * @returns {string[]} Array of template names
 */
function getAvailableTemplates() {
  return Object.keys(TEMPLATE_INFO);
}

/**
 * Get templates by type
 * @param {string} type - Template type (timeline, list, chart, etc.)
 * @returns {string[]} Array of matching template names
 */
function getTemplatesByType(type) {
  return Object.entries(TEMPLATE_INFO)
    .filter(([_, info]) => info.type === type)
    .map(([name]) => name);
}

/**
 * Get templates that require illustrations
 * @returns {string[]} Array of template names
 */
function getIllustrationTemplates() {
  return Object.entries(TEMPLATE_INFO)
    .filter(([_, info]) => info.hasIllustrations)
    .map(([name]) => name);
}

/**
 * Generate a data prompt for a specific template
 * @param {Object} options - Generation options
 * @param {string} options.templateName - ANTV template name
 * @param {number} options.itemCount - Number of items (optional)
 * @param {string} options.assetsPath - Path for illustration assets
 * @returns {string} Generated prompt text
 */
function generateDataPrompt(options) {
  const { templateName, itemCount, assetsPath = './assets/infographics' } = options;

  const info = getTemplateInfo(templateName);
  if (!info) {
    throw new Error(`Unknown template: ${templateName}. Use getAvailableTemplates() to see options.`);
  }

  const items = itemCount || info.defaultItems;
  const hasIllus = info.hasIllustrations;
  const hasIcons = info.hasIcons || false;

  let prompt = `I need help structuring my content for an infographic. I have a specific template that requires data in a particular format.

## TEMPLATE INFORMATION

**Template**: ${templateName}
**Type**: ${info.type}
**Items**: ${items} items expected
**Illustrations**: ${hasIllus ? 'Yes - each item needs an illustration' : 'No illustrations needed'}
${hasIcons ? '**Icons**: Yes - each item can have an icon' : ''}

## DATA STRUCTURE

The infographic needs data in this JSON format:

\`\`\`json
{
  "title": "Main Title",
  "desc": "Subtitle or description",
  "items": [
${generateItemExamples(info.type, hasIllus, hasIcons)}
  ]
}
\`\`\`

### Field Guidelines

- **title**: Clear, concise main heading (3-7 words)
- **desc**: Supporting context or subtitle (10-20 words max)
- **item.label**: Short, descriptive title for each ${info.type === 'timeline' ? 'phase/step' : 'item'} (2-5 words)
- **item.desc**: Brief explanation (10-30 words)`;

  if (info.type === 'chart') {
    prompt += `
- **item.value**: Numeric data value (required for charts)`;
  }

  if (hasIcons) {
    prompt += `
- **item.icon**: Icon reference like "icon:rocket", "icon:users" (Lucide icons)`;
  }

  if (hasIllus) {
    prompt += `
- **item.illus**: Illustration filename "illus:step-1", "illus:step-2", etc.`;
  }

  prompt += `

## MY RAW CONTENT

[PASTE YOUR CONTENT HERE - meeting notes, bullet points, research data, project plan, etc.]

## INSTRUCTIONS

Please transform my content into the JSON format above. For each item:

1. Extract or create a clear, concise label (2-5 words)
2. Write a brief description based on available content
${info.type === 'chart' ? '3. Extract or estimate numeric values for each item\n' : ''}${hasIllus ? `${info.type === 'chart' ? '4' : '3'}. Assign illustration filenames: step-1, step-2, step-3, etc.\n` : ''}${hasIcons ? `${hasIllus ? (info.type === 'chart' ? '5' : '4') : '3'}. Suggest appropriate Lucide icons (rocket, users, chart-bar, target, lightbulb, etc.)\n` : ''}`;

  if (hasIllus) {
    prompt += `
## ILLUSTRATION REQUIREMENTS

After providing the JSON, I need to create ${items} illustrations.

**Required illustration files:**
${Array.from({ length: items }, (_, i) => `- step-${i + 1}.svg (or .png/.jpg)`).join('\n')}

**Place files in:** \`${assetsPath}\`

Please also describe what each illustration should depict based on the content.
`;
  }

  prompt += `
## OUTPUT FORMAT

Provide the complete JSON data structure:

\`\`\`json
{
  "title": "Your suggested title",
  "desc": "Your suggested subtitle",
  "items": [
    // ... all items with proper structure
  ]
}
\`\`\`
`;

  if (hasIllus) {
    prompt += `
**Illustration Descriptions:**
1. step-1.svg - [Describe what this illustration should show]
2. step-2.svg - [Description]
... and so on for all ${items} illustrations
`;
  }

  return prompt;
}

/**
 * Generate example items for the prompt
 */
function generateItemExamples(type, hasIllus, hasIcons) {
  const base = `    {
      "label": "Item Title",
      "desc": "Brief description of this item"`;

  let extra = '';
  if (type === 'chart') {
    extra += `,
      "value": 100`;
  }
  if (hasIcons) {
    extra += `,
      "icon": "icon:rocket"`;
  }
  if (hasIllus) {
    extra += `,
      "illus": "illus:step-1"`;
  }

  return base + extra + `
    },
    // ... more items`;
}

/**
 * Generate the JSON schema for validation
 * @param {string} templateName - Template name
 * @returns {Object} JSON schema
 */
function generateJsonSchema(templateName) {
  const info = getTemplateInfo(templateName);
  if (!info) return null;

  const itemProperties = {
    label: { type: 'string', description: 'Item title (2-5 words)' },
    desc: { type: 'string', description: 'Item description (10-30 words)' }
  };

  if (info.type === 'chart') {
    itemProperties.value = { type: 'number', description: 'Numeric value' };
  }

  if (info.hasIcons) {
    itemProperties.icon = { type: 'string', pattern: '^icon:', description: 'Lucide icon reference' };
  }

  if (info.hasIllustrations) {
    itemProperties.illus = { type: 'string', pattern: '^illus:', description: 'Illustration filename' };
  }

  return {
    type: 'object',
    required: ['title', 'items'],
    properties: {
      title: { type: 'string', description: 'Main title' },
      desc: { type: 'string', description: 'Subtitle' },
      items: {
        type: 'array',
        minItems: 1,
        items: {
          type: 'object',
          required: ['label'],
          properties: itemProperties
        }
      }
    }
  };
}

module.exports = {
  getTemplateInfo,
  getAvailableTemplates,
  getTemplatesByType,
  getIllustrationTemplates,
  generateDataPrompt,
  generateJsonSchema,
  TEMPLATE_INFO
};
