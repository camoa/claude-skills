import { describe, it, expect } from 'vitest';
import { GoogleAuth, OAuth2Client } from 'google-auth-library';
import { resolveAuthConfig, createAuthClient, AuthConfigError } from '../src/auth.js';

const SA = 'BCD_SLIDES_SA_KEY_FILE';
const CID = 'BCD_SLIDES_OAUTH_CLIENT_ID';
const SECRET = 'BCD_SLIDES_OAUTH_CLIENT_SECRET';
const REFRESH = 'BCD_SLIDES_OAUTH_REFRESH_TOKEN';

describe('resolveAuthConfig', () => {
  it('resolves a service-account config from the key-file env var', () => {
    expect(resolveAuthConfig({ [SA]: '/secrets/sa.json' })).toEqual({
      kind: 'service-account',
      keyFile: '/secrets/sa.json',
    });
  });

  it('resolves an oauth config from the full client/secret/refresh trio', () => {
    expect(
      resolveAuthConfig({ [CID]: 'cid', [SECRET]: 'csec', [REFRESH]: 'rtok' }),
    ).toEqual({ kind: 'oauth', clientId: 'cid', clientSecret: 'csec', refreshToken: 'rtok' });
  });

  it('prefers the service account when both credential sets are present', () => {
    const cfg = resolveAuthConfig({
      [SA]: '/secrets/sa.json',
      [CID]: 'cid',
      [SECRET]: 'csec',
      [REFRESH]: 'rtok',
    });
    expect(cfg.kind).toBe('service-account');
  });

  it('throws AuthConfigError on a partial oauth trio', () => {
    expect(() => resolveAuthConfig({ [CID]: 'cid' })).toThrow(AuthConfigError);
  });

  it('throws AuthConfigError when no credentials are set', () => {
    expect(() => resolveAuthConfig({})).toThrow(AuthConfigError);
  });

  it('error messages name env vars, never credential values', () => {
    try {
      resolveAuthConfig({ [CID]: 'super-secret-id' });
      expect.unreachable('should have thrown');
    } catch (err) {
      expect((err as Error).message).toContain(CID);
      expect((err as Error).message).not.toContain('super-secret-id');
    }
  });
});

describe('createAuthClient', () => {
  it('builds a GoogleAuth for a service-account config', () => {
    const client = createAuthClient({ kind: 'service-account', keyFile: '/secrets/sa.json' });
    expect(client).toBeInstanceOf(GoogleAuth);
  });

  it('builds an OAuth2Client for an oauth config', () => {
    const client = createAuthClient({
      kind: 'oauth',
      clientId: 'cid',
      clientSecret: 'csec',
      refreshToken: 'rtok',
    });
    expect(client).toBeInstanceOf(OAuth2Client);
  });
});
