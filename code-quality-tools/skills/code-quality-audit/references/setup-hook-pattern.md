# Setup-hook pattern — one-time CI tool bootstrap

The quality tools this plugin drives (PHPStan, PHPMD, Psalm, Semgrep, Trivy, Gitleaks, ESLint, …) must be installed before an audit can run. In CI, that install should happen **once** during pipeline initialization, not on every audit. Claude Code's **`Setup` hook event** is the canonical place for it.

This is an **opt-in pattern** — the plugin does **not** ship a `Setup` hook. You add it to your own project, exactly as with the `StopFailure` alerting pattern in `CONVENTIONS.md`.

## When the `Setup` event fires

`Setup` does **not** fire on a normal `claude` launch. It fires only when you start Claude Code explicitly for initialization or maintenance:

| Matcher       | Fires on                                   |
| :------------ | :------------------------------------------ |
| `init`        | `claude --init-only` or `claude -p --init`  |
| `maintenance` | `claude -p --maintenance`                   |

`--init` and `--maintenance` fire `Setup` **only when combined with `-p`** (print mode); in an interactive session those flags do not. `claude --init-only` runs `Setup` hooks plus `startup`-matcher `SessionStart` hooks, then exits without starting a conversation — ideal as a dedicated CI step.

`Setup` hooks receive a `trigger` field (`"init"` or `"maintenance"`), have access to `CLAUDE_ENV_FILE`, and support only `command` and `mcp_tool` handler types. They **cannot block** — on a non-zero exit, execution continues (stderr reaches the user only on exit code 2, or under `--verbose`).

> **`Setup` alone does not guarantee tooling is present.** Because it never fires on a normal launch, a developer who skips the init step has no tools. Keep the audit scripts' existing "tool not found → run `/code-quality-tools:setup`" guidance as the fallback. `Setup` optimizes the CI path; it does not replace first-use detection.

## CI pipeline step

Run the dedicated init once, early in the pipeline:

```bash
claude --init-only          # fires Setup hooks, then exits
# … later steps run /code-quality-tools:audit etc. with tools already installed
```

## Wiring the hook

Add the hook to your **project's** `.claude/settings.json` (or `.claude/hooks.json`). Use **exec form** (`args` array) — the preferred form per the Hooks Reference:

```json
{
  "hooks": {
    "Setup": [
      {
        "matcher": "init",
        "hooks": [
          { "type": "command", "command": "composer", "args": ["install", "--dev"] }
        ]
      }
    ]
  }
}
```

If your quality tools are declared as dev dependencies in `composer.json` / `package.json` (recommended), the hook is just `composer install --dev` or `npm ci` — the dependency manifest is the source of truth and the hook only triggers it.

To invoke this plugin's installer directly instead, point at `install-tools.sh`:

```json
{ "type": "command",
  "command": "<path-to-installed-plugin>/skills/code-quality-audit/scripts/core/install-tools.sh",
  "args": [] }
```

Notes on `install-tools.sh`:

- It takes **no positional arguments** — it is driven by environment variables (`PROJECT_TYPE`, `REPORT_DIR`, `DDEV_AVAILABLE`). Set them in the hook environment or let it auto-detect from `.reports/environment.json`.
- For Drupal it requires a running DDEV container and exits non-zero if DDEV is absent. A `Setup` hook cannot block, so a failed install will not stop the session — have the pipeline verify tool availability after `--init-only` and fail there if needed.
- `${CLAUDE_PLUGIN_ROOT}` resolves **only inside plugin-shipped hooks**. A hook in your project's own `settings.json` must use a real path (or a CI variable) instead.

## Related

- `CONVENTIONS.md` → "StopFailure Hook (CI pipelines)" — the sibling opt-in CI hook pattern
- `commands/setup.md` — the interactive `/code-quality-tools:setup` wizard (the local, first-time counterpart to this CI pattern)
- `references/premerge-gate-routine.md` — running the audit itself in CI once tools are installed
