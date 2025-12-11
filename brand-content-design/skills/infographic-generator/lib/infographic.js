/**
 * Infographic creation module
 * Single Responsibility: Creating and managing infographic instances
 */

let resourceLoaderRegistered = false;

/**
 * Register custom resource loader for local icons and illustrations
 *
 * Resource parsing (from library's data-uri.ts):
 * - String 'icon:name' -> { type: 'custom', data: 'icon:name' } -> custom loader
 * - String 'illus:name' -> { type: 'custom', data: 'illus:name' } -> custom loader
 * - String '<svg>...</svg>' -> { type: 'custom', data: '<svg>...' } -> custom loader
 * - String 'data:image/svg+xml,...' -> { type: 'svg', data: '...' } -> built-in (buggy, doesn't decode)
 * - Object { type: 'custom', data: '...' } -> custom loader
 *
 * Handles:
 * - 'icon:name' format using local Lucide icons (1909 icons)
 * - 'illus:name' format - loads from illustrations folder or shows placeholder
 * - Direct SVG strings (raw <svg>...</svg>)
 * - Object format { type: 'custom', data: '<svg>...</svg>' }
 *
 * NOTE: data:image/svg+xml URIs have a library bug (doesn't decode URL-encoded data).
 * Use raw SVG strings or { type: 'custom', data: svg } instead.
 */
function registerResourceLoader() {
  if (resourceLoaderRegistered) return;

  const { registerResourceLoader: register, loadSVGResource } = require('@antv/infographic');
  const { getIcon } = require('./icons');
  const { loadIllustration, generatePlaceholder, getIllustrationsDir } = require('./illustrations');

  register(async (config) => {
    const { type, data } = config;

    // The custom resource loader handles type: 'custom' resources
    // String values like 'icon:name' and 'illus:name' are automatically
    // converted to { type: 'custom', data: string } by the library

    // Handle 'icon:name' format (Lucide icons)
    if (typeof data === 'string' && data.startsWith('icon:')) {
      const iconName = data.replace('icon:', '');
      const svg = getIcon(iconName);
      if (svg) {
        return loadSVGResource(svg);
      }
    }

    // Handle 'illus:name' format - load from illustrations folder
    if (typeof data === 'string' && data.startsWith('illus:')) {
      const name = data.replace('illus:', '');

      // Try to load from illustrations directory
      const illustration = loadIllustration(name);
      if (illustration) {
        return loadSVGResource(illustration.svg);
      }

      // Fall back to placeholder if illustrations dir is set but file not found
      if (getIllustrationsDir()) {
        console.warn(`Illustration '${name}' not found in ${getIllustrationsDir()}`);
      }

      // Generate placeholder
      const placeholder = generatePlaceholder(name);
      return loadSVGResource(placeholder);
    }

    // Handle type: 'custom' with raw SVG data
    // When users provide { type: 'custom', data: '<svg>...</svg>' }
    if (type === 'custom' && typeof data === 'string') {
      // Check if data is URL-encoded (starts with %3C which is '<')
      if (data.startsWith('%3C') || data.startsWith('%3c')) {
        const decoded = decodeURIComponent(data);
        return loadSVGResource(decoded);
      }
      // Already decoded SVG string
      if (data.startsWith('<svg') || data.startsWith('<symbol')) {
        return loadSVGResource(data);
      }
    }

    return null;
  });

  resourceLoaderRegistered = true;
}

/**
 * Create and render an infographic
 * @param {Object} config - Infographic configuration
 * @param {string} config.template - Template name (e.g., 'sequence-timeline-simple')
 * @param {Object} config.data - Data object with title, desc, items
 * @param {Object} config.themeConfig - Theme configuration
 * @param {number} config.width - Width in pixels
 * @param {number} config.height - Height in pixels (optional, auto-calculated)
 * @param {string} config.illustrationsDir - Optional path to illustrations folder
 * @returns {Object} Infographic instance
 */
async function createInfographic(config) {
  // Import after DOM setup
  const { Infographic } = require('@antv/infographic');
  const { setIllustrationsDir } = require('./illustrations');

  // Set illustrations directory if provided
  if (config.illustrationsDir) {
    setIllustrationsDir(config.illustrationsDir);
  }

  // Register resource loader on first use
  registerResourceLoader();

  const infographic = new Infographic({
    container: config.container || '#container',
    template: config.template,
    data: config.data,
    themeConfig: config.themeConfig || {},
    width: config.width || 800,
    height: config.height || 600
  });

  infographic.render();

  // Wait for async resource loading (icons, illustrations)
  // This ensures all resources are loaded before export
  await new Promise(resolve => setTimeout(resolve, 300));

  return infographic;
}

/**
 * Cleanup infographic and release resources
 * @param {Object} infographic - Infographic instance
 */
function cleanup(infographic) {
  if (infographic && typeof infographic.destroy === 'function') {
    infographic.destroy();
  }
}

module.exports = {
  createInfographic,
  cleanup
};
