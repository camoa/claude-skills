# `.code-quality.json` — the contract between the wizard and the installer

`/code-quality-tools:setup` detects, asks, analyses, and writes this file. Nothing
downstream of it is a model's judgement: `scripts/core/cqt-install.sh` reads it and
installs, and `scripts/core/install-verify.sh` proves the gates it installed can fail.

Two files, deliberately:

| File | Ships with | Trusted | Read by |
|---|---|---|---|
| `schema/tool-catalog.json` | the plugin | yes | the wizard, `scripts/gen-setup-doc.sh`, `cqt_config_derive` |
| `.code-quality.json` | the project | **no** | `cqt-config.sh`, and nothing else directly |

Collapsing them would put untrusted content behind a trusted read. The installer's only
input is a validated config, so the catalog never reaches it.

## The scope rule

Every tool carries a `scope`, and the scope is assigned by this rule rather than per-tool
taste. Stated verbatim, the same sentence `schema/tool-catalog.json` carries in its
`scope_rule` field:

> A tool is `project` when it autoloads the project's own code, or when it works only as an edge in the project's own dependency resolution. Everything else that the audit machinery alone invokes is `isolated`. Anything with no PHP or npm package at all is `machine`. An entry may sit on the wrong side of this predicate only when it records a `scope_reason` saying so in those terms and a `reversal_condition` naming the observation that would move it; `psalm` is the one such entry, and its generated config hands it an explicit autoloader rather than sharing a resolver.

The predicate is `bamarni/composer-bin-plugin`'s own rule of thumb — "limit this approach
to tools which do not autoload your code" — and it excludes most of what this plugin
installs. `isolated` is the **minority case**: four analysers, `phpmd/phpmd`,
`systemsdk/phpcpd`, `yousha/php-security-linter` and `vimeo/psalm`. Everything a developer
runs against their own source stays `project`, because it has to resolve that source:
`mglaman/phpstan-drupal` boots Drupal's container, `drupal/coder` registers a phpcs
standard through `dealerdirect/phpcodesniffer-composer-installer` and works only as an edge
in the project's resolution, PHPUnit boots the application, Rector rewrites it.

Three scopes in the vocabulary does not mean a third of the toolchain in each.

Two entries need their reason read rather than assumed, and both carry it in the catalog:

- `roave/security-advisories` is a metapackage with no code whose only mechanism is a
  conflict edge inside the resolver. `project` is the only scope in which it does anything.
- `vimeo/psalm` sits on the wrong side of the predicate's letter, because taint analysis
  resolves the classes it follows. It stays `isolated` because its dependency tree is the
  heaviest of the four, and the generated `psalm.xml` hands it
  `<autoloader>vendor/autoload.php</autoloader>` explicitly. Its reversal condition is
  recorded in the catalog beside the scope.

`npm` has no isolation mechanism analogous to `composer-bin-plugin`, so every Next.js tool
is `project` because that is the only bucket available, not because the predicate puts it
there. Each of those entries says so.

## The five matrix dimensions

One fixture per dimension round-trips through the installer; that is criterion 1's verify
method, and it lives in section IN-B of `scripts/tests/false-clean-spec.sh`.

| Dimension | Key | Values |
|---|---|---|
| project type | `project.type` | `drupal` \| `nextjs` \| `monorepo` |
| layout | `project.layout.web_root` | `web` \| `docroot` \| `""` (root layout) |
| scope mix | `tools.<id>.scope` | `project` \| `isolated` \| `machine` |
| strictness | `phpstan.level` | 0–10 |
| hooks | `git_hooks.enabled` | `true` \| `false` |

## Shape

```json
{
  "schema_version": "3.0",
  "project": {
    "type": "drupal",
    "layout": { "web_root": "web", "modules": "web/modules/custom", "themes": "web/themes/custom" }
  },
  "tools": {
    "phpstan":  { "scope": "project",  "packages": [{ "name": "phpstan/phpstan", "constraint": "^2.0" }], "bin": "phpstan" },
    "phpmd":    { "scope": "isolated", "packages": [{ "name": "phpmd/phpmd", "constraint": "^2.15" }], "bin": "phpmd" },
    "gitleaks": { "scope": "machine",  "packages": [], "bin": "gitleaks", "install_hint": "brew install gitleaks" }
  },
  "phpstan": { "level": 5 },
  "templates": ["drupal/phpstan.neon", "drupal/phpmd.xml", "drupal/phpunit.xml"],
  "git_hooks": { "enabled": false, "tool": null, "tasks": [] },
  "thresholds": { "coverage": 80, "complexity": 10, "duplication": 5, "security_severity": "medium" }
}
```

## What the config carries, and what it deliberately does not

**Resolved packages, not tool ids alone.** The wizard resolves ids through the catalog and
writes the concrete name and constraint. Three consequences, all of them the point: the
installer has exactly one input; a project's config is afterwards a readable record of what
was installed; and drift between catalog and config becomes *visible* through the
invariants below rather than impossible through a coupling that hides the question.

**No `report_dir` key.** Report location is resolved per run by
`scripts/core/report-dir.sh`, and overridden with the `REPORT_DIR` environment variable or
`REPORT_DIR_IN_REPO=1`. Freezing it at install time would put a second answer in the tree.

**No key is optional-with-a-silent-default.** Every key is either required or its absence
has a stated, printed meaning. An empty `constraint` and an empty `web_root` are values,
not omissions.

## Invariants: what `cqt-config.sh` checks beyond shape

Schema validation checks shape. These check meaning, and they are why the Drupal PHPStan
set is guaranteed by whichever entry point the user arrived through:

1. `project.type == "drupal"` implies `tools` contains `phpstan/extension-installer`,
   `mglaman/phpstan-drupal` and `phpstan/phpstan-deprecation-rules`, all at scope
   `project`. Sourced from `required_when` in the catalog, enforced at read time.
2. Every Composer package name matches `^[a-z0-9]([_.-]?[a-z0-9]+)*/[a-z0-9]([_.-]?[a-z0-9]+)*$`;
   every npm name matches the npm grammar. Nothing else may reach a command line.
3. Every `templates[]` entry is in the schema's fixed allowlist.
4. `git_hooks.enabled == false` implies no consent-gated tool appears in `tools`.
5. `project.layout.web_root` is `web`, `docroot` or empty, and no value under `layout`
   contains `..` or starts with `/`.

A config that fails any of these is refused with the field named, and exits **2**. It is
not repaired: repairing a contract silently is how the two install paths came to disagree
in the first place.

## A missing file is derived, announced, and never persisted

When an audit finds no `.code-quality.json`, `cqt_config_derive` builds a **complete**
config from the catalog for the detected project type and layout, announces it in full,
and hands it to the same validator a file gets. **No `.code-quality.json` is written** —
the derived config lives in memory for the duration of the run and nowhere else.

That is a narrower claim than "nothing is written", and the narrower one is the true one.
The install this feeds does write to the project, exactly as it does from a file-driven
config: Composer edits `composer.json` for the resolved packages, and the `templates[]`
entries are placed at the project root unless a file of that name is already there. The
announcement names those files before the install runs. The alternative — skipping
template placement on the derived path — would leave PHPStan reading no config on the
projects that never ran `/setup`, which is PHPStan analysing Drupal as plain PHP and
exiting 0.

`/code-quality-tools:setup` is the only writer of `.code-quality.json` in this plugin.
Writing a config file is what an init command is for — `composer init`,
`npm init @eslint/config`. No tool in this space writes one during a normal run: PHPStan
and Prettier hold zero-config defaults in memory, ESLint 9 fails fast and points at
`npm init @eslint/config`. An audit that invents a file in somebody's repository leaves
something indistinguishable from a file a person authored.

The derived path is still the opposite of a fail-open default. `install-tools.sh:25-27`
used to read two scalars out of `environment.json` and then do
`PROJECT_TYPE="${PROJECT_TYPE:-drupal}"`, so a missing or renamed field produced a Drupal
install on a project nobody had established was Drupal, behind a `[WARN]` nobody reads.
Here nothing is assumed: everything is derived from the catalog and printed.

## Why `jq` is required here and optional elsewhere

`full-audit.sh` and `detect-environment.sh` treat missing `jq` as first-class and read
`environment.json` with `grep -oP`. That is deliberate, and it is correct for a *detection
record*: a detection that could not run should degrade. `.code-quality.json` is a
*contract file*. `cqt-config.sh` therefore requires `jq` and says so, matching
`check_version_drift()`'s own reasoning for choosing `jq` over a pattern.
