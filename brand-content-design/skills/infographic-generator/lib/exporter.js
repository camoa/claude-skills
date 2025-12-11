/**
 * Export utilities module
 * Single Responsibility: Converting infographics to various formats
 */

const { applyCustomBackground, applyLayeredBackground } = require('./backgrounds');

/**
 * Export infographic to data URL using library's native export
 * NOTE: This may fail in JSDOM due to font embedding. Use extractSVG instead.
 * @param {Object} infographic - Infographic instance
 * @param {Object} options - Export options
 * @param {string} options.type - 'svg' or 'png'
 * @param {number} options.dpr - Device pixel ratio for PNG (default: 2)
 * @param {boolean} options.embedResources - Embed fonts/images for SVG
 * @returns {Promise<string>} Data URL
 */
async function exportToDataURL(infographic, options = {}) {
  const type = options.type || 'png';
  const exportOptions = {
    type,
    ...(type === 'png' ? { dpr: options.dpr || 2 } : {}),
    ...(type === 'svg' ? { embedResources: options.embedResources !== false } : {})
  };

  return await infographic.toDataURL(exportOptions);
}

/**
 * Extract SVG directly from DOM (bypasses font embedding issues in JSDOM)
 * @param {Object} dom - JSDOM instance
 * @param {Object} options - Export options
 * @param {string} options.container - Container selector (default: '#container')
 * @param {Object} options.customBackground - Custom background configuration
 * @returns {string} SVG string
 */
function extractSVG(dom, options = {}) {
  const container = options.container || '#container';
  const svgElement = dom.window.document.querySelector(`${container} svg`);

  if (!svgElement) {
    throw new Error(`SVG element not found in DOM at ${container}`);
  }

  // Clone to avoid modifying original
  const clonedSvg = svgElement.cloneNode(true);

  // Get dimensions from viewBox and set explicit width/height
  const viewBox = clonedSvg.getAttribute('viewBox');
  if (viewBox) {
    const [, , w, h] = viewBox.split(' ').map(Number);
    // Set numeric dimensions (without px) for proper rendering
    clonedSvg.setAttribute('width', w);
    clonedSvg.setAttribute('height', h);
  }

  // Apply custom background if provided
  if (options.customBackground) {
    applyCustomBackground(clonedSvg, options.customBackground, dom);
  }

  // Apply layered background if provided (gradient + pattern overlay)
  if (options.layeredBackground) {
    applyLayeredBackground(clonedSvg, options.layeredBackground, dom);
  }

  return clonedSvg.outerHTML;
}

/**
 * Extract SVG as Buffer
 * @param {Object} dom - JSDOM instance
 * @param {Object} options - Export options
 * @returns {Buffer} SVG buffer
 */
function extractSVGBuffer(dom, options = {}) {
  const svgString = extractSVG(dom, options);
  return Buffer.from(svgString, 'utf-8');
}

/**
 * Convert data URL to Buffer
 * Handles both base64 and URL-encoded data URLs
 * @param {string} dataUrl - Data URL string
 * @returns {Buffer} File buffer
 */
function dataURLToBuffer(dataUrl) {
  if (dataUrl.includes(';base64,')) {
    const base64Data = dataUrl.split(',')[1];
    return Buffer.from(base64Data, 'base64');
  } else {
    // URL encoded (used by @antv/infographic for SVG)
    const encodedData = dataUrl.split(',')[1];
    return Buffer.from(decodeURIComponent(encodedData), 'utf-8');
  }
}

/**
 * Convert SVG buffer to PNG using Puppeteer (full browser rendering)
 * This properly renders foreignObject elements with HTML content
 * @param {Buffer} svgBuffer - SVG file buffer
 * @param {Object} options - Conversion options
 * @param {number} options.dpr - Device pixel ratio (default: 2)
 * @returns {Promise<Buffer>} PNG buffer
 */
async function svgToPng(svgBuffer, options = {}) {
  const dpr = options.dpr || 2;
  const svgString = svgBuffer.toString('utf-8');

  // Extract dimensions from SVG
  const widthMatch = svgString.match(/width="(\d+)"/);
  const heightMatch = svgString.match(/height="(\d+)"/);
  const width = widthMatch ? parseInt(widthMatch[1]) : 800;
  const height = heightMatch ? parseInt(heightMatch[1]) : 600;

  const puppeteer = require('puppeteer');
  let browser;

  try {
    browser = await puppeteer.launch({
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    const page = await browser.newPage();

    // Set viewport to match SVG dimensions with DPR scaling
    await page.setViewport({
      width: width,
      height: height,
      deviceScaleFactor: dpr
    });

    // Create HTML page with SVG
    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          * { margin: 0; padding: 0; }
          body {
            width: ${width}px;
            height: ${height}px;
            overflow: hidden;
          }
          svg { display: block; }
        </style>
      </head>
      <body>${svgString}</body>
      </html>
    `;

    await page.setContent(html, { waitUntil: 'networkidle0' });

    // Take screenshot
    const screenshot = await page.screenshot({
      type: 'png',
      omitBackground: false
    });

    return screenshot;
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

module.exports = {
  exportToDataURL,
  extractSVG,
  extractSVGBuffer,
  dataURLToBuffer,
  svgToPng
};
