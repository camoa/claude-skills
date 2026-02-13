#!/usr/bin/env node
/**
 * Extract inline SVGs from HTML files for Drupal Icon API.
 *
 * Finds `<!-- icon: {name} -->` comments followed by `<svg>...</svg>` blocks
 * and extracts the inner SVG content (paths, circles, lines) to individual files.
 *
 * Usage:
 *   node scripts/extract-icons.js list <html-file>
 *   node scripts/extract-icons.js extract <html-file> <output-dir>
 */

const fs = require('fs');
const path = require('path');

const [command, ...args] = process.argv.slice(2);

/**
 * Parse HTML and return an array of { name, innerSvg } objects.
 * Matches `<!-- icon: {name} -->` followed by an `<svg ...>...</svg>` block.
 * Deduplicates by icon name (keeps first occurrence).
 */
function parseIcons(html) {
  const pattern = /<!--\s*icon:\s*([\w-]+)\s*-->\s*<svg[^>]*>([\s\S]*?)<\/svg>/gi;
  const seen = new Set();
  const icons = [];
  let match;

  while ((match = pattern.exec(html)) !== null) {
    const name = match[1].toLowerCase();
    const innerSvg = match[2].trim();

    if (!seen.has(name)) {
      seen.add(name);
      icons.push({ name, innerSvg });
    }
  }

  return icons;
}

/**
 * Read an HTML file and return its contents.
 */
function readHtmlFile(filePath) {
  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) {
    console.error(`File not found: ${resolved}`);
    process.exit(1);
  }
  return fs.readFileSync(resolved, 'utf-8');
}

switch (command) {
  case 'list': {
    if (args.length === 0) {
      console.error('Usage: extract-icons.js list <html-file>');
      process.exit(1);
    }
    const html = readHtmlFile(args[0]);
    const icons = parseIcons(html);

    if (icons.length === 0) {
      console.error('No icon comments found in the HTML file.');
      console.error('Expected format: <!-- icon: name --> followed by <svg>...</svg>');
      process.exit(1);
    }

    for (const icon of icons) {
      console.log(icon.name);
    }
    break;
  }

  case 'extract': {
    if (args.length < 2) {
      console.error('Usage: extract-icons.js extract <html-file> <output-dir>');
      process.exit(1);
    }

    const html = readHtmlFile(args[0]);
    const outputDir = path.resolve(args[1]);
    const icons = parseIcons(html);

    if (icons.length === 0) {
      console.error('No icon comments found in the HTML file.');
      console.error('Expected format: <!-- icon: name --> followed by <svg>...</svg>');
      process.exit(1);
    }

    // Create output directory if it does not exist
    fs.mkdirSync(outputDir, { recursive: true });

    let count = 0;
    for (const icon of icons) {
      const outPath = path.join(outputDir, icon.name + '.svg');
      fs.writeFileSync(outPath, icon.innerSvg + '\n', 'utf-8');
      count++;
    }

    console.log('Extracted ' + count + ' icons to ' + outputDir);
    break;
  }

  default:
    console.error('Commands: list, extract');
    console.error('  list <html-file>                — list icon names found in HTML');
    console.error('  extract <html-file> <output-dir> — extract SVG inner content to files');
    process.exit(1);
}
