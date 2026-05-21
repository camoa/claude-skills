/**
 * Credential resolution for the Slides/Drive API client.
 *
 * Credentials come ONLY from environment variables — never hard-coded, never
 * committed. `resolveAuthConfig` is pure (env in → config out) and is the
 * unit-tested seam; `createAuthClient` constructs the google-auth-library
 * client. Error messages name env vars, never credential values.
 */
import { GoogleAuth, OAuth2Client } from 'google-auth-library';
import type { AuthConfig, Scope } from './types.js';

/** Environment variable names. */
export const ENV = {
  saKeyFile: 'BCD_SLIDES_SA_KEY_FILE',
  oauthClientId: 'BCD_SLIDES_OAUTH_CLIENT_ID',
  oauthClientSecret: 'BCD_SLIDES_OAUTH_CLIENT_SECRET',
  oauthRefreshToken: 'BCD_SLIDES_OAUTH_REFRESH_TOKEN',
} as const;

/** Narrowest scopes that still permit copy/export of app-created templates. */
export const DEFAULT_SCOPES: Scope[] = [
  'https://www.googleapis.com/auth/presentations',
  'https://www.googleapis.com/auth/drive.file',
];

/** Raised when env vars are missing or incomplete. Carries a stable `code`. */
export class AuthConfigError extends Error {
  readonly code = 'AUTH_CONFIG';
  constructor(message: string) {
    super(message);
    this.name = 'AuthConfigError';
  }
}

/**
 * Resolve an {@link AuthConfig} from environment variables.
 * Service-account credentials take precedence over OAuth when both are set.
 *
 * @throws {AuthConfigError} when no credentials, or an incomplete OAuth trio.
 */
export function resolveAuthConfig(
  env: Record<string, string | undefined>,
): AuthConfig {
  const keyFile = env[ENV.saKeyFile];
  if (keyFile) {
    return { kind: 'service-account', keyFile };
  }

  const clientId = env[ENV.oauthClientId];
  const clientSecret = env[ENV.oauthClientSecret];
  const refreshToken = env[ENV.oauthRefreshToken];

  if (clientId || clientSecret || refreshToken) {
    if (!clientId || !clientSecret || !refreshToken) {
      throw new AuthConfigError(
        `Incomplete OAuth configuration: set all of ${ENV.oauthClientId}, ` +
          `${ENV.oauthClientSecret}, and ${ENV.oauthRefreshToken}.`,
      );
    }
    return { kind: 'oauth', clientId, clientSecret, refreshToken };
  }

  throw new AuthConfigError(
    `No credentials found. Set ${ENV.saKeyFile} for a service account, or the ` +
      `${ENV.oauthClientId}/${ENV.oauthClientSecret}/${ENV.oauthRefreshToken} ` +
      `trio for OAuth.`,
  );
}

/** An authorized client googleapis accepts as its `auth` option. */
export type AuthClient = GoogleAuth | OAuth2Client;

/**
 * Build an authorized client from a resolved {@link AuthConfig}.
 * `scopes` apply to the service-account path; an OAuth refresh token already
 * encodes its granted scopes.
 */
export function createAuthClient(
  config: AuthConfig,
  scopes: Scope[] = DEFAULT_SCOPES,
): AuthClient {
  if (config.kind === 'service-account') {
    return new GoogleAuth({ keyFile: config.keyFile, scopes });
  }
  const client = new OAuth2Client({
    clientId: config.clientId,
    clientSecret: config.clientSecret,
  });
  client.setCredentials({ refresh_token: config.refreshToken });
  return client;
}
