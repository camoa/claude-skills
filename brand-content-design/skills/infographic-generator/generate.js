#!/usr/bin/env node
/**
 * Infographic Generator CLI
 *
 * Usage:
 *   node generate.js --config config.json --output output.png
 *   node generate.js --template sequence-timeline-simple --data '{"title":"Test"}' --output output.svg
 */

const fs = require('fs');
const path = require('path');

// Setup DOM before importing @antv/infographic
const {
  setupDOM,
  createInfographic,
  exportToDataURL,
  extractSVG,
  dataURLToBuffer,
  svgToPng,
  cleanup,
  applyCustomBackground,
  applyLayeredBackground,
  createBackgroundPreset,
  createLayeredPreset,
  getBackgroundPresets,
  getLayeredPresets,
  getDOMInstance,
  setIllustrationsDir
} = require('./lib/renderer');
setupDOM();

/**
 * Parse command line arguments
 */
function parseArgs() {
  const args = process.argv.slice(2);
  const options = {};

  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      const key = args[i].substring(2);
      const value = args[i + 1];

      // Handle --key=value format
      if (key.includes('=')) {
        const [k, v] = key.split('=');
        options[k] = v;
      } else {
        options[key] = value;
        i++;
      }
    }
  }

  return options;
}

/**
 * Load configuration from file or inline
 */
function loadConfig(options) {
  let config = {};

  // Load from config file
  if (options.config) {
    const configPath = path.resolve(options.config);
    if (fs.existsSync(configPath)) {
      config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    } else {
      throw new Error(`Config file not found: ${configPath}`);
    }
  }

  // Override with inline options
  if (options.template) {
    config.template = options.template;
  }

  if (options.data) {
    try {
      config.data = typeof options.data === 'string'
        ? JSON.parse(options.data)
        : options.data;
    } catch (e) {
      throw new Error(`Invalid JSON in --data: ${e.message}`);
    }
  }

  if (options.theme) {
    try {
      config.themeConfig = typeof options.theme === 'string'
        ? JSON.parse(options.theme)
        : options.theme;
    } catch (e) {
      throw new Error(`Invalid JSON in --theme: ${e.message}`);
    }
  }

  if (options.width) {
    config.width = parseInt(options.width, 10);
  }

  if (options.height) {
    config.height = parseInt(options.height, 10);
  }

  // Handle background option (can override config file)
  if (options.background) {
    config.background = options.background;
  }

  // Handle illustrations directory
  if (options.illustrations) {
    config.illustrationsDir = path.resolve(options.illustrations);
  }

  return config;
}

/**
 * Determine output format from file extension
 */
function getOutputFormat(outputPath) {
  const ext = path.extname(outputPath).toLowerCase();
  if (ext === '.svg') return 'svg';
  if (ext === '.png') return 'png';
  return 'png'; // default
}

/**
 * Darken a hex color by a percentage
 * @param {string} hex - Hex color code
 * @param {number} percent - Amount to darken (0-1)
 * @returns {string} Darkened hex color
 */
function darkenColor(hex, percent) {
  const num = parseInt(hex.replace('#', ''), 16);
  const r = Math.max(0, Math.floor((num >> 16) * (1 - percent)));
  const g = Math.max(0, Math.floor(((num >> 8) & 0x00FF) * (1 - percent)));
  const b = Math.max(0, Math.floor((num & 0x0000FF) * (1 - percent)));
  return `#${((r << 16) | (g << 8) | b).toString(16).padStart(6, '0')}`;
}

/**
 * Check if a color is light (for contrast decisions)
 * @param {string} hex - Hex color code
 * @returns {boolean} True if color is light
 */
function isLightColor(hex) {
  const num = parseInt(hex.replace('#', ''), 16);
  const r = (num >> 16) & 0xFF;
  const g = (num >> 8) & 0xFF;
  const b = num & 0xFF;
  // Using relative luminance formula
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.5;
}

/**
 * Main generation function
 */
async function main() {
  const options = parseArgs();

  // Validate required options
  if (!options.output) {
    console.error('Error: --output is required');
    console.error('Usage: node generate.js --config config.json --output output.png');
    process.exit(1);
  }

  try {
    // Load configuration
    const config = loadConfig(options);

    // Validate config
    if (!config.template && !config.design) {
      throw new Error('Either --template or --config with template/design is required');
    }

    if (!config.data) {
      throw new Error('--data or config.data is required');
    }

    // Set illustrations directory if provided
    if (config.illustrationsDir) {
      setIllustrationsDir(config.illustrationsDir);
      console.log(`Using illustrations from: ${config.illustrationsDir}`);
    }

    // Create infographic
    console.log(`Creating infographic with template: ${config.template || 'custom design'}`);
    const infographic = await createInfographic(config);

    // Determine output format
    const outputPath = path.resolve(options.output);
    const format = getOutputFormat(outputPath);
    console.log(`Exporting as ${format.toUpperCase()}...`);

    // Prepare background configuration
    let exportOptions = {};
    if (config.background) {
      // Extract brand colors from theme config for background
      // Note: For dark backgrounds, colorBg should be the dark base color
      // The palette should have dark colors for background gradient and light accent for patterns
      const brandColors = {};
      if (config.themeConfig) {
        // Use colorBg as primary background color (for dark backgrounds, this is the dark base)
        const bgColor = config.themeConfig.colorBg || '#0D2B5C';
        brandColors.primary = bgColor;
        // Derive darker shades from the background color
        brandColors.dark = darkenColor(bgColor, 0.3);
        brandColors.darker = darkenColor(bgColor, 0.6);
        // Accent comes from colorPrimary (for patterns) or palette
        brandColors.accent = config.themeConfig.colorPrimary || '#00f3ff';
        if (config.themeConfig.palette && config.themeConfig.palette.length > 1) {
          // If palette has accent color, use it (typically second light color for dark themes)
          const potentialAccent = config.themeConfig.palette.find(c =>
            isLightColor(c) && c !== '#FFFFFF' && c !== '#ffffff'
          );
          if (potentialAccent) brandColors.accent = potentialAccent;
        }
      }

      // Check if it's a layered preset
      const layeredPresets = getLayeredPresets();
      const simplePresets = getBackgroundPresets();

      if (layeredPresets.includes(config.background)) {
        exportOptions.layeredBackground = createLayeredPreset(config.background, brandColors);
        console.log(`Applying layered background: ${config.background}`);
      } else if (simplePresets.includes(config.background)) {
        exportOptions.customBackground = createBackgroundPreset(config.background, brandColors);
        console.log(`Applying simple background: ${config.background}`);
      } else if (config.background !== 'solid') {
        // Default to spotlight-dots if unknown preset
        exportOptions.layeredBackground = createLayeredPreset('spotlight-dots', brandColors);
        console.log(`Unknown preset "${config.background}", using spotlight-dots`);
      }
    }

    // Export SVG using extractSVG which applies backgrounds
    const dom = getDOMInstance();
    const svgString = extractSVG(dom, exportOptions);
    const svgBuffer = Buffer.from(svgString, 'utf-8');

    // Write file based on format
    if (format === 'svg') {
      fs.writeFileSync(outputPath, svgBuffer);
    } else {
      // Convert SVG to PNG using Puppeteer
      const dpr = options.dpr ? parseInt(options.dpr, 10) : 2;
      const pngBuffer = await svgToPng(svgBuffer, { dpr });
      fs.writeFileSync(outputPath, pngBuffer);
    }
    console.log(`Generated: ${outputPath}`);

    // Cleanup
    cleanup(infographic);

    // Output path for programmatic use
    if (options.json) {
      console.log(JSON.stringify({ success: true, path: outputPath }));
    }

  } catch (error) {
    console.error(`Error: ${error.message}`);
    if (options.json) {
      console.log(JSON.stringify({ success: false, error: error.message }));
    }
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}

module.exports = { main, loadConfig, parseArgs };
