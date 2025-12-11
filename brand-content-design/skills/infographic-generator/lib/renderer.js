/**
 * Renderer module - Main entry point
 * Re-exports from focused modules for backward compatibility
 *
 * Architecture (SOLID):
 * - dom-setup.js: DOM environment setup (Single Responsibility)
 * - infographic.js: Infographic creation/cleanup (Single Responsibility)
 * - exporter.js: Export format conversions (Single Responsibility)
 * - illustrations.js: User-provided illustration management (Single Responsibility)
 * - backgrounds.js: Custom background rendering (Single Responsibility)
 */

const { setupDOM, getDOMInstance } = require('./dom-setup');
const { createInfographic, cleanup } = require('./infographic');
const {
  exportToDataURL,
  extractSVG,
  extractSVGBuffer,
  dataURLToBuffer,
  svgToPng
} = require('./exporter');
const {
  setIllustrationsDir,
  getIllustrationsDir,
  checkIllustration,
  listIllustrations,
  loadIllustration,
  validateIllustrations,
  clearCache: clearIllustrationsCache
} = require('./illustrations');

const {
  applyCustomBackground,
  applyLayeredBackground,
  createBackgroundPreset,
  createLayeredPreset,
  getBackgroundPresets,
  getLayeredPresets
} = require('./backgrounds');

const {
  getTemplateInfo,
  getAvailableTemplates,
  getTemplatesByType,
  getIllustrationTemplates,
  generateDataPrompt,
  generateJsonSchema,
  TEMPLATE_INFO
} = require('./prompt-generator');

const {
  validateConfig,
  validateWithIllustrations,
  formatGuidance,
  parseJsonData
} = require('./validation');

module.exports = {
  // DOM setup
  setupDOM,
  getDOMInstance,

  // Infographic creation
  createInfographic,
  cleanup,

  // Export utilities
  exportToDataURL,
  extractSVG,
  extractSVGBuffer,
  dataURLToBuffer,
  svgToPng,

  // Illustrations management
  setIllustrationsDir,
  getIllustrationsDir,
  checkIllustration,
  listIllustrations,
  loadIllustration,
  validateIllustrations,
  clearIllustrationsCache,

  // Custom backgrounds
  applyCustomBackground,
  applyLayeredBackground,
  createBackgroundPreset,
  createLayeredPreset,
  getBackgroundPresets,
  getLayeredPresets,

  // Prompt generation
  getTemplateInfo,
  getAvailableTemplates,
  getTemplatesByType,
  getIllustrationTemplates,
  generateDataPrompt,
  generateJsonSchema,
  TEMPLATE_INFO,

  // Validation
  validateConfig,
  validateWithIllustrations,
  formatGuidance,
  parseJsonData
};
