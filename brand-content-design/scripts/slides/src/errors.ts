/**
 * Error normalization — turn anything thrown by `googleapis` (or anywhere
 * else) into a structured {@link SlidesError}.
 *
 * Contract: never throws, never leaks credentials. Only the API's own `code`
 * and `message` strings are copied out — request bodies are attached only when
 * the caller explicitly supplies them via `failedRequest`.
 */
import type { SlidesError } from './types.js';

/** Shape of the error body googleapis nests under `response.data`. */
interface GoogleApiErrorBody {
  error?: { code?: number; message?: string; status?: string };
}

/** Loosely-typed view of a Gaxios-style error for safe field access. */
interface GaxiosLike {
  message?: unknown;
  name?: unknown;
  code?: unknown;
  response?: { status?: number; data?: GoogleApiErrorBody };
}

/**
 * Normalize an unknown thrown value into a {@link SlidesError}.
 *
 * @param err           Anything caught — a GaxiosError, an Error, a string, etc.
 * @param failedRequest Optional batchUpdate request the caller knows was
 *                      rejected; attached verbatim to aid the merge engine.
 */
export function normalizeError(err: unknown, failedRequest?: unknown): SlidesError {
  const result: SlidesError = { code: 'UNKNOWN', message: 'Unknown error' };
  if (failedRequest !== undefined) {
    result.failedRequest = failedRequest;
  }

  if (typeof err === 'string') {
    result.message = err;
    return result;
  }

  if (!err || typeof err !== 'object') {
    return result;
  }

  const e = err as GaxiosLike;

  // Prefer the structured googleapis error body when present.
  const apiError = e.response?.data?.error;
  if (apiError) {
    result.code =
      apiError.status ??
      (typeof apiError.code === 'number' ? `HTTP_${apiError.code}` : 'UNKNOWN');
    if (typeof apiError.message === 'string') {
      result.message = apiError.message;
    }
    return result;
  }

  // No structured body — prefer a stable string `code` the error carries
  // itself (AuthConfigError, command errors), then the HTTP status.
  if (typeof e.code === 'string') {
    result.code = e.code;
  } else if (typeof e.response?.status === 'number') {
    result.code = `HTTP_${e.response.status}`;
  }
  if (typeof e.message === 'string') {
    result.message = e.message;
  }
  return result;
}
