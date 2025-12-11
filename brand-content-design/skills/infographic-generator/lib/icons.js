/**
 * Icon helper module for @antv/infographic
 * Provides local Lucide icons as inline SVG for Node.js environment
 *
 * Usage:
 *   const { getIcon, getIconDataUri, listIcons, searchIcons } = require('./lib/icons');
 *
 *   // Get SVG string
 *   const svg = getIcon('rocket');
 *
 *   // Get data URI for @antv/infographic
 *   const dataUri = getIconDataUri('rocket');
 *   // Use in data: { items: [{ icon: dataUri, label: 'Launch' }] }
 */

const fs = require('fs');
const path = require('path');

const ICONS_DIR = path.join(__dirname, '../node_modules/lucide-static/icons');

// Cache for loaded icons
const iconCache = new Map();

/**
 * List all available icon names
 * @returns {string[]} Array of icon names (without .svg extension)
 */
function listIcons() {
  try {
    const files = fs.readdirSync(ICONS_DIR);
    return files
      .filter(f => f.endsWith('.svg'))
      .map(f => f.replace('.svg', ''));
  } catch (error) {
    console.error('Error listing icons:', error.message);
    return [];
  }
}

/**
 * Search icons by keyword
 * @param {string} keyword - Search term
 * @returns {string[]} Matching icon names
 */
function searchIcons(keyword) {
  const icons = listIcons();
  const term = keyword.toLowerCase();
  return icons.filter(name => name.includes(term));
}

/**
 * Get icon SVG content
 * @param {string} name - Icon name (e.g., 'rocket', 'check-circle')
 * @param {Object} options - Options
 * @param {string} options.color - Fill/stroke color (default: 'currentColor')
 * @param {number} options.size - Width/height in pixels (default: 24)
 * @returns {string|null} SVG string or null if not found
 */
function getIcon(name, options = {}) {
  const { color = 'currentColor', size = 24 } = options;

  // Check cache
  const cacheKey = `${name}-${color}-${size}`;
  if (iconCache.has(cacheKey)) {
    return iconCache.get(cacheKey);
  }

  const iconPath = path.join(ICONS_DIR, `${name}.svg`);

  try {
    let svg = fs.readFileSync(iconPath, 'utf-8');

    // Strip license comment (Lucide icons start with <!-- @license ... -->)
    svg = svg.replace(/<!--[\s\S]*?-->\s*/g, '').trim();

    // Update color and size
    svg = svg
      .replace(/width="24"/g, `width="${size}"`)
      .replace(/height="24"/g, `height="${size}"`)
      .replace(/stroke="currentColor"/g, `stroke="${color}"`)
      .replace(/fill="none"/g, 'fill="none"'); // Keep fill none for outline icons

    iconCache.set(cacheKey, svg);
    return svg;
  } catch (error) {
    console.error(`Icon not found: ${name}`);
    return null;
  }
}

/**
 * Get icon as data URI for @antv/infographic ResourceConfig
 * This format works with the 'svg' resource type
 * @param {string} name - Icon name
 * @param {Object} options - Options (color, size)
 * @returns {string|null} Data URI string or null if not found
 */
function getIconDataUri(name, options = {}) {
  const svg = getIcon(name, options);
  if (!svg) return null;

  // Convert to data:image/svg+xml format
  const encoded = encodeURIComponent(svg);
  return `data:image/svg+xml,${encoded}`;
}

/**
 * Get icon as base64 data URI
 * Alternative format that may work better in some contexts
 * @param {string} name - Icon name
 * @param {Object} options - Options (color, size)
 * @returns {string|null} Base64 data URI or null if not found
 */
function getIconBase64(name, options = {}) {
  const svg = getIcon(name, options);
  if (!svg) return null;

  const base64 = Buffer.from(svg).toString('base64');
  return `data:image/svg+xml;base64,${base64}`;
}

/**
 * Get multiple icons as a map
 * @param {string[]} names - Array of icon names
 * @param {Object} options - Options (color, size)
 * @returns {Object} Map of name -> dataUri
 */
function getIcons(names, options = {}) {
  const result = {};
  for (const name of names) {
    const uri = getIconDataUri(name, options);
    if (uri) result[name] = uri;
  }
  return result;
}

/**
 * Common icon categories for infographics
 */
const ICON_CATEGORIES = {
  process: ['play', 'pause', 'stop', 'skip-forward', 'skip-back', 'refresh-cw', 'repeat'],
  business: ['briefcase', 'building', 'building-2', 'landmark', 'store', 'factory', 'warehouse'],
  growth: ['trending-up', 'trending-down', 'chart-bar', 'chart-line', 'chart-pie', 'target', 'award'],
  people: ['user', 'users', 'user-plus', 'user-check', 'contact', 'smile', 'heart'],
  communication: ['mail', 'message-circle', 'message-square', 'phone', 'video', 'radio', 'megaphone'],
  technology: ['laptop', 'smartphone', 'tablet', 'monitor', 'server', 'cloud', 'database', 'cpu'],
  actions: ['check', 'check-circle', 'x', 'x-circle', 'plus', 'minus', 'edit', 'trash-2'],
  navigation: ['arrow-right', 'arrow-left', 'arrow-up', 'arrow-down', 'chevron-right', 'chevron-left'],
  time: ['clock', 'calendar', 'timer', 'hourglass', 'history', 'calendar-days'],
  documents: ['file', 'file-text', 'folder', 'clipboard', 'book', 'notebook', 'newspaper'],
  security: ['lock', 'unlock', 'shield', 'shield-check', 'key', 'eye', 'eye-off'],
  money: ['dollar-sign', 'credit-card', 'wallet', 'coins', 'banknote', 'receipt'],
  nature: ['sun', 'moon', 'cloud', 'zap', 'droplet', 'leaf', 'tree', 'flower'],
  transport: ['car', 'truck', 'plane', 'ship', 'train', 'bike', 'bus'],
  misc: ['star', 'heart', 'flag', 'bookmark', 'tag', 'gift', 'lightbulb', 'rocket']
};

/**
 * Get icons by category
 * @param {string} category - Category name from ICON_CATEGORIES
 * @returns {string[]} Icon names in that category
 */
function getIconsByCategory(category) {
  return ICON_CATEGORIES[category] || [];
}

/**
 * List all categories
 * @returns {string[]} Category names
 */
function listCategories() {
  return Object.keys(ICON_CATEGORIES);
}

module.exports = {
  listIcons,
  searchIcons,
  getIcon,
  getIconDataUri,
  getIconBase64,
  getIcons,
  getIconsByCategory,
  listCategories,
  ICON_CATEGORIES
};
