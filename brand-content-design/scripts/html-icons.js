#!/usr/bin/env node
/**
 * CLI wrapper for Lucide icons — outputs inline SVG for HTML embedding.
 *
 * Reuses icons.js from infographic-generator for icon loading.
 *
 * Usage:
 *   node scripts/html-icons.js get rocket lightbulb shield
 *   node scripts/html-icons.js search chart
 *   node scripts/html-icons.js category business
 *   node scripts/html-icons.js categories
 */

const path = require('path');

// Resolve plugin root from BRAND_CONTENT_DESIGN_DIR or script location
const pluginDir = process.env.BRAND_CONTENT_DESIGN_DIR || path.resolve(__dirname, '..');
const iconsLib = require(path.join(pluginDir, 'skills', 'infographic-generator', 'lib', 'icons.js'));

const [command, ...args] = process.argv.slice(2);

switch (command) {
  case 'get': {
    if (args.length === 0) {
      console.error('Usage: html-icons.js get <name> [name2] [name3] ...');
      process.exit(1);
    }
    for (const name of args) {
      const svg = iconsLib.getIcon(name);
      if (svg) {
        console.log(`<!-- icon: ${name} -->`);
        console.log(svg);
      } else {
        console.error(`Icon not found: ${name}`);
      }
    }
    break;
  }

  case 'search': {
    if (args.length === 0) {
      console.error('Usage: html-icons.js search <keyword>');
      process.exit(1);
    }
    const results = iconsLib.searchIcons(args[0]);
    if (results.length === 0) {
      console.error(`No icons matching "${args[0]}"`);
    } else {
      console.log(results.join('\n'));
    }
    break;
  }

  case 'category': {
    if (args.length === 0) {
      console.error('Usage: html-icons.js category <name>');
      process.exit(1);
    }
    const icons = iconsLib.getIconsByCategory(args[0]);
    if (icons.length === 0) {
      console.error(`Unknown category: ${args[0]}`);
      console.error(`Available: ${iconsLib.listCategories().join(', ')}`);
    } else {
      console.log(icons.join('\n'));
    }
    break;
  }

  case 'categories': {
    console.log(iconsLib.listCategories().join('\n'));
    break;
  }

  default:
    console.error('Commands: get, search, category, categories');
    console.error('  get <name> [...]    — output inline SVG for named icons');
    console.error('  search <keyword>    — find icons matching keyword');
    console.error('  category <name>     — list icons in a category');
    console.error('  categories          — list all category names');
    process.exit(1);
}
