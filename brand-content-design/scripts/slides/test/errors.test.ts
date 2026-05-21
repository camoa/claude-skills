import { describe, it, expect } from 'vitest';
import { normalizeError } from '../src/errors.js';

describe('normalizeError', () => {
  it('normalizes a string into an UNKNOWN-coded error', () => {
    expect(normalizeError('something broke')).toEqual({
      code: 'UNKNOWN',
      message: 'something broke',
    });
  });

  it('normalizes a plain Error using its message', () => {
    expect(normalizeError(new Error('boom'))).toEqual({
      code: 'UNKNOWN',
      message: 'boom',
    });
  });

  it('extracts status + message from a googleapis (Gaxios) error body', () => {
    const gaxiosErr = Object.assign(new Error('Request failed'), {
      response: {
        status: 429,
        data: {
          error: {
            code: 429,
            status: 'RESOURCE_EXHAUSTED',
            message: 'Quota exceeded for quota metric',
          },
        },
      },
    });
    expect(normalizeError(gaxiosErr)).toEqual({
      code: 'RESOURCE_EXHAUSTED',
      message: 'Quota exceeded for quota metric',
    });
  });

  it('falls back to HTTP_<code> when the API body has no status string', () => {
    const err = Object.assign(new Error('Bad Request'), {
      response: { status: 400, data: { error: { code: 400, message: 'Invalid request' } } },
    });
    expect(normalizeError(err)).toEqual({ code: 'HTTP_400', message: 'Invalid request' });
  });

  it('attaches failedRequest when the caller supplies one', () => {
    const failed = { replaceAllText: { containsText: { text: '{{x}}' } } };
    const result = normalizeError(new Error('batch rejected'), failed);
    expect(result.failedRequest).toEqual(failed);
    expect(result.message).toBe('batch rejected');
  });

  it('omits failedRequest entirely when none is supplied', () => {
    expect('failedRequest' in normalizeError(new Error('x'))).toBe(false);
  });

  it('uses a stable string `code` property on the error when present', () => {
    const err = Object.assign(new Error('Unknown command: frobnicate'), {
      code: 'BAD_COMMAND',
    });
    expect(normalizeError(err)).toEqual({
      code: 'BAD_COMMAND',
      message: 'Unknown command: frobnicate',
    });
  });

  it('lets a googleapis status body win over a plain string code', () => {
    const err = Object.assign(new Error('failed'), {
      code: 'SOME_NODE_CODE',
      response: { status: 403, data: { error: { status: 'PERMISSION_DENIED', message: 'denied' } } },
    });
    expect(normalizeError(err).code).toBe('PERMISSION_DENIED');
  });

  it('never throws on null, undefined, or numeric input', () => {
    expect(normalizeError(null)).toEqual({ code: 'UNKNOWN', message: 'Unknown error' });
    expect(normalizeError(undefined)).toEqual({ code: 'UNKNOWN', message: 'Unknown error' });
    expect(normalizeError(42)).toEqual({ code: 'UNKNOWN', message: 'Unknown error' });
  });
});
