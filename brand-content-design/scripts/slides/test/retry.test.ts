import { describe, it, expect, vi } from 'vitest';
import { withRetry, isRetryable } from '../src/retry.js';

/** Build an Error carrying a Gaxios-style `response.status`. */
function httpError(status: number): Error {
  return Object.assign(new Error(`HTTP ${status}`), { response: { status } });
}

describe('isRetryable', () => {
  it('treats 429 and 5xx as retryable', () => {
    expect(isRetryable(httpError(429))).toBe(true);
    expect(isRetryable(httpError(500))).toBe(true);
    expect(isRetryable(httpError(503))).toBe(true);
  });

  it('treats 4xx (other than 429) and statusless errors as non-retryable', () => {
    expect(isRetryable(httpError(400))).toBe(false);
    expect(isRetryable(httpError(404))).toBe(false);
    expect(isRetryable(new Error('plain'))).toBe(false);
    expect(isRetryable(null)).toBe(false);
  });
});

describe('withRetry', () => {
  it('returns immediately when fn succeeds on the first try', async () => {
    const fn = vi.fn().mockResolvedValue('ok');
    await expect(withRetry(fn, { sleep: vi.fn() })).resolves.toBe('ok');
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('retries retryable failures and applies exponential backoff', async () => {
    const fn = vi
      .fn()
      .mockRejectedValueOnce(httpError(429))
      .mockRejectedValueOnce(httpError(503))
      .mockResolvedValue('ok');
    const sleep = vi.fn().mockResolvedValue(undefined);
    await expect(withRetry(fn, { sleep, baseDelayMs: 500 })).resolves.toBe('ok');
    expect(fn).toHaveBeenCalledTimes(3);
    expect(sleep).toHaveBeenNthCalledWith(1, 500);
    expect(sleep).toHaveBeenNthCalledWith(2, 1000);
  });

  it('does not retry a non-retryable error', async () => {
    const fn = vi.fn().mockRejectedValue(httpError(400));
    const sleep = vi.fn();
    await expect(withRetry(fn, { sleep })).rejects.toThrow('HTTP 400');
    expect(fn).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it('gives up after maxAttempts and rethrows the last error', async () => {
    const fn = vi.fn().mockRejectedValue(httpError(429));
    const sleep = vi.fn().mockResolvedValue(undefined);
    await expect(withRetry(fn, { sleep, maxAttempts: 3 })).rejects.toThrow('HTTP 429');
    expect(fn).toHaveBeenCalledTimes(3);
    expect(sleep).toHaveBeenCalledTimes(2);
  });
});
