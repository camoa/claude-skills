/**
 * Validation Module
 * Validates infographic data and provides user guidance
 */

const path = require('path');
const { validateIllustrations, getIllustrationsDir } = require('./illustrations');
const { getTemplateInfo } = require('./prompt-generator');

/**
 * Validate infographic configuration
 * @param {Object} config - Infographic configuration
 * @returns {Object} Validation result { valid, errors, warnings, guidance }
 */
function validateConfig(config) {
  const errors = [];
  const warnings = [];
  const guidance = [];

  // Check required fields
  if (!config.template) {
    errors.push('Missing required field: template');
  }

  if (!config.data) {
    errors.push('Missing required field: data');
  } else {
    if (!config.data.title) {
      warnings.push('Missing data.title - infographic will have no main title');
    }

    if (!config.data.items || !Array.isArray(config.data.items)) {
      errors.push('Missing or invalid data.items - must be an array');
    } else if (config.data.items.length === 0) {
      errors.push('data.items is empty - infographic needs at least one item');
    }
  }

  // Check template-specific requirements
  if (config.template) {
    const templateInfo = getTemplateInfo(config.template);
    if (!templateInfo) {
      warnings.push(`Unknown template: ${config.template}. Proceeding anyway.`);
    }
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
    guidance
  };
}

/**
 * Validate and check illustrations for a configuration
 * @param {Object} config - Infographic configuration
 * @param {string} illustrationsDir - Path to illustrations folder
 * @returns {Object} Validation result with illustration status
 */
function validateWithIllustrations(config, illustrationsDir) {
  const result = validateConfig(config);

  // Check if template requires illustrations
  const templateInfo = config.template ? getTemplateInfo(config.template) : null;
  const needsIllustrations = templateInfo?.hasIllustrations || false;

  if (!needsIllustrations) {
    return {
      ...result,
      illustrations: {
        required: false,
        status: 'not_required'
      }
    };
  }

  // Extract illustration references from items
  const illustrationRefs = [];
  if (config.data?.items) {
    config.data.items.forEach((item, index) => {
      if (item.illus) {
        // Extract name from 'illus:name' format
        const name = typeof item.illus === 'string' && item.illus.startsWith('illus:')
          ? item.illus.replace('illus:', '')
          : `item-${index + 1}`;
        illustrationRefs.push(name);
      } else {
        // Item missing illus field
        result.warnings.push(`Item ${index + 1} (${item.label || 'unnamed'}) has no illustration`);
        illustrationRefs.push(`step-${index + 1}`); // Default expected name
      }
    });
  }

  // Check if illustrations directory is set
  if (!illustrationsDir) {
    result.guidance.push(
      'To use illustrations, set the illustrationsDir in config or call setIllustrationsDir(path)'
    );
    return {
      ...result,
      illustrations: {
        required: true,
        status: 'no_directory',
        expected: illustrationRefs
      }
    };
  }

  // Validate illustrations exist
  const validation = validateIllustrations(illustrationRefs);

  if (!validation.valid) {
    result.guidance.push(
      `Missing ${validation.missing.length} illustration(s). Please create the following files:`
    );
    validation.missing.forEach(name => {
      result.guidance.push(`  - ${illustrationsDir}/${name}.svg (or .png, .jpg)`);
    });
  }

  return {
    ...result,
    illustrations: {
      required: true,
      status: validation.valid ? 'complete' : 'missing',
      found: validation.found,
      missing: validation.missing,
      directory: illustrationsDir
    }
  };
}

/**
 * Generate user-friendly guidance message
 * @param {Object} validationResult - Result from validateWithIllustrations
 * @returns {string} Formatted guidance message
 */
function formatGuidance(validationResult) {
  const lines = [];

  if (validationResult.errors.length > 0) {
    lines.push('## Errors (must fix)\n');
    validationResult.errors.forEach(err => lines.push(`- ${err}`));
    lines.push('');
  }

  if (validationResult.warnings.length > 0) {
    lines.push('## Warnings\n');
    validationResult.warnings.forEach(warn => lines.push(`- ${warn}`));
    lines.push('');
  }

  if (validationResult.illustrations?.status === 'missing') {
    lines.push('## Missing Illustrations\n');
    lines.push(`Directory: \`${validationResult.illustrations.directory}\`\n`);
    lines.push('**Found:**');
    if (validationResult.illustrations.found.length > 0) {
      validationResult.illustrations.found.forEach(name => lines.push(`- ${name} ✓`));
    } else {
      lines.push('- (none)');
    }
    lines.push('\n**Missing:**');
    validationResult.illustrations.missing.forEach(name => {
      lines.push(`- ${name}.svg (or .png, .jpg)`);
    });
    lines.push('');
  }

  if (validationResult.guidance.length > 0) {
    lines.push('## Next Steps\n');
    validationResult.guidance.forEach(guide => lines.push(guide));
  }

  if (validationResult.valid && validationResult.illustrations?.status !== 'missing') {
    lines.push('## Status: Ready to Generate\n');
    lines.push('All requirements met. You can now generate the infographic.');
  }

  return lines.join('\n');
}

/**
 * Parse JSON data from string (with error handling)
 * @param {string} jsonString - JSON string to parse
 * @returns {Object} { data, error }
 */
function parseJsonData(jsonString) {
  try {
    // Try to extract JSON from markdown code blocks if present
    const jsonMatch = jsonString.match(/```json\s*([\s\S]*?)\s*```/);
    const toParse = jsonMatch ? jsonMatch[1] : jsonString;

    const data = JSON.parse(toParse);
    return { data, error: null };
  } catch (error) {
    return {
      data: null,
      error: `Invalid JSON: ${error.message}`
    };
  }
}

module.exports = {
  validateConfig,
  validateWithIllustrations,
  formatGuidance,
  parseJsonData
};
