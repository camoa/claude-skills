/**
 * Illustrations module
 * Single Responsibility: Loading and managing user-provided illustrations
 *
 * Supports:
 * - SVG files (.svg)
 * - PNG files (.png) - converted to base64 data URI
 * - JPG/JPEG files (.jpg, .jpeg) - converted to base64 data URI
 */

const fs = require('fs');
const path = require('path');

// Default assets directory (can be overridden)
let illustrationsDir = null;

// Cache for loaded illustrations
const illustrationCache = new Map();

/**
 * Set the illustrations directory path
 * @param {string} dirPath - Absolute path to illustrations folder
 */
function setIllustrationsDir(dirPath) {
  illustrationsDir = dirPath;
  // Clear cache when directory changes
  illustrationCache.clear();
}

/**
 * Get current illustrations directory
 * @returns {string|null} Current directory path
 */
function getIllustrationsDir() {
  return illustrationsDir;
}

/**
 * Check if an illustration file exists
 * @param {string} name - Illustration name (without extension)
 * @returns {Object|null} { exists: boolean, path: string, format: string } or null if dir not set
 */
function checkIllustration(name) {
  if (!illustrationsDir) {
    return null;
  }

  const supportedFormats = ['.svg', '.png', '.jpg', '.jpeg'];

  for (const ext of supportedFormats) {
    const filePath = path.join(illustrationsDir, `${name}${ext}`);
    if (fs.existsSync(filePath)) {
      return {
        exists: true,
        path: filePath,
        format: ext.slice(1) // Remove the dot
      };
    }
  }

  return {
    exists: false,
    path: path.join(illustrationsDir, `${name}.svg`), // Default expected path
    format: null
  };
}

/**
 * Get list of all available illustrations in the directory
 * @returns {string[]} Array of illustration names (without extensions)
 */
function listIllustrations() {
  if (!illustrationsDir || !fs.existsSync(illustrationsDir)) {
    return [];
  }

  const supportedExtensions = ['.svg', '.png', '.jpg', '.jpeg'];
  const files = fs.readdirSync(illustrationsDir);

  const illustrations = new Set();
  for (const file of files) {
    const ext = path.extname(file).toLowerCase();
    if (supportedExtensions.includes(ext)) {
      illustrations.add(path.basename(file, ext));
    }
  }

  return Array.from(illustrations).sort();
}

/**
 * Load an illustration by name
 * @param {string} name - Illustration name (without extension)
 * @returns {Object|null} { svg: string, format: string } or null if not found
 */
function loadIllustration(name) {
  // Check cache first
  if (illustrationCache.has(name)) {
    return illustrationCache.get(name);
  }

  const check = checkIllustration(name);
  if (!check || !check.exists) {
    return null;
  }

  try {
    let result;

    if (check.format === 'svg') {
      // Read SVG directly
      const svg = fs.readFileSync(check.path, 'utf-8');
      result = { svg, format: 'svg' };
    } else {
      // Convert PNG/JPG to embedded SVG with image
      const imageData = fs.readFileSync(check.path);
      const base64 = imageData.toString('base64');
      const mimeType = check.format === 'png' ? 'image/png' : 'image/jpeg';

      // Create SVG wrapper with embedded image
      // Using viewBox 0 0 100 100 for consistent sizing
      const svg = `<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <image width="100" height="100" preserveAspectRatio="xMidYMid meet" xlink:href="data:${mimeType};base64,${base64}"/>
</svg>`;
      result = { svg, format: check.format };
    }

    // Cache the result
    illustrationCache.set(name, result);
    return result;

  } catch (error) {
    console.error(`Error loading illustration '${name}':`, error.message);
    return null;
  }
}

/**
 * Validate that all required illustrations exist
 * @param {string[]} names - Array of required illustration names
 * @returns {Object} { valid: boolean, missing: string[], found: string[] }
 */
function validateIllustrations(names) {
  const missing = [];
  const found = [];

  for (const name of names) {
    const check = checkIllustration(name);
    if (check && check.exists) {
      found.push(name);
    } else {
      missing.push(name);
    }
  }

  return {
    valid: missing.length === 0,
    missing,
    found
  };
}

/**
 * Generate a colored placeholder SVG for missing illustrations
 * @param {string} name - Illustration name
 * @returns {string} SVG string
 */
function generatePlaceholder(name) {
  const colors = ['#3B82F6', '#10B981', '#F59E0B', '#EF4444', '#8B5CF6', '#EC4899'];
  const colorIndex = name.split('').reduce((acc, c) => acc + c.charCodeAt(0), 0) % colors.length;
  const color = colors[colorIndex];

  return `<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <rect width="100" height="100" fill="${color}" rx="8"/>
  <text x="50" y="45" text-anchor="middle" dominant-baseline="middle" fill="white" font-size="10" font-family="sans-serif">${name.substring(0, 12)}</text>
  <text x="50" y="60" text-anchor="middle" fill="rgba(255,255,255,0.7)" font-size="6" font-family="sans-serif">(missing)</text>
</svg>`;
}

/**
 * Clear the illustration cache
 */
function clearCache() {
  illustrationCache.clear();
}

module.exports = {
  setIllustrationsDir,
  getIllustrationsDir,
  checkIllustration,
  listIllustrations,
  loadIllustration,
  validateIllustrations,
  generatePlaceholder,
  clearCache
};
