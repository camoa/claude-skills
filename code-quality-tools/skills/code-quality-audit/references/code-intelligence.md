# Code Intelligence (LSP tool)

The SOLID, DRY, and review commands run deeper and cheaper when Claude Code's built-in **LSP tool** is active. This file explains what it adds, how to enable it, and where it does *not* reach — so the commands can degrade cleanly when it is absent.

## Recommended, not required

The LSP tool needs **no permission** and is **inert when no code-intelligence plugin is installed**. Every command in this plugin keeps its grep-free, full-file-read **Type-B** pass as the guaranteed floor. Installing an LSP plugin makes the analysis sharper and reduces token cost; skipping it changes nothing about correctness.

Do **not** add `LSP` to any skill or command `allowed-tools` — it requires no permission grant, and listing it would imply a hard dependency that does not exist.

## What the LSP tool provides

Once a language server is running, Claude can (per the Tools Reference, §"LSP tool behavior"):

- Jump to a symbol's definition
- Find all references to a symbol
- Get type information at a position
- List symbols in a file or workspace
- Find implementations of an interface
- Trace call hierarchies
- Receive **automatic type errors and warnings after every file edit** — no separate build/lint step

These give semantic navigation that grep cannot: grep matches text, the language server resolves *meaning* (inheritance, interface implementation, wired dependencies).

## Enabling it

The LSP tool stays inactive until you install a code-intelligence plugin **and** its language-server binary (the plugin bundles the LSP configuration; the binary is installed separately).

| Project | Plugin | Server binary |
|---------|--------|---------------|
| Drupal / PHP | `php-lsp` | `intelephense` |
| Next.js / TypeScript | `typescript-lsp` | `typescript-language-server` |

```bash
# Install the plugin from the official marketplace
/plugin install php-lsp@claude-plugins-official
# …or
/plugin install typescript-lsp@claude-plugins-official
```

Then install the server binary so it is on `$PATH` (see each plugin's own README for the exact package). If `/plugin` shows `Executable not found in $PATH` in its Errors tab, the binary is missing.

Verify it is active: `/plugin` lists the loaded LSP servers; a "diagnostics found" indicator appears after edits (press **Ctrl+O** to view inline).

## What each command gains

### `/code-quality:solid`

SOLID's hardest checks are exactly the ones grep cannot do:

- **Liskov / Interface Segregation** — `find-implementations` on an interface enumerates *every* subtype; each override can then be checked for contract compatibility. A real check, not a heuristic.
- **Dependency Inversion** — `find-references` on a concrete class shows whether high-level modules depend on it directly instead of on an abstraction.
- **Single Responsibility** — `call-hierarchy` gives real fan-in/fan-out, instead of inferring "reasons to change" from file size.

### `/code-quality:dry`

PHPCPD and jscpd find **textual** clones. `find-references` finds **semantic** duplication they miss entirely — e.g. the same service resolved inline at 14 call sites is a DRY/DIP violation even though the surrounding text differs at every site.

### `/code-quality:review`

The rubric's *Separation of concerns* and *Testability* categories otherwise rest on the reviewer's impression. `call-hierarchy` shows whether a controller/form method reaches into a data layer N levels deep; `find-references` and definition resolution show how dependencies are actually wired — evidence instead of impression.

## Caveats — keep the full-read floor

- **Availability varies by language and environment** (Discover Plugins guide). When in doubt, fall back to the Type-B full-file read.
- **Drupal `.module` / `.inc` / `.theme` files** are PHP but carry non-`.php` extensions. `intelephense` may not index them by default. For those files, the grep-free full-read pass remains the guaranteed path — do not assume LSP coverage.
- **Large projects** — language servers can consume significant memory. If a project is heavy, disabling the plugin and relying on built-in search is a valid trade-off.
- **Monorepos** — a language server may report false-positive unresolved-import diagnostics for internal packages when the workspace is not configured for it; these do not affect edit correctness.

When the LSP tool is unavailable or a file falls outside its index, the command MUST fall back to reading full class hierarchies, interfaces, and service definitions — the behavior documented in each command's "Reading strategy" note.
