/**
 * AUTH SETUP TEMPLATE (generic, stack-neutral) — ai-dev-assistant.
 * /setup-visual-regression copies this to tests/visual/.auth/<ctx>.setup.ts
 * for each distinct non-null auth_context, substituting the tokens.
 *
 * The PLUGIN provides this shell. HOW you log in is stack-specific and is
 * supplied by your project's process recipe / stack reference scaffold, NOT here.
 * Contract: log in by your stack's mechanism, then save the session to
 * __STORAGE_STATE__. Then delete the throw below. Nothing here assumes a framework.
 */
import { test as setup } from '@playwright/test';

const STORAGE_STATE = '__STORAGE_STATE__';

setup('authenticate __AUTH_CONTEXT__', async ({ page }) => {
  // TODO (your process recipe fills this): perform the login for "__AUTH_CONTEXT__".
  //   Example only (your framework's recipe supplies the real step): await login(page, '<credentials>')
  throw new Error(
    'auth setup for "__AUTH_CONTEXT__" is not implemented. Your process recipe must ' +
    'fill tests/visual/.auth/__AUTH_CONTEXT__.setup.ts with the login for this stack, ' +
    'then save storageState to ' + STORAGE_STATE + ' and remove this throw.'
  );
  // await page.context().storageState({ path: STORAGE_STATE });
});
