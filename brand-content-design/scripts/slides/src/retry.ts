/**
 * Exponential-backoff retry for transient Slides/Drive API failures.
 *
 * Only `429` (rate limit) and `5xx` (server) responses are retried — a `4xx`
 * such as `400`/`403`/`404` is a deterministic failure and is rethrown at once.
 * `batchUpdate` is atomic, so retrying a rejected batch is safe: nothing was
 * applied.
 */

export interface RetryOptions {
  /** Total attempts including the first. Default 4. */
  maxAttempts?: number;
  /** Base delay in ms; attempt N waits `baseDelayMs * 2^(N-1)`. Default 500. */
  baseDelayMs?: number;
  /** Injectable sleep — overridden in tests so they do not actually wait. */
  sleep?: (ms: number) => Promise<void>;
}

/** True when the error carries an HTTP status of 429 or any 5xx. */
export function isRetryable(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false;
  const status = (err as { response?: { status?: number } }).response?.status;
  if (typeof status !== 'number') return false;
  return status === 429 || (status >= 500 && status <= 599);
}

const defaultSleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Run `fn`, retrying retryable failures with exponential backoff.
 * Non-retryable errors and the final failure after `maxAttempts` are rethrown.
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  opts: RetryOptions = {},
): Promise<T> {
  const maxAttempts = opts.maxAttempts ?? 4;
  const baseDelayMs = opts.baseDelayMs ?? 500;
  const sleep = opts.sleep ?? defaultSleep;

  let attempt = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    attempt++;
    try {
      return await fn();
    } catch (err) {
      if (attempt >= maxAttempts || !isRetryable(err)) {
        throw err;
      }
      await sleep(baseDelayMs * 2 ** (attempt - 1));
    }
  }
}
