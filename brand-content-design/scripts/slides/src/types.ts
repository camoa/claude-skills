/**
 * Shared types for the brand-content-design Slides/Drive API client.
 *
 * See architecture.md (slides_api_client) — this module is the contract the
 * sibling renderer children (scaffolder, merge engine) compile against.
 */
import type { slides_v1, drive_v3 } from 'googleapis';

/**
 * The two googleapis service objects SlidesClient depends on.
 * Injecting these (rather than credentials) is the DIP seam that lets unit
 * tests pass fakes — see architecture.md "SOLID Principles Applied".
 */
export interface SlidesServices {
  slides: slides_v1.Slides;
  drive: drive_v3.Drive;
}

/** Credential configuration, resolved from environment variables by auth.ts. */
export type AuthConfig =
  | { kind: 'service-account'; keyFile: string }
  | {
      kind: 'oauth';
      clientId: string;
      clientSecret: string;
      refreshToken: string;
    };

/** OAuth scopes the client may request (narrowest-first). */
export type Scope =
  | 'https://www.googleapis.com/auth/presentations'
  | 'https://www.googleapis.com/auth/drive.file'
  | 'https://www.googleapis.com/auth/drive';

/** A map of merge tag -> replacement value (literal text, or an image URL). */
export type TagMap = Record<string, string>;

/** Export formats reachable via the Drive API files.export endpoint. */
export type ExportMimeType = 'application/pdf' | 'image/png';

/**
 * Structured error. Normalized from a googleapis error by errors.ts.
 * MUST NOT carry credentials, tokens, or token-bearing URLs.
 */
export interface SlidesError {
  /** Stable, machine-readable error code (e.g. "BATCH_REJECTED", "AUTH_MISSING_ENV"). */
  code: string;
  /** Human-readable message. */
  message: string;
  /** The batchUpdate request the API rejected, when identifiable. */
  failedRequest?: unknown;
}

/** Result envelope the CLI writes to stdout — exactly one of ok/error. */
export type ResultEnvelope =
  | { ok: true; result: unknown }
  | { ok: false; error: SlidesError };

/** A command document the CLI reads from stdin. */
export interface CommandDoc {
  command: string;
  args: Record<string, unknown>;
}

/* --- Method result shapes (the typed surface of SlidesClient) --- */

export interface CreatePresentationResult {
  presentationId: string;
}

export interface BatchUpdateResult {
  replies: slides_v1.Schema$Response[];
}

export interface CopyFileResult {
  fileId: string;
}

export interface ThumbnailResult {
  /**
   * Short-lived thumbnail URL returned by the Slides API. The caller (the
   * visual-diff gate) fetches the image bytes itself — the client returns the
   * URL only, keeping this module pure transport.
   */
  contentUrl: string;
}

export interface ReplaceResult {
  /** Number of occurrences replaced, keyed by tag. */
  occurrencesByTag: Record<string, number>;
}
