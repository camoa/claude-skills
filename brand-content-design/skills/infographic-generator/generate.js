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
const { setupDOM, createInfographic, exportToDataURL, dataURLToBuffer, svgToPng, cleanup } = require('./lib/renderer');
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

    // Create infographic
    console.log(`Creating infographic with template: ${config.template || 'custom design'}`);
    const infographic = await createInfographic(config);

    // Determine output format
    const outputPath = path.resolve(options.output);
    const format = getOutputFormat(outputPath);
    console.log(`Exporting as ${format.toUpperCase()}...`);

    // Export to SVG first (always needed, PNG is converted from SVG)
    const svgDataUrl = await exportToDataURL(infographic, { type: 'svg' });
    const svgBuffer = dataURLToBuffer(svgDataUrl);

    // Write file based on format
    if (format === 'svg') {
      fs.writeFileSync(outputPath, svgBuffer);
    } else {
      // Convert SVG to PNG using sharp
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
