# claude-skills

Run repo tasks through `make`. Do not call test files, the linter, or the
validator directly.

| Job | Command |
|---|---|
| Run all tests | `make test` |
| Run one plugin's tests | `make test-<plugin>` |
| Check shell scripts | `make lint` |
| Rewrite the lint baseline | `make lint-baseline` |
| Check plugin structure | `make validate` |
| Check plugin manifests | `make manifests` |
| Everything, same as the PR check | `make ci` |

Before opening a PR: `make ci`. It runs all four checks even when one
fails, so one run shows every problem. CI runs the same four the same way.

## What each check can fail on

- `make lint` compares shellcheck against `scripts/lint-baseline.txt`, a
  committed list of `<path>:<CODE>` pairs. A pair that is not in the
  baseline fails. A baseline pair that no longer occurs is reported as
  fixed and passes. Regenerating is deliberate: `make lint-baseline`, then
  commit the diff. The baseline keys on file and code, never line number,
  so unrelated edits do not disturb it. It also means a file going from
  one instance of a code to five does not fail.
- `make validate` fails on validator errors; validator warnings print
  without failing. It checks the catalog as well as each plugin folder.
- Neither `lint` nor `validate` can pass without doing work. Zero scripts
  found, zero plugins found, or a missing baseline all fail. When
  shellcheck or the `claude` CLI is missing they skip locally and say so,
  but fail outright when `CI` is set, so a CI step never goes green
  without checking anything.
- `make validate` does not catch a plugin folder missing from the catalog,
  and treats a version disagreement with the catalog as a warning only.
  `make manifests` is the check that fails on both.

Only `make test` and `make lint` scan files, and both only look at
git-tracked ones. A brand-new script or test is not picked up until it is
`git add`ed.

New test: put it where that plugin already keeps its tests. `make test`
picks it up.

## Before `make test` works

- **bash 4 or newer.** macOS ships bash 3.2 and some tests fail on it for
  that reason alone. `brew install bash`.
- **PyYAML.** `ai-dev-assistant/scripts/fm-helpers.sh` reads task
  frontmatter with it. Without it the reader returns nulls and the tests
  that depend on it fail. `pip install pyyaml`.
- **gitleaks.** `code-quality-tools`' secret-scanning spec gates whole
  sections on `command -v gitleaks`. Without the binary those sections do
  not run, and the spec still exits 0 and still prints a passing total, so
  nothing tells you they were skipped. Measured on this tree: **742
  assertions with gitleaks, 458 without — 284 silently disappear, and both
  runs report "0 failed".** Everything about secret detection, history
  scanning and redaction is in the missing 284. `brew install gitleaks`.
- **shellcheck**, for `make lint` only. `brew install shellcheck`. The
  version matters: `scripts/lint-baseline.txt` names the version that
  produced it on its first line, and `make lint` says so when yours
  differs. CI pins the same version in `.github/workflows/ci.yml`.
- **git history.** Some tests compare a file against its version on
  `main`, so a shallow clone fails them.

None of these dependencies fail loudly on their own. A green `make test`
on a machine missing gitleaks is a smaller green than it looks.

## Where things live

- Plugin folders are top level. Each has `.claude-plugin/plugin.json`.
- The catalog is `.claude-plugin/marketplace.json`.
- Per-plugin conventions are in `<plugin>/CONVENTIONS.md`, not `CLAUDE.md`.
  Claude Code does not load a plugin-root `CLAUDE.md`.
- Repo task scripts are in `scripts/`.

## Releasing a plugin

Four files move together in one commit: `plugin.json`, `CHANGELOG.md`,
`README.md`, and the plugin's entry in `.claude-plugin/marketplace.json`.
`make manifests` checks the version agrees between `plugin.json` and the
catalog entry. The two `description` fields are deliberately different and
are not compared. Full rules are in `CONTRIBUTING.md`.
