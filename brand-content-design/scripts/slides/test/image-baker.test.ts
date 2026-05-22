import { describe, it, expect } from 'vitest';
import { bakeGradient, bakeDisplayText } from '../src/image-baker.js';

const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const isPng = (b: Buffer): boolean => b.subarray(0, 8).equals(PNG_SIG);

describe('bakeGradient', () => {
  it('produces a non-trivial PNG buffer', () => {
    const b = bakeGradient({ width: 200, height: 100, colors: ['#FF0000', '#0000FF'] });
    expect(isPng(b)).toBe(true);
    expect(b.length).toBeGreaterThan(100);
  });

  it('supports horizontal, vertical and diagonal directions', () => {
    for (const direction of ['horizontal', 'vertical', 'diagonal'] as const) {
      const b = bakeGradient({ width: 50, height: 50, colors: ['#000000', '#FFFFFF'], direction });
      expect(isPng(b)).toBe(true);
    }
  });

  it('throws on fewer than two colour stops', () => {
    expect(() => bakeGradient({ width: 50, height: 50, colors: ['#000000'] })).toThrow();
  });

  it('throws on non-positive dimensions', () => {
    expect(() => bakeGradient({ width: 0, height: 50, colors: ['#000000', '#FFFFFF'] })).toThrow();
  });
});

describe('bakeDisplayText', () => {
  it('produces a PNG buffer sized to the text', () => {
    const b = bakeDisplayText({
      text: 'Hello',
      fontFamily: 'sans-serif',
      fontSizePx: 48,
      color: '#000000',
    });
    expect(isPng(b)).toBe(true);
    expect(b.length).toBeGreaterThan(100);
  });

  it('throws on empty text', () => {
    expect(() =>
      bakeDisplayText({ text: '', fontFamily: 'sans-serif', fontSizePx: 48, color: '#000000' }),
    ).toThrow();
  });

  it('throws a clear error when the supplied fontFile does not exist', () => {
    expect(() =>
      bakeDisplayText({
        text: 'Hi',
        fontFamily: 'X',
        fontSizePx: 20,
        color: '#000000',
        fontFile: '/no/such/font.ttf',
      }),
    ).toThrow(/font file/i);
  });
});

describe('bakeGradient — uneven positions', () => {
  it('bakes a 3-stop diagonal gradient with explicit positions', () => {
    const png = bakeGradient({
      width: 64,
      height: 36,
      colors: ['#081E41', '#194582', '#00F3FF'],
      direction: 'diagonal',
      positions: [0, 0.62, 1],
    });
    expect(png.length).toBeGreaterThan(0);
    expect(png.subarray(1, 4).toString()).toBe('PNG');
  });

  it('throws when positions length does not match colours', () => {
    expect(() =>
      bakeGradient({ width: 10, height: 10, colors: ['#000000', '#FFFFFF'], positions: [0, 0.5, 1] }),
    ).toThrow(/positions/);
  });
});
