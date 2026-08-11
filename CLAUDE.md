# claude-skills

Run repo tasks through `make`. Do not call test files, the linter, or the
validator directly.

| Job | Command |
|---|---|
| Run all tests | `make test` |
| Run one plugin's tests | `make test-<plugin>` |
| Check shell scripts | `make lint` |
| Check plugin structure | `make validate` |
| Check versions and descriptions | `make manifests` |
| Everything, same as the PR check | `make ci` |

Before opening a PR: `make ci`.

New test: put it where that plugin already keeps its tests. `make test`
picks it up.

## macOS

`make test` needs bash 4 or newer. macOS ships bash 3.2, and some tests
fail on it for that reason alone. Install a current bash first:

```
brew install bash
```

## Where things live

- Plugin folders are top level. Each has `.claude-plugin/plugin.json`.
- The catalog is `.claude-plugin/marketplace.json`.
- Per-plugin conventions are in `<plugin>/CONVENTIONS.md`, not `CLAUDE.md`.
  Claude Code does not load a plugin-root `CLAUDE.md`.
- Repo task scripts are in `scripts/`.

## Releasing a plugin

Four files move together in one commit: `plugin.json`, `CHANGELOG.md`,
`README.md`, and the plugin's entry in `.claude-plugin/marketplace.json`.
`make manifests` checks the version and description agree. Full rules are
in `CONTRIBUTING.md`.
