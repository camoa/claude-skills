#!/usr/bin/env node
/**
 * Test script for infographic-generator
 * Tests 3 different template types: Timeline, Comparison, Bar Chart
 */

const fs = require('fs');
const path = require('path');

// Setup DOM first
const { setupDOM, createInfographic, exportToDataURL, dataURLToBuffer, svgToPng, cleanup } = require('./lib/renderer');
setupDOM();

const TEST_OUTPUT_DIR = path.join(__dirname, 'test-output');

// Test configurations
const testCases = [
  {
    name: 'timeline',
    config: {
      template: 'sequence-timeline-simple',
      data: {
        title: 'Company Milestones',
        desc: 'Our journey from startup to scale',
        items: [
          { label: '2020', desc: 'Founded in Seattle' },
          { label: '2021', desc: 'Seed funding ($2M)' },
          { label: '2022', desc: 'Series A ($15M)' },
          { label: '2023', desc: '100K users' },
          { label: '2024', desc: 'Global expansion' }
        ]
      },
      themeConfig: {
        colorPrimary: '#3B82F6',
        palette: ['#3B82F6', '#10B981', '#F59E0B', '#EF4444', '#8B5CF6']
      },
      width: 800,
      height: 400
    }
  },
  {
    name: 'comparison',
    config: {
      template: 'compare-binary-horizontal-badge-card-vs',
      data: {
        title: 'Before vs After',
        desc: 'The transformation',
        items: [
          {
            label: 'Before',
            children: [
              { label: 'Slow' },
              { label: 'Manual' },
              { label: 'Expensive' },
              { label: 'Error-prone' }
            ]
          },
          {
            label: 'After',
            children: [
              { label: 'Fast' },
              { label: 'Automated' },
              { label: 'Affordable' },
              { label: 'Reliable' }
            ]
          }
        ]
      },
      themeConfig: {
        colorPrimary: '#3B82F6',
        palette: ['#EF4444', '#10B981']
      },
      width: 800,
      height: 500
    }
  },
  {
    name: 'chart',
    config: {
      template: 'chart-column-simple',
      data: {
        title: 'Quarterly Revenue',
        desc: '2024 Performance',
        items: [
          { label: 'Q1', value: 120 },
          { label: 'Q2', value: 150 },
          { label: 'Q3', value: 180 },
          { label: 'Q4', value: 210 }
        ]
      },
      themeConfig: {
        colorPrimary: '#3B82F6'
      },
      width: 600,
      height: 400
    }
  }
];

async function runTests() {
  console.log('=== Infographic Generator Tests ===\n');

  // Create output directory
  if (!fs.existsSync(TEST_OUTPUT_DIR)) {
    fs.mkdirSync(TEST_OUTPUT_DIR, { recursive: true });
  }

  let passed = 0;
  let failed = 0;

  for (const testCase of testCases) {
    console.log(`Testing: ${testCase.name}...`);

    try {
      // Create infographic
      const infographic = await createInfographic(testCase.config);

      // Export to SVG
      const svgPath = path.join(TEST_OUTPUT_DIR, `${testCase.name}.svg`);
      const svgDataUrl = await exportToDataURL(infographic, { type: 'svg' });
      const svgBuffer = dataURLToBuffer(svgDataUrl);
      fs.writeFileSync(svgPath, svgBuffer);

      // Convert SVG to PNG using sharp
      const pngPath = path.join(TEST_OUTPUT_DIR, `${testCase.name}.png`);
      const pngBuffer = await svgToPng(svgBuffer, { dpr: 2 });
      fs.writeFileSync(pngPath, pngBuffer);

      // Cleanup
      cleanup(infographic);

      // Verify files exist and have content
      const svgStats = fs.statSync(svgPath);
      const pngStats = fs.statSync(pngPath);

      if (svgStats.size > 0 && pngStats.size > 0) {
        console.log(`  ✓ SVG: ${svgPath} (${(svgStats.size / 1024).toFixed(1)} KB)`);
        console.log(`  ✓ PNG: ${pngPath} (${(pngStats.size / 1024).toFixed(1)} KB)`);
        passed++;
      } else {
        console.log(`  ✗ Files created but empty`);
        failed++;
      }

    } catch (error) {
      console.log(`  ✗ Error: ${error.message}`);
      console.log(`    Stack: ${error.stack}`);
      failed++;
    }

    console.log('');
  }

  console.log('=== Results ===');
  console.log(`Passed: ${passed}/${testCases.length}`);
  console.log(`Failed: ${failed}/${testCases.length}`);

  if (failed > 0) {
    process.exit(1);
  }
}

// Run tests
runTests().catch(error => {
  console.error('Test runner error:', error);
  process.exit(1);
});
