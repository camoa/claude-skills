/**
 * Custom Background Module
 * Adds creative backgrounds (gradients, patterns) to infographics
 * Applied post-render to bypass ANTV's solid-color-only limitation
 */

/**
 * Apply custom background to an SVG element
 * @param {SVGSVGElement} svg - The SVG element to modify
 * @param {Object} backgroundConfig - Background configuration
 * @param {Object} dom - JSDOM instance for element creation
 * @returns {SVGSVGElement} Modified SVG element
 */
function applyCustomBackground(svg, backgroundConfig, dom) {
  if (!backgroundConfig || !dom) return svg;

  const bg = backgroundConfig;
  const document = dom.window.document;

  // Get SVG dimensions
  const viewBox = svg.getAttribute('viewBox');
  let svgWidth = 720, svgHeight = 600;
  if (viewBox) {
    const parts = viewBox.split(' ').map(Number);
    svgWidth = parts[2] || svgWidth;
    svgHeight = parts[3] || svgHeight;
  }

  // Ensure defs element exists
  let defs = svg.querySelector('defs');
  if (!defs) {
    defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
    svg.prepend(defs);
  }

  // Helper to get or create background rect
  const getOrCreateBgRect = () => {
    let bgRect = svg.querySelector('[data-element-type="Background"]');
    if (!bgRect) {
      bgRect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      bgRect.setAttribute('x', '0');
      bgRect.setAttribute('y', '0');
      bgRect.setAttribute('width', svgWidth);
      bgRect.setAttribute('height', svgHeight);
      bgRect.setAttribute('data-element-type', 'Background');
      // Insert after defs
      const firstDefs = svg.querySelector('defs');
      if (firstDefs && firstDefs.nextSibling) {
        svg.insertBefore(bgRect, firstDefs.nextSibling);
      } else {
        svg.prepend(bgRect);
      }
    }
    return bgRect;
  };

  // Apply based on background type
  if (bg.type === 'gradient' || bg.type === 'linear-gradient') {
    applyLinearGradient(svg, defs, bg, getOrCreateBgRect, document);
  } else if (bg.type === 'radial-gradient') {
    applyRadialGradient(svg, defs, bg, getOrCreateBgRect, document);
  } else if (bg.type === 'pattern') {
    applyPattern(svg, defs, bg, getOrCreateBgRect, document);
  }

  return svg;
}

/**
 * Apply linear gradient background
 */
function applyLinearGradient(svg, defs, bg, getOrCreateBgRect, document) {
  const gradientId = 'custom-bg-gradient';
  const gradient = document.createElementNS('http://www.w3.org/2000/svg', 'linearGradient');
  gradient.setAttribute('id', gradientId);
  gradient.setAttribute('x1', bg.x1 || '0%');
  gradient.setAttribute('y1', bg.y1 || '0%');
  gradient.setAttribute('x2', bg.x2 || '100%');
  gradient.setAttribute('y2', bg.y2 || '100%');

  (bg.stops || []).forEach((stop, i) => {
    const stopEl = document.createElementNS('http://www.w3.org/2000/svg', 'stop');
    const offset = stop.offset || (i * 100 / Math.max(bg.stops.length - 1, 1)) + '%';
    stopEl.setAttribute('offset', offset);
    stopEl.setAttribute('stop-color', stop.color);
    if (stop.opacity !== undefined) stopEl.setAttribute('stop-opacity', stop.opacity);
    gradient.appendChild(stopEl);
  });

  defs.appendChild(gradient);
  getOrCreateBgRect().setAttribute('fill', `url(#${gradientId})`);
}

/**
 * Apply radial gradient background
 */
function applyRadialGradient(svg, defs, bg, getOrCreateBgRect, document) {
  const gradientId = 'custom-bg-radial';
  const gradient = document.createElementNS('http://www.w3.org/2000/svg', 'radialGradient');
  gradient.setAttribute('id', gradientId);
  gradient.setAttribute('cx', bg.cx || '50%');
  gradient.setAttribute('cy', bg.cy || '50%');
  gradient.setAttribute('r', bg.r || '70%');

  (bg.stops || []).forEach((stop, i) => {
    const stopEl = document.createElementNS('http://www.w3.org/2000/svg', 'stop');
    const offset = stop.offset || (i * 100 / Math.max(bg.stops.length - 1, 1)) + '%';
    stopEl.setAttribute('offset', offset);
    stopEl.setAttribute('stop-color', stop.color);
    if (stop.opacity !== undefined) stopEl.setAttribute('stop-opacity', stop.opacity);
    gradient.appendChild(stopEl);
  });

  defs.appendChild(gradient);
  getOrCreateBgRect().setAttribute('fill', `url(#${gradientId})`);
}

/**
 * Apply pattern background
 */
function applyPattern(svg, defs, bg, getOrCreateBgRect, document) {
  const patternId = 'custom-bg-pattern';
  const pattern = document.createElementNS('http://www.w3.org/2000/svg', 'pattern');
  pattern.setAttribute('id', patternId);
  pattern.setAttribute('patternUnits', 'userSpaceOnUse');
  pattern.setAttribute('width', bg.size || 20);
  pattern.setAttribute('height', bg.size || 20);

  // Background color for pattern
  const patternBg = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
  patternBg.setAttribute('width', bg.size || 20);
  patternBg.setAttribute('height', bg.size || 20);
  patternBg.setAttribute('fill', bg.backgroundColor || '#0D2B5C');
  pattern.appendChild(patternBg);

  const size = bg.size || 20;
  const fgColor = bg.foregroundColor || '#194582';

  switch (bg.pattern) {
    case 'dots':
      const dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      dot.setAttribute('cx', size / 2);
      dot.setAttribute('cy', size / 2);
      dot.setAttribute('r', bg.dotSize || 2);
      dot.setAttribute('fill', fgColor);
      pattern.appendChild(dot);
      break;

    case 'grid':
      const hLine = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      hLine.setAttribute('x1', '0');
      hLine.setAttribute('y1', '0');
      hLine.setAttribute('x2', size);
      hLine.setAttribute('y2', '0');
      hLine.setAttribute('stroke', fgColor);
      hLine.setAttribute('stroke-width', bg.lineWidth || 0.5);
      pattern.appendChild(hLine);

      const vLine = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      vLine.setAttribute('x1', '0');
      vLine.setAttribute('y1', '0');
      vLine.setAttribute('x2', '0');
      vLine.setAttribute('y2', size);
      vLine.setAttribute('stroke', fgColor);
      vLine.setAttribute('stroke-width', bg.lineWidth || 0.5);
      pattern.appendChild(vLine);
      break;

    case 'diagonal':
      const diag = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      diag.setAttribute('x1', '0');
      diag.setAttribute('y1', size);
      diag.setAttribute('x2', size);
      diag.setAttribute('y2', '0');
      diag.setAttribute('stroke', fgColor);
      diag.setAttribute('stroke-width', bg.lineWidth || 0.5);
      pattern.appendChild(diag);
      break;

    case 'crosshatch':
      const cross1 = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      cross1.setAttribute('x1', '0');
      cross1.setAttribute('y1', '0');
      cross1.setAttribute('x2', size);
      cross1.setAttribute('y2', size);
      cross1.setAttribute('stroke', fgColor);
      cross1.setAttribute('stroke-width', bg.lineWidth || 0.5);
      pattern.appendChild(cross1);

      const cross2 = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      cross2.setAttribute('x1', size);
      cross2.setAttribute('y1', '0');
      cross2.setAttribute('x2', '0');
      cross2.setAttribute('y2', size);
      cross2.setAttribute('stroke', fgColor);
      cross2.setAttribute('stroke-width', bg.lineWidth || 0.5);
      pattern.appendChild(cross2);
      break;

    default:
      // Default to dots if unknown pattern
      const defaultDot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      defaultDot.setAttribute('cx', size / 2);
      defaultDot.setAttribute('cy', size / 2);
      defaultDot.setAttribute('r', 2);
      defaultDot.setAttribute('fill', fgColor);
      pattern.appendChild(defaultDot);
  }

  defs.appendChild(pattern);
  getOrCreateBgRect().setAttribute('fill', `url(#${patternId})`);
}

/**
 * Create a preset background configuration
 * @param {string} preset - Preset name
 * @param {Object} brandColors - Brand color palette
 * @returns {Object} Background configuration
 */
function createBackgroundPreset(preset, brandColors = {}) {
  const primary = brandColors.primary || '#194582';
  const dark = brandColors.dark || '#0D2B5C';
  const darker = brandColors.darker || '#061120';
  const accent = brandColors.accent || '#00f3ff';

  const presets = {
    'spotlight': {
      type: 'radial-gradient',
      cx: '50%',
      cy: '40%',
      r: '80%',
      stops: [
        { offset: '0%', color: primary },
        { offset: '60%', color: dark },
        { offset: '100%', color: darker }
      ]
    },
    'diagonal-fade': {
      type: 'linear-gradient',
      x1: '0%',
      y1: '0%',
      x2: '100%',
      y2: '100%',
      stops: [
        { offset: '0%', color: dark },
        { offset: '50%', color: primary },
        { offset: '100%', color: dark }
      ]
    },
    'top-down': {
      type: 'linear-gradient',
      x1: '50%',
      y1: '0%',
      x2: '50%',
      y2: '100%',
      stops: [
        { offset: '0%', color: primary },
        { offset: '100%', color: darker }
      ]
    },
    'subtle-dots': {
      type: 'pattern',
      pattern: 'dots',
      size: 24,
      dotSize: 1.5,
      backgroundColor: dark,
      foregroundColor: primary
    },
    'tech-grid': {
      type: 'pattern',
      pattern: 'grid',
      size: 30,
      lineWidth: 0.3,
      backgroundColor: dark,
      foregroundColor: primary
    },
    'crosshatch': {
      type: 'pattern',
      pattern: 'crosshatch',
      size: 16,
      lineWidth: 0.3,
      backgroundColor: dark,
      foregroundColor: primary
    }
  };

  return presets[preset] || presets['spotlight'];
}

/**
 * Get list of available background presets
 * @returns {string[]} Array of preset names
 */
function getBackgroundPresets() {
  return ['spotlight', 'diagonal-fade', 'top-down', 'subtle-dots', 'tech-grid', 'crosshatch'];
}

/**
 * Apply layered background (gradient + pattern overlay)
 * @param {SVGSVGElement} svg - The SVG element to modify
 * @param {Object} layeredConfig - Layered background configuration
 * @param {Object} layeredConfig.gradient - Gradient config (linear-gradient or radial-gradient)
 * @param {Object} layeredConfig.pattern - Pattern config with opacity
 * @param {Object} dom - JSDOM instance
 * @returns {SVGSVGElement} Modified SVG element
 */
function applyLayeredBackground(svg, layeredConfig, dom) {
  if (!layeredConfig || !dom) return svg;

  const document = dom.window.document;

  // Get SVG dimensions
  const viewBox = svg.getAttribute('viewBox');
  let svgWidth = 720, svgHeight = 600;
  if (viewBox) {
    const parts = viewBox.split(' ').map(Number);
    svgWidth = parts[2] || svgWidth;
    svgHeight = parts[3] || svgHeight;
  }

  // Ensure defs element exists
  let defs = svg.querySelector('defs');
  if (!defs) {
    defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
    svg.prepend(defs);
  }

  // Remove existing background
  const existingBg = svg.querySelector('[data-element-type="Background"]');
  if (existingBg) existingBg.remove();

  // Create background group
  const bgGroup = document.createElementNS('http://www.w3.org/2000/svg', 'g');
  bgGroup.setAttribute('data-element-type', 'Background');

  // Layer 1: Gradient base
  if (layeredConfig.gradient) {
    const grad = layeredConfig.gradient;
    let gradientId, gradientEl;

    if (grad.type === 'radial-gradient') {
      gradientId = 'layered-bg-radial';
      gradientEl = document.createElementNS('http://www.w3.org/2000/svg', 'radialGradient');
      gradientEl.setAttribute('id', gradientId);
      gradientEl.setAttribute('cx', grad.cx || '50%');
      gradientEl.setAttribute('cy', grad.cy || '50%');
      gradientEl.setAttribute('r', grad.r || '70%');
    } else {
      gradientId = 'layered-bg-linear';
      gradientEl = document.createElementNS('http://www.w3.org/2000/svg', 'linearGradient');
      gradientEl.setAttribute('id', gradientId);
      gradientEl.setAttribute('x1', grad.x1 || '0%');
      gradientEl.setAttribute('y1', grad.y1 || '0%');
      gradientEl.setAttribute('x2', grad.x2 || '100%');
      gradientEl.setAttribute('y2', grad.y2 || '100%');
    }

    (grad.stops || []).forEach((stop, i) => {
      const stopEl = document.createElementNS('http://www.w3.org/2000/svg', 'stop');
      const offset = stop.offset || (i * 100 / Math.max(grad.stops.length - 1, 1)) + '%';
      stopEl.setAttribute('offset', offset);
      stopEl.setAttribute('stop-color', stop.color);
      if (stop.opacity !== undefined) stopEl.setAttribute('stop-opacity', stop.opacity);
      gradientEl.appendChild(stopEl);
    });

    defs.appendChild(gradientEl);

    const gradRect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    gradRect.setAttribute('x', '0');
    gradRect.setAttribute('y', '0');
    gradRect.setAttribute('width', svgWidth);
    gradRect.setAttribute('height', svgHeight);
    gradRect.setAttribute('fill', `url(#${gradientId})`);
    bgGroup.appendChild(gradRect);
  }

  // Layer 2: Pattern overlay
  if (layeredConfig.pattern) {
    const pat = layeredConfig.pattern;
    const patternId = 'layered-bg-pattern';
    const pattern = document.createElementNS('http://www.w3.org/2000/svg', 'pattern');
    pattern.setAttribute('id', patternId);
    pattern.setAttribute('patternUnits', 'userSpaceOnUse');
    pattern.setAttribute('width', pat.size || 20);
    pattern.setAttribute('height', pat.size || 20);

    const size = pat.size || 20;
    const fgColor = pat.foregroundColor || '#ffffff';

    switch (pat.pattern) {
      case 'dots':
        const dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        dot.setAttribute('cx', size / 2);
        dot.setAttribute('cy', size / 2);
        dot.setAttribute('r', pat.dotSize || 1.5);
        dot.setAttribute('fill', fgColor);
        pattern.appendChild(dot);
        break;

      case 'grid':
        const hLine = document.createElementNS('http://www.w3.org/2000/svg', 'line');
        hLine.setAttribute('x1', '0');
        hLine.setAttribute('y1', '0');
        hLine.setAttribute('x2', size);
        hLine.setAttribute('y2', '0');
        hLine.setAttribute('stroke', fgColor);
        hLine.setAttribute('stroke-width', pat.lineWidth || 0.5);
        pattern.appendChild(hLine);

        const vLine = document.createElementNS('http://www.w3.org/2000/svg', 'line');
        vLine.setAttribute('x1', '0');
        vLine.setAttribute('y1', '0');
        vLine.setAttribute('x2', '0');
        vLine.setAttribute('y2', size);
        vLine.setAttribute('stroke', fgColor);
        vLine.setAttribute('stroke-width', pat.lineWidth || 0.5);
        pattern.appendChild(vLine);
        break;

      case 'diagonal':
        const diag = document.createElementNS('http://www.w3.org/2000/svg', 'line');
        diag.setAttribute('x1', '0');
        diag.setAttribute('y1', size);
        diag.setAttribute('x2', size);
        diag.setAttribute('y2', '0');
        diag.setAttribute('stroke', fgColor);
        diag.setAttribute('stroke-width', pat.lineWidth || 0.5);
        pattern.appendChild(diag);
        break;

      case 'crosshatch':
        const cross1 = document.createElementNS('http://www.w3.org/2000/svg', 'line');
        cross1.setAttribute('x1', '0');
        cross1.setAttribute('y1', '0');
        cross1.setAttribute('x2', size);
        cross1.setAttribute('y2', size);
        cross1.setAttribute('stroke', fgColor);
        cross1.setAttribute('stroke-width', pat.lineWidth || 0.5);
        pattern.appendChild(cross1);

        const cross2 = document.createElementNS('http://www.w3.org/2000/svg', 'line');
        cross2.setAttribute('x1', size);
        cross2.setAttribute('y1', '0');
        cross2.setAttribute('x2', '0');
        cross2.setAttribute('y2', size);
        cross2.setAttribute('stroke', fgColor);
        cross2.setAttribute('stroke-width', pat.lineWidth || 0.5);
        pattern.appendChild(cross2);
        break;
    }

    defs.appendChild(pattern);

    const patRect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    patRect.setAttribute('x', '0');
    patRect.setAttribute('y', '0');
    patRect.setAttribute('width', svgWidth);
    patRect.setAttribute('height', svgHeight);
    patRect.setAttribute('fill', `url(#${patternId})`);
    patRect.setAttribute('opacity', pat.opacity || 0.15);
    bgGroup.appendChild(patRect);
  }

  // Insert background group at the beginning (after defs)
  const firstDefs = svg.querySelector('defs');
  if (firstDefs && firstDefs.nextSibling) {
    svg.insertBefore(bgGroup, firstDefs.nextSibling);
  } else {
    svg.prepend(bgGroup);
  }

  return svg;
}

/**
 * Create a layered background preset
 * @param {string} preset - Preset name
 * @param {Object} brandColors - Brand color palette
 * @returns {Object} Layered background configuration
 */
function createLayeredPreset(preset, brandColors = {}) {
  const primary = brandColors.primary || '#194582';
  const dark = brandColors.dark || '#0D2B5C';
  const darker = brandColors.darker || '#061120';
  const accent = brandColors.accent || '#00f3ff';

  const presets = {
    'spotlight-dots': {
      gradient: {
        type: 'radial-gradient',
        cx: '50%',
        cy: '40%',
        r: '80%',
        stops: [
          { offset: '0%', color: primary },
          { offset: '60%', color: dark },
          { offset: '100%', color: darker }
        ]
      },
      pattern: {
        pattern: 'dots',
        size: 20,
        dotSize: 1,
        foregroundColor: accent,
        opacity: 0.08
      }
    },
    'spotlight-grid': {
      gradient: {
        type: 'radial-gradient',
        cx: '50%',
        cy: '40%',
        r: '80%',
        stops: [
          { offset: '0%', color: primary },
          { offset: '60%', color: dark },
          { offset: '100%', color: darker }
        ]
      },
      pattern: {
        pattern: 'grid',
        size: 30,
        lineWidth: 0.3,
        foregroundColor: accent,
        opacity: 0.1
      }
    },
    'diagonal-crosshatch': {
      gradient: {
        type: 'linear-gradient',
        x1: '0%',
        y1: '0%',
        x2: '100%',
        y2: '100%',
        stops: [
          { offset: '0%', color: darker },
          { offset: '50%', color: primary },
          { offset: '100%', color: darker }
        ]
      },
      pattern: {
        pattern: 'crosshatch',
        size: 16,
        lineWidth: 0.3,
        foregroundColor: accent,
        opacity: 0.06
      }
    },
    'tech-matrix': {
      gradient: {
        type: 'linear-gradient',
        x1: '0%',
        y1: '0%',
        x2: '0%',
        y2: '100%',
        stops: [
          { offset: '0%', color: darker },
          { offset: '50%', color: dark },
          { offset: '100%', color: darker }
        ]
      },
      pattern: {
        pattern: 'grid',
        size: 24,
        lineWidth: 0.5,
        foregroundColor: accent,
        opacity: 0.12
      }
    }
  };

  return presets[preset] || presets['spotlight-dots'];
}

/**
 * Get list of available layered presets
 * @returns {string[]} Array of preset names
 */
function getLayeredPresets() {
  return ['spotlight-dots', 'spotlight-grid', 'diagonal-crosshatch', 'tech-matrix'];
}

module.exports = {
  applyCustomBackground,
  applyLayeredBackground,
  createBackgroundPreset,
  createLayeredPreset,
  getBackgroundPresets,
  getLayeredPresets
};
