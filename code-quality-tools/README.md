# Code Quality Tools

[![Listed on ClaudePluginHub](https://www.claudepluginhub.com/badge/camoa-code-quality-tools-code-quality-tools)](https://www.claudepluginhub.com/plugins/camoa-code-quality-tools-code-quality-tools?ref=badge)

**Is this code actually safe and sound, or does it just run?** Code that compiles and passes a quick glance can still carry SOLID violations, duplicated logic, missing tests, and security holes that only surface in production, or in an audit you did not choose the timing of. This plugin runs the checks that answer that question for real: TDD, SOLID, and DRY analysis plus multi-layer security scanning (Semgrep, Trivy, Gitleaks, and framework-specific SAST) for **Drupal** and **Next.js** projects. It auto-detects which one you are in, so the same commands work either way, and it correlates findings across tools instead of handing you a pile of disconnected reports.

> **Not using Claude Code?** This plugin's checks run through commands, which are Claude-Code-specific by format. The underlying `code-quality-audit` skill and its reference material port natively to Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more. See the marketplace [PORTABILITY.md](../PORTABILITY.md) for what ports and how.

## See it in action

Real commands, output trimmed to the lines that matter, on a Drupal project.

```text
$ /code-quality-tools:setup
  Detected: Drupal 11 via DDEV.
  Installing phpstan, phpmd, phpcpd, psalm, drupal/coder, drupal/security_review...
  Offered: security-guidance plugin (in-session edit scanning). GrumPHP pre-commit hook: declined (default).

$ /code-quality-tools:audit
  Running: SOLID, DRY, coverage, security...
  Hot spots: 2 files flagged by 3+ tools (highest priority)
  → audit-report.json + audit-synthesis.md written to ~/.local/state/code-quality-tools/acme-site/20260810T0912/

$ /code-quality-tools:security
  10 layers (Drupal): Drush pm:security, Composer audit, Psalm taint analysis, Semgrep, Trivy, Gitleaks...
  Critical: 0   High: 1
  → security-report.json written (same run directory)
```

Reports land outside the repository being audited, because they quote its source and name the files a secret scanner matched in. The run prints where it wrote, and `--latest` on the resolver finds it again.

Nothing here decided your architecture or waved off the one High finding. `/setup` detected the stack and asked before installing anything beyond the core toolchain. `/audit` told you which files multiple tools independently flagged, which is where the compounding risk usually lives. `/security` gave you a number, not a vibe. Full report shapes and the review-scoring rubric are in [docs/usage.md](docs/usage.md).

## When to reach for it

- **Before a commit or PR**, when you want more than "it runs" as your bar. `/audit` and `/review` are built for this.
- **Before deploying**, for the security layers a generic linter does not cover: taint analysis, dependency CVEs, secret scanning, and (Drupal) config-level checks like access-callback and raw-`db_query` patterns.
- **During a refactor**, when `/solid` or `/dry` tell you where the coupling and duplication actually are instead of where you assume they are.
- **On a contentious design call**, when `/architecture-debate` or `/security-debate` run competing AI perspectives against each other instead of settling for one confident pass.
- **As the gate underneath `ai-dev-assistant`**, which wraps these same checks (its `/validate-tdd`, `/validate-solid`, `/validate-dry`, `/validate-security` commands) with task context. Install this plugin on its own if you just want the checks without the full research-to-review lifecycle.

## Commands

`/code-quality-tools:setup` detects your project type and installs the matching toolchain. Every other command auto-detects too, so you never specify Drupal or Next.js yourself.

| Command | Purpose |
|---------|---------|
| `/setup` | Interactive install and configuration wizard. |
| `/audit` | Full audit with cross-tool synthesis (`--json` for CI). |
| `/review` | Rubric-scored code review, `/50` scale (`--json` for CI). |
| `/ultrareview` | Cloud multi-agent deep review (paid after free quota). |
| `/security` | Security scan: 10 layers (Drupal) or 7 layers (Next.js). |
| `/security-debate` | 3-agent team (Defender, Red Team, Compliance) on security findings. |
| `/architecture-debate` | 3-agent team (Pragmatist, Purist, Maintainer) on design decisions. |
| `/solid` | SOLID/architecture check. |
| `/dry` | Duplication finder. |
| `/coverage` | Test coverage. |
| `/lint` | Code standards. |
| `/tdd` | TDD workflow with a test watcher. |
| `/generate-review-md` | Generate the v2 `REVIEW.md` used to tune `/review`'s rubric. |

All commands are prefixed `code-quality-tools:`. Rubric scoring, the cross-tool synthesis logic, report file shapes, thresholds, CI templates, and watch-mode/scheduled-sweep options are in [docs/usage.md](docs/usage.md) and the plugin's `references/`.

## Installation

```bash
/plugin install code-quality-tools@camoa-skills
```

Then run the setup wizard, which analyses your project, asks what you want, and writes
`.code-quality.json`:

```
/code-quality-tools:setup
```

`.code-quality.json` is the contract. It records your layout, the tools to install and the
scope each runs in, the PHPStan level, and whether git hooks are wanted. A deterministic
script reads it to install, configure and verify. Nothing about the install is decided by
prose. Commit it, and the next person gets the toolchain you got.

Two things are worth knowing before you run it. **GrumPHP is optional.** It is installed
only when you enable git hooks, because it writes a pre-commit hook into your repository.
And the installer **verifies its own work and fails when it cannot**. It checks that phpcs
registers the Drupal standard, that the PHPStan extension registered `mglaman`, and that a
staged violation drives the hook to a non-zero exit. An install that cannot fail tells you
nothing, so this one exits non-zero rather than reporting a pass it did not earn.

Or install manually.

**Drupal (via DDEV):**
```bash
ddev composer require --dev \
  phpstan/phpstan:^2.0 \
  phpmd/phpmd:^2.15 \
  systemsdk/phpcpd:^9.0 \
  vimeo/psalm:^6.0 \
  drupal/coder:^9.0 \
  drupal/security_review \
  roave/security-advisories:dev-master
```

**Next.js:**
```bash
npm install --save-dev \
  eslint \
  @typescript-eslint/parser \
  @typescript-eslint/eslint-plugin \
  eslint-plugin-security \
  jest \
  @testing-library/react \
  @testing-library/jest-dom \
  jscpd \
  madge
```

**System tools (both):** [Semgrep](https://semgrep.dev/docs/getting-started/), [Trivy](https://trivy.dev/latest/getting-started/installation/), [Gitleaks](https://github.com/gitleaks/gitleaks#installing).

**Code intelligence (optional, recommended):** install a code-intelligence plugin (`php-lsp` for Drupal, `typescript-lsp` for Next.js) plus its language-server binary so `/solid`, `/dry`, and `/review` resolve inherited and config-wired relationships semantically via Claude Code's LSP tool. Not required: commands fall back to full-file reads without it. See `skills/code-quality-audit/references/code-intelligence.md`.

### Requirements

**Drupal:** DDEV, Drupal 10.3+ or 11.x, PHP 8.2+ (8.3+ recommended). All tools run inside the DDEV container.

**Next.js:** Node.js 18+, npm or yarn, TypeScript recommended.

> To control which of this plugin's commands and skills are available, use `/plugin` (plugin skills are not affected by the `skillOverrides` setting, and slash commands are not skills, so neither can be muted that way).

## Where this fits in defense-in-depth

This plugin is the whole-codebase, CI-grade SAST stage. It is one layer among several Claude Code already gives you, not a replacement for the others: **security-guidance** (a separate plugin, offered during `/setup`) watches Claude's own edits in-session. Native `/security-review` is a one-shot, diff-scoped pass. **Code Review** (`/code-review ultra`) covers the PR with full-codebase context. This plugin adds the framework-aware, multi-tool SAST and the OWASP-mapped debate none of the others run:

**Drupal, 10 layers:** Drush `pm:security`, Composer audit, PHPCS security rules (OWASP/CIS), Psalm taint analysis (XSS/SQLi data flow), custom Drupal patterns (raw `db_query`, form/access-callback checks), Security Review module, Semgrep (20,000+ rules), Trivy, Gitleaks, Roave Security Advisories.

**Next.js, 7 layers:** npm audit, ESLint security plugins, custom React/Next.js patterns (XSS, eval, navigation), Semgrep, Trivy, Gitleaks, Socket CLI (supply chain).

Report shapes, thresholds, CI templates, and DAST tooling (OWASP ZAP, Nuclei) for pre-production scanning are in [docs/usage.md](docs/usage.md) and `skills/code-quality-audit/references/operations/dast-tools.md`.

## Version

See `CHANGELOG.md` for the full history.

## License

MIT
