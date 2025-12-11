/**
 * DOM Setup module for server-side rendering
 * Single Responsibility: Setting up virtual DOM environment for jsdom
 */

const { JSDOM } = require('jsdom');

let domInstance = null;

/**
 * Setup virtual DOM environment
 * Must be called before importing @antv/infographic
 * @returns {JSDOM} The DOM instance
 */
function setupDOM() {
  if (domInstance) {
    return domInstance;
  }

  const dom = new JSDOM('<!DOCTYPE html><html><body><div id="container"></div></body></html>', {
    pretendToBeVisual: true,
    runScripts: 'dangerously'
  });

  domInstance = dom;

  // Core DOM globals
  global.window = dom.window;
  global.document = dom.window.document;
  global.navigator = dom.window.navigator;
  global.Element = dom.window.Element;
  global.Node = dom.window.Node;
  global.Text = dom.window.Text;
  global.DocumentFragment = dom.window.DocumentFragment;
  global.DOMParser = dom.window.DOMParser;
  global.XMLSerializer = dom.window.XMLSerializer;

  // HTML Elements
  global.HTMLElement = dom.window.HTMLElement;
  global.HTMLCanvasElement = dom.window.HTMLCanvasElement;

  // SVG Elements - required by @antv/infographic
  setupSVGGlobals(dom.window);

  // Browser APIs
  setupBrowserAPIs(dom.window);

  return dom;
}

/**
 * Setup SVG element globals
 * @param {Window} window - jsdom window object
 */
function setupSVGGlobals(window) {
  const svgElements = [
    'SVGElement', 'SVGSVGElement', 'SVGGElement', 'SVGPathElement',
    'SVGRectElement', 'SVGCircleElement', 'SVGEllipseElement', 'SVGLineElement',
    'SVGPolylineElement', 'SVGPolygonElement', 'SVGTextElement', 'SVGTSpanElement',
    'SVGDefsElement', 'SVGUseElement', 'SVGImageElement', 'SVGClipPathElement',
    'SVGMaskElement', 'SVGPatternElement', 'SVGLinearGradientElement',
    'SVGRadialGradientElement', 'SVGStopElement', 'SVGForeignObjectElement'
  ];

  svgElements.forEach(name => {
    global[name] = window[name] || window.SVGElement;
  });
}

/**
 * Setup browser API globals
 * @param {Window} window - jsdom window object
 */
function setupBrowserAPIs(window) {
  global.getComputedStyle = window.getComputedStyle;
  global.requestAnimationFrame = (cb) => setTimeout(cb, 0);
  global.cancelAnimationFrame = (id) => clearTimeout(id);
  global.URL = window.URL;
  global.Blob = window.Blob;
  global.btoa = window.btoa;
  global.atob = window.atob;
  global.fetch = window.fetch;
  global.Image = window.Image;
  global.MutationObserver = window.MutationObserver;
  global.ResizeObserver = window.ResizeObserver || createResizeObserverStub();
}

/**
 * Create ResizeObserver stub for environments without it
 * @returns {Function} ResizeObserver constructor stub
 */
function createResizeObserverStub() {
  return class ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  };
}

/**
 * Get the current DOM instance
 * @returns {JSDOM|null} Current DOM instance or null
 */
function getDOMInstance() {
  return domInstance;
}

module.exports = {
  setupDOM,
  getDOMInstance
};
