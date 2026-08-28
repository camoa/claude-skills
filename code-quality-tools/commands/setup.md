---
description: Interactive setup wizard to install and configure code quality tools for Drupal/Next.js projects. Use when user says "install quality tools", "set up PHPStan", "configure linting", "add code quality", "first time setup", "install ESLint", "setup security tools". Detects project type, runs the interview, and writes the config the installer reads.
allowed-tools: Read, Bash, Grep, Glob, AskUserQuestion, Write
argument-hint: optional|project-path
---

# Setup Wizard

Interactive wizard that decides what this project needs, writes `.code-quality.json`, and
hands off to the installer.

## Usage

```
/code-quality-tools:setup [project-path]
```

## The boundary this command sits on

You keep the judgment. The script keeps the execution. `.code-quality.json` is the line
between them, and it is a file rather than a step, so nothing the user ends up with was
re-typed by a model on its way there.

- **Detection is a script.** Anything discoverable from the filesystem, the package
  manifests or the installed binaries is detected, never asked.
- **Selection is an interview, and it is the only interview.** Which tools, how strict,
  which paths, hooks or CI or both. No amount of detection produces a preference.
- **The config is the artifact and the handoff.** Every judgement has to be expressible
  in it. A judgement that cannot be written into the config means the schema is short a
  field, not that logic belongs back in this prose.
- **Execution is a script and it fails closed.** It refuses a malformed config naming
  the field, refuses to write outside its expected paths, and installs in a declared
  order.
- **Verification is a script and it is separate from execution.** A model asking itself
  whether the install worked verifies nothing.

**This command is the only writer of `.code-quality.json` in this plugin.** An audit run
that finds the file missing derives an equivalent config in memory, announces it in full,
and tells the user that this command is what persists one. So no audit leaves a
`.code-quality.json` behind — a file nobody could tell apart from one a person authored.

That is the whole of the claim, and the narrow version is the true one. The install an
audit runs after deriving does write to the project, exactly as it does from a config
file: Composer edits `composer.json` for the resolved packages, and the `templates[]`
entries are placed at the project root unless a file of that name is already there. The
derived run names `composer.json` and each of those files before it places them, and
`references/config-schema.md` says the same. Leaving the templates out of the derived path
would be the tidier-sounding choice and the wrong one: it would leave PHPStan reading no
config on exactly the projects that never ran this command, which is PHPStan analysing
Drupal as plain PHP and exiting 0.

## Steps

1. **Detect.** Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/detect-environment.sh"`.
   Do not re-implement any of it. What it resolves — project type, the Drupal root and
   therefore the web root, DDEV availability, what is already installed — is what goes
   into `project` in the config. In particular `project.layout.web_root` is the value
   that script already computed; deriving it a second time here is how the two would
   come to disagree.

2. **Read the codebase.** Look at what is already there: an existing `phpstan.neon` or
   `phpunit.xml.dist`, a `grumphp.yml`, a CI workflow, how much custom PHP exists, and
   whether the code is legacy enough to need a baseline. This is the part that needs
   judgment and is why this is a command and not a script.

3. **Interview.** Ask, and record the answers in the config:
   - **Which tools.** The full inventory is below. Default to everything for the
     detected stack.
   - **PHPStan level** (`phpstan.level`, default 5). This field is the single source of
     truth for the level; nothing else in the plugin restates a number.
   - **Thresholds**: coverage (default 80), complexity (default 10), duplication
     (default 5%), security severity (default medium).
   - **Git hooks: yes or no, defaulting to no.** This one answer controls both the hook
     registration and the hook runner's package. GrumPHP attaches hooks at
     package-install time, so consent for the package and consent for the hooks are the
     same answer, and the installer refuses a config that says otherwise.
   - **CI workflows**, independently of hooks.

4. **Write `.code-quality.json`** at the project root, against
   `skills/code-quality-audit/schema/code-quality.schema.json`. Resolve each chosen tool
   through `skills/code-quality-audit/schema/tool-catalog.json` and copy its concrete
   packages, `scope`, `allow_plugins` and `bin` into the config. The schema and the
   scope rule are documented in
   `skills/code-quality-audit/references/config-schema.md`.

5. **Install.** One command:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/install-tools.sh"
   ```

   It reads the config you just wrote, writes `config.allow-plugins` before installing
   anything, installs each tool at its scope, places the templates with the layout
   substituted, registers the hook if one was consented to, and then runs
   `install-verify.sh` in a separate process. It exits non-zero when the install did not
   complete. Do not install a package or copy a template yourself: the whole point of
   the config is that there is one install path and it is that script.

6. **Read the verification result.** `install-verify.sh` asserts three things that are
   false on a normal install today and produce no error: that `phpcs -i` lists Drupal,
   that extension-installer's `GeneratedConfig.php` names mglaman, and that a staged
   known violation drives the hook non-zero. A check that could not apply reports
   `skipped` with a reason, never `passed`. Report what it found rather than
   paraphrasing it as success.

7. **Offer the optional extras** below (LSP, `security-guidance`, CI workflows).

8. **Run a baseline audit** and report it.

## What gets installed

<!-- BEGIN GENERATED: tool-catalog -->
<!-- Generated from skills/code-quality-audit/schema/tool-catalog.json.
     Do not modify this region directly; edit the catalog and run `make setup-doc`.
     `make setup-doc-check` fails when this region and the catalog disagree. -->

| Tool | Package | Scope | Category |
|---|---|---|---|
| `phpstan` | phpstan/phpstan ^2.0 | project | static-analysis |
| `phpstan-extension-installer` | phpstan/extension-installer ^1.4 | project | static-analysis |
| `phpstan-drupal` | mglaman/phpstan-drupal ^2.1.2 | project | static-analysis |
| `phpstan-deprecation-rules` | phpstan/phpstan-deprecation-rules ^2.0 | project | static-analysis |
| `coder` | drupal/coder ^9.0 | project | standards |
| `rector` | palantirnet/drupal-rector ^1.1 | project | standards |
| `phpunit` | drupal/core-dev * | project | testing |
| `roave` | roave/security-advisories dev-master | project | security |
| `grumphp` | phpro/grumphp ^2.0 | project | hooks |
| `phpmd` | phpmd/phpmd ^2.15 | isolated | quality |
| `phpcpd` | systemsdk/phpcpd ^9.0 | isolated | quality |
| `php-security-linter` | yousha/php-security-linter ^3.1 | isolated | security |
| `psalm` | vimeo/psalm ^6.0 | isolated | security |
| `eslint` | eslint<br>eslint-config-next<br>@typescript-eslint/eslint-plugin<br>eslint-plugin-react-hooks<br>eslint-config-prettier<br>eslint-plugin-security<br>eslint-plugin-no-secrets | project | static-analysis |
| `jest` | jest<br>@jest/globals<br>jest-environment-jsdom<br>@testing-library/react<br>@testing-library/jest-dom | project | testing |
| `jscpd` | jscpd | project | quality |
| `madge` | madge | project | static-analysis |
| `typescript` | typescript<br>@types/node<br>@types/react | project | static-analysis |
| `socket` | @socketsecurity/cli | project | security |
| `husky` | husky<br>lint-staged | project | hooks |
| `jq` | _(no package; installed on the machine)_ | machine | quality |
| `semgrep` | _(no package; installed on the machine)_ | machine | security |
| `trivy` | _(no package; installed on the machine)_ | machine | security |
| `gitleaks` | _(no package; installed on the machine)_ | machine | security |
| `pcov` | _(no package; installed on the machine)_ | machine | testing |
| `inotifywait` | _(no package; installed on the machine)_ | machine | quality |
<!-- END GENERATED: tool-catalog sha256:a371766a2b392fb8c462cdfa1cbc273afe2d3545c5445f39de425bcb37120615 -->

`scope` is assigned by a stated rule, not per tool taste:

> A tool is `project` when it autoloads the project's own code, or when it works only as an edge in the project's own dependency resolution. Everything else that the audit machinery alone invokes is `isolated`. Anything with no PHP or npm package at all is `machine`.

`isolated` tools go into their own `vendor-bin/<tool>/` namespace via
`bamarni/composer-bin-plugin` and never enter the project's `require-dev`. `machine`
tools are reported with an install hint and never installed: this plugin does not pipe a
moving branch of somebody's install script into `sh`, and does not write
`/usr/local/bin`, during what you asked to be an audit.

## Code Intelligence Plugins (recommended)

The `/code-quality-tools:solid`, `/code-quality-tools:dry`, and `/code-quality-tools:review` commands go deeper when Claude Code's built-in **LSP tool** is active — it resolves references, interface implementations, and call hierarchies that grep cannot see, and it reports type errors automatically after every edit. The tool is inactive until a code-intelligence plugin **and** its language-server binary are installed:

| Project | Plugin | Server binary |
|---------|--------|---------------|
| Drupal / PHP | `php-lsp` | `intelephense` |
| Next.js / TypeScript | `typescript-lsp` | `typescript-language-server` |

```bash
/plugin install php-lsp@claude-plugins-official        # or typescript-lsp@claude-plugins-official
```

Then install the language-server binary so it is on `$PATH` (see each plugin's README for the exact package). If `/plugin` shows `Executable not found in $PATH`, the binary is missing.

This is **recommended, not required** — every command falls back to full-file reads when no LSP plugin is present. Analysis-depth gains and the Drupal `.module`/`.inc`/`.theme` indexing caveat: `skills/code-quality-audit/references/code-intelligence.md`.

## In-Session Security Plugin (recommended, optional)

The official **security-guidance** plugin reviews Claude's *own* code edits for vulnerabilities while it works — a fast per-edit pattern match (no model call), a background end-of-turn diff review, and a deeper agentic review on each commit/push Claude makes — and feeds findings back into the same session for Claude to fix. It is the **in-session** layer of defense in depth: it reduces what reaches the PR (Code Review / `/code-review ultra`) and the whole-codebase scan (`/code-quality-tools:security`) without replacing either.

This plugin's audits scan the *whole tree*; security-guidance watches Claude's *live edits*. They complement each other.

**Soft offer — never auto-install.** Ask the user (plain chat, not a silent install):

> Install the in-session **security-guidance** plugin? It reviews Claude's own edits for vulnerabilities as it works, in addition to this plugin's whole-tree scans. [y/N]

On **yes**, have the user run (the install needs network + their consent, so the wizard does not run it for them):

```
/plugin install security-guidance@claude-plugins-official
/reload-plugins
```

Prerequisites: Claude Code **2.1.144+**, `python3` on `PATH`, and a git repository. On first run it creates a virtual environment under `~/.claude/security/` (needs `pip` + network); if that install fails it falls back to a single-shot commit review. Once installed it runs automatically — nothing to invoke. If the marketplace isn't found, run `/plugin marketplace add anthropics/claude-plugins-official` first, then retry.

Default is **No**. To enable it for everyone who clones the repo, add it to checked-in `.claude/settings.json` under `enabledPlugins` instead (see the plugin's docs).

## Git Hooks

Ask once, default **No**:

> Install git hooks to lint staged files on every commit? [y/N]

The answer becomes `git_hooks.enabled` in the config, and it controls the package as well
as the hook. The hook only checks **files staged for the current commit**
(`context: git-staged-files`); heavier checks stay in CI. The placed `grumphp.yml` ships
`phpcs` (Drupal standards) and `phpstan` only, and deliberately excludes:

- **phpcpd** — directory-scoped, too slow for pre-commit
- **phpunit** — runs the full suite; lives in CI instead
- **phpmd** — noisy on legacy code; opt in by adding `phpmd:` to the placed file

Verification of the hook is not this command's job, and it is not an empty commit: an
empty commit stages no files, so a `git-staged-files` hook inspects an empty set and
passes. That is a verification that cannot fail. `install-verify.sh` stages a known
violation, runs the hook, asserts it goes non-zero, and restores the index.

To remove later: `vendor/bin/grumphp git:deinit && composer remove --dev phpro/grumphp`.

On Next.js the hook runner is Husky with `lint-staged`; the same consent gate applies.

## CI workflows (independent of hooks)

Both are opt-in and independent — install one, both, or neither:

- `skills/code-quality-audit/templates/ci/github-drupal.yml` → `.github/workflows/quality.yml` — full quality battery on push/PR to main.
- `skills/code-quality-audit/templates/ci/github-drupal-pr.yml` → `.github/workflows/quality-pr.yml` — **changed-files-only** review of PRs; posts a sticky comment with synthesis + rubric. Gate is soft by default; set repo Variable `FAIL_ON_GATE=true` to enforce.

## Baseline Audit

After installation, run an initial audit to establish a baseline: coverage, existing
security issues, duplication level, SOLID score.

Baseline saved to `$REPORT_DIR/baseline.json`, where `$REPORT_DIR` is what the scripts resolve and announce on start. There is no report-directory key in `.code-quality.json`: the location is decided by `scripts/core/report-dir.sh` and overridden with the `REPORT_DIR` environment variable, or with `REPORT_DIR_IN_REPO=1` to opt back in to an in-repo `.reports/`. It is out of the repository by default because reports quote audited source and name the files a secret scanner matched in.

## Output

This one changes the project rather than reporting on it. The command's own footprint is
one file; everything else is written by the script it hands off to, and all of it is at
the project root and on your confirmation:

- `.code-quality.json` — written by this command, always. It is the only thing this
  command writes, and this command is the only thing in the plugin that writes it.
- `composer.json` and its lock file and installed tree, from the tool installs. Composer
  writes `composer.json` itself, including the `config.allow-plugins` block; the
  installer never edits that file directly.
- `vendor-bin/<tool>/` for each `isolated` tool, plus `composer.json` there.
- `package.json` and its lock file and `node_modules`, on Next.js.
- The config templates the config asked for, at the project root, each with a provenance
  comment naming this plugin: `phpstan.neon`, `phpmd.xml`, `phpunit.xml`, `psalm.xml`,
  `grumphp.yml`. The installer **declines** to write any of them when a file it did not
  generate would be shadowed or overwritten, and says which file and why.
- `grumphp.yml` (Drupal) or `.husky/pre-commit` (Next.js), plus the git hooks themselves
  under `.git/hooks/`, only if you accept the hooks prompt. It defaults to no. The
  package and the hooks are the same consent, so declining installs neither.
- `.github/workflows/quality.yml` and `.github/workflows/quality-pr.yml`, each opt-in and independent of the other.
- `install-verify.json` and `tools-status.json` in the resolved report directory, plus
  whatever the baseline audit writes there. That is outside the repository by default;
  `scripts/core/report-dir.sh` decides and announces it.

It installs nothing outside the project, and it installs no `machine`-scope tool at all —
those are reported with a hint. The optional `security-guidance` plugin is a suggestion
the wizard prints for you to run yourself.

## Re-running Setup

Safe to re-run. Detection runs again, the interview is re-asked, the config is rewritten,
and the installer refreshes the templates **it** generated (identified by the provenance
comment) while still declining to touch any file it did not write.

## Error Handling

- **"the project type could not be determined"** — nothing is assumed. Pass
  `PROJECT_TYPE`, or write the config first.
- **`.code-quality.json (…): …` with a field named, exit 2** — the config is refused
  rather than repaired. Fix the named field.
- **"DDEV not running"** (Drupal): start DDEV (`ddev start`), or run without it — the
  installer probes rather than assuming.
- **"npm not found"** (Next.js): install Node.js.

See: `references/troubleshooting.md#setup-issues`

## Related Commands

- `/code-quality-tools:audit` - Run full audit after setup
- `/code-quality-tools:coverage` - Check test coverage
- `/code-quality-tools:security` - Run security scan
