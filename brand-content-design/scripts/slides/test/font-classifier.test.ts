import { describe, it, expect } from 'vitest';
import { isGoogleFont, classifyFonts } from '../src/font-classifier.js';
import type { BrandTokens } from '../src/token-mapper.js';

function tokens(headingFont: string, bodyFont: string): BrandTokens {
  return {
    colors: {
      primary: '#000000',
      background: '#FFFFFF',
      textLight: '#111111',
      textDark: '#EEEEEE',
    },
    typography: { headingFont, bodyFont },
  };
}

describe('isGoogleFont', () => {
  it('recognizes common Google Fonts families', () => {
    expect(isGoogleFont('Roboto')).toBe(true);
    expect(isGoogleFont('Inter')).toBe(true);
    expect(isGoogleFont('Montserrat')).toBe(true);
  });

  it('is case- and whitespace-insensitive', () => {
    expect(isGoogleFont('  roboto ')).toBe(true);
    expect(isGoogleFont('OPEN SANS')).toBe(true);
  });

  it('rejects a custom / non-catalogue font', () => {
    expect(isGoogleFont('Proxima Nova')).toBe(false);
    expect(isGoogleFont('Acme Corp Sans')).toBe(false);
    expect(isGoogleFont('')).toBe(false);
  });
});

describe('classifyFonts', () => {
  it('classifies heading and body fonts independently', () => {
    expect(classifyFonts(tokens('Montserrat', 'Proxima Nova'))).toEqual({
      heading: 'native',
      body: 'custom',
    });
  });

  it('classifies both as native when both are Google Fonts', () => {
    expect(classifyFonts(tokens('Inter', 'Lora'))).toEqual({
      heading: 'native',
      body: 'native',
    });
  });
});
