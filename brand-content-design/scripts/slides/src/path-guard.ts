/**
 * Path confinement — refuse user-controlled paths that escape the workspace
 * or carry suspicious shapes. The CLI is a stdin-JSON adapter, so when it is
 * wrapped by an MCP/HTTP service every path argument is effectively untrusted.
 *
 * Policy for `manifestPath`:
 *   - must end with `.render-manifest.json`
 *   - the resolved parent directory must exist and (after `realpath`, so
 *     symlinks are followed) must be inside the workspace root
 *   - workspace root = `BCD_SLIDES_WORKSPACE` (resolved) when set, else `cwd`
 *   - the file itself need not exist (first-render writes a new manifest);
 *     the parent dir is the trust boundary, not the file
 *
 * Policy for arbitrary read paths (e.g. `imagePaths` values, `customFontFile`):
 *   - `realpath` of the file must be inside the workspace root
 *   - file must exist (we are about to readFileSync it)
 *
 * On failure: throws an {@link InvalidPathError} carrying the stable
 * `INVALID_PATH` code — the CLI envelope surfaces it as
 * `{ ok: false, error: { code: "INVALID_PATH", message } }`.
 */
import { realpathSync, existsSync } from 'node:fs';
import { resolve, dirname, sep } from 'node:path';
import { InvalidPathError } from './errors.js';

/** Suffix every render manifest must use. */
const MANIFEST_SUFFIX = '.render-manifest.json';

/**
 * Workspace root for path confinement. Resolves `BCD_SLIDES_WORKSPACE` when
 * set (must exist; symlinks followed). Falls back to `process.cwd()`.
 */
function workspaceRoot(env: NodeJS.ProcessEnv = process.env): string {
  const raw = env.BCD_SLIDES_WORKSPACE;
  const root = raw && raw.length > 0 ? resolve(raw) : process.cwd();
  if (!existsSync(root)) {
    throw new InvalidPathError(
      `Workspace root "${root}" does not exist. Set BCD_SLIDES_WORKSPACE to a valid directory or run from a real cwd.`,
    );
  }
  return realpathSync(root);
}

/**
 * Is `child` (already realpath-resolved absolute) inside `parent` (already
 * realpath-resolved absolute)? Suffix-with-`sep` guards against the
 * `/work-suffix` vs `/work` confusion.
 */
function isInside(child: string, parent: string): boolean {
  if (child === parent) return true;
  const parentWithSep = parent.endsWith(sep) ? parent : parent + sep;
  return child.startsWith(parentWithSep);
}

/**
 * Confine a manifest path. Returns the absolute, validated path.
 *
 * @throws {InvalidPathError} on wrong extension, missing parent dir, or
 *   parent-dir escape from the workspace root.
 */
export function confineManifestPath(
  manifestPath: string,
  env: NodeJS.ProcessEnv = process.env,
): string {
  if (!manifestPath.endsWith(MANIFEST_SUFFIX)) {
    throw new InvalidPathError(
      `manifestPath must end with "${MANIFEST_SUFFIX}" (got "${manifestPath}").`,
    );
  }
  const root = workspaceRoot(env);
  const absolute = resolve(manifestPath);
  const parent = dirname(absolute);
  if (!existsSync(parent)) {
    throw new InvalidPathError(
      `manifestPath parent directory "${parent}" does not exist.`,
    );
  }
  const parentReal = realpathSync(parent);
  if (!isInside(parentReal, root)) {
    throw new InvalidPathError(
      `manifestPath "${manifestPath}" resolves outside the workspace root "${root}".`,
    );
  }
  // Reconstruct an absolute path anchored under the realpath'd parent so the
  // returned value is canonical (caller persists this).
  return resolve(parentReal, absolute.slice(parent.length + (parent.endsWith(sep) ? 0 : 1)));
}

/**
 * Confine a read path (file must exist + must resolve inside the workspace).
 * Used for `imagePaths` values and `customFontFile`.
 *
 * @throws {InvalidPathError} on missing file or workspace escape.
 */
export function confineReadPath(
  inputPath: string,
  label: string,
  env: NodeJS.ProcessEnv = process.env,
): string {
  const absolute = resolve(inputPath);
  if (!existsSync(absolute)) {
    throw new InvalidPathError(`${label} "${inputPath}" does not exist.`);
  }
  const real = realpathSync(absolute);
  const root = workspaceRoot(env);
  if (!isInside(real, root)) {
    throw new InvalidPathError(
      `${label} "${inputPath}" resolves outside the workspace root "${root}".`,
    );
  }
  return real;
}
