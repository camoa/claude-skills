import { describe, it, expect } from 'vitest';
import {
  hexToRgbColor,
  mapShapeFill,
  mapTextColor,
  mapPageBackground,
  mapTextStyle,
  mapParagraphStyle,
} from '../src/token-mapper.js';

describe('hexToRgbColor', () => {
  it('converts #RRGGBB to rgbColor floats in 0–1', () => {
    expect(hexToRgbColor('#FF8000')).toEqual({ red: 1, green: 128 / 255, blue: 0 });
  });

  it('converts black and white correctly', () => {
    expect(hexToRgbColor('#000000')).toEqual({ red: 0, green: 0, blue: 0 });
    expect(hexToRgbColor('#FFFFFF')).toEqual({ red: 1, green: 1, blue: 1 });
  });

  it('expands #RGB shorthand', () => {
    expect(hexToRgbColor('#F80')).toEqual(hexToRgbColor('#FF8800'));
  });

  it('is case-insensitive', () => {
    expect(hexToRgbColor('#ff8000')).toEqual(hexToRgbColor('#FF8000'));
  });

  it('accepts hex with or without the leading #', () => {
    expect(hexToRgbColor('FF8000')).toEqual(hexToRgbColor('#FF8000'));
  });

  it('throws a clear error on malformed hex', () => {
    expect(() => hexToRgbColor('#GGGGGG')).toThrow(/invalid hex/i);
    expect(() => hexToRgbColor('#12345')).toThrow(/invalid hex/i);
    expect(() => hexToRgbColor('not-a-color')).toThrow(/invalid hex/i);
    expect(() => hexToRgbColor('')).toThrow(/invalid hex/i);
  });
});

describe('mapShapeFill', () => {
  it('builds an updateShapeProperties request with a solid fill colour', () => {
    expect(mapShapeFill('shape1', '#FF8000')).toEqual({
      updateShapeProperties: {
        objectId: 'shape1',
        shapeProperties: {
          shapeBackgroundFill: {
            solidFill: { color: { rgbColor: { red: 1, green: 128 / 255, blue: 0 } } },
          },
        },
        fields: 'shapeBackgroundFill.solidFill.color',
      },
    });
  });

  it('throws on a malformed hex', () => {
    expect(() => mapShapeFill('s', 'xyz')).toThrow(/invalid hex/i);
  });
});

describe('mapTextColor', () => {
  it('builds an updateTextStyle request setting foregroundColor over ALL text by default', () => {
    expect(mapTextColor('text1', '#000000')).toEqual({
      updateTextStyle: {
        objectId: 'text1',
        style: { foregroundColor: { opaqueColor: { rgbColor: { red: 0, green: 0, blue: 0 } } } },
        textRange: { type: 'ALL' },
        fields: 'foregroundColor',
      },
    });
  });

  it('honours an explicit textRange', () => {
    const r = mapTextColor('t', '#FFFFFF', { type: 'FIXED_RANGE', startIndex: 0, endIndex: 5 });
    expect(r.updateTextStyle?.textRange).toEqual({
      type: 'FIXED_RANGE',
      startIndex: 0,
      endIndex: 5,
    });
  });
});

describe('mapPageBackground', () => {
  it('builds an updatePageProperties request with a page background fill', () => {
    expect(mapPageBackground('slide1', '#FFFFFF')).toEqual({
      updatePageProperties: {
        objectId: 'slide1',
        pageProperties: {
          pageBackgroundFill: {
            solidFill: { color: { rgbColor: { red: 1, green: 1, blue: 1 } } },
          },
        },
        fields: 'pageBackgroundFill.solidFill.color',
      },
    });
  });
});

describe('mapTextStyle', () => {
  it('builds updateTextStyle with fontFamily only and a precise fields mask', () => {
    expect(mapTextStyle('t1', { fontFamily: 'Inter' })).toEqual({
      updateTextStyle: {
        objectId: 't1',
        style: { fontFamily: 'Inter' },
        textRange: { type: 'ALL' },
        fields: 'fontFamily',
      },
    });
  });

  it('emits fontSize as a PT magnitude and bold when given; mask names every set field', () => {
    const r = mapTextStyle('t1', { fontFamily: 'Inter', fontSize: 24, bold: true });
    expect(r.updateTextStyle?.style).toEqual({
      fontFamily: 'Inter',
      fontSize: { magnitude: 24, unit: 'PT' },
      bold: true,
    });
    expect(r.updateTextStyle?.fields).toBe('fontFamily,fontSize,bold');
  });

  it('honours an explicit textRange', () => {
    const r = mapTextStyle('t', { fontFamily: 'X' }, { type: 'FROM_START_INDEX', startIndex: 3 });
    expect(r.updateTextStyle?.textRange).toEqual({ type: 'FROM_START_INDEX', startIndex: 3 });
  });
});

describe('mapParagraphStyle', () => {
  it('builds updateParagraphStyle with only the set fields', () => {
    const r = mapParagraphStyle('p1', { lineSpacing: 115, alignment: 'CENTER' });
    expect(r.updateParagraphStyle?.style).toEqual({ lineSpacing: 115, alignment: 'CENTER' });
    expect(r.updateParagraphStyle?.fields).toBe('lineSpacing,alignment');
  });

  it('emits spaceAbove / spaceBelow as PT magnitudes', () => {
    const r = mapParagraphStyle('p1', { spaceAbove: 8, spaceBelow: 4 });
    expect(r.updateParagraphStyle?.style).toEqual({
      spaceAbove: { magnitude: 8, unit: 'PT' },
      spaceBelow: { magnitude: 4, unit: 'PT' },
    });
    expect(r.updateParagraphStyle?.fields).toBe('spaceAbove,spaceBelow');
  });

  it('throws fail-fast when no spacing/alignment value is supplied', () => {
    expect(() => mapParagraphStyle('p1', {})).toThrow();
  });
});

describe('mapTextStyle — weighted fonts', () => {
  it('emits weightedFontFamily when a weight is given', () => {
    const r = mapTextStyle('o1', { fontFamily: 'Nunito', weight: 900 });
    expect(r.updateTextStyle?.style?.weightedFontFamily).toEqual({
      fontFamily: 'Nunito',
      weight: 900,
    });
    expect(r.updateTextStyle?.style?.fontFamily).toBeUndefined();
    expect(r.updateTextStyle?.fields).toBe('weightedFontFamily');
  });

  it('emits plain fontFamily when no weight is given', () => {
    const r = mapTextStyle('o1', { fontFamily: 'Inter' });
    expect(r.updateTextStyle?.style?.fontFamily).toBe('Inter');
    expect(r.updateTextStyle?.style?.weightedFontFamily).toBeUndefined();
    expect(r.updateTextStyle?.fields).toBe('fontFamily');
  });

  it('combines a weight with an explicit font size', () => {
    const r = mapTextStyle('o1', { fontFamily: 'Nunito', weight: 800, fontSize: 52 });
    expect(r.updateTextStyle?.style?.weightedFontFamily?.weight).toBe(800);
    expect(r.updateTextStyle?.style?.fontSize).toEqual({ magnitude: 52, unit: 'PT' });
    expect(r.updateTextStyle?.fields).toBe('weightedFontFamily,fontSize');
  });
});
