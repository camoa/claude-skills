# Contributing to camoa-skills

Thanks for your interest in contributing to this marketplace of Claude Code plugins. This document describes the real workflow used in this repo — please follow it as written.

## Workflow

`main` is protected — there are no direct pushes to it. All changes land through a pull request:

1. Branch off `main`.
2. Commit your changes.
3. Push your branch.
4. Open a pull request.
5. The maintainer reviews and merges.

You will not be able to merge your own PR; that's expected. If your branch conflicts with something already merged (see the version-line conflict note below), rebase or merge `main` in and push again.

## Branch naming

Branches are kebab-case, named `<type>/<slug>`:

- `feature/<slug>` — new capability
- `fix/<slug>` — bug fix
- `docs/<slug>` — documentation-only change
- `chore/<slug>` — maintenance, tooling, non-functional cleanup

Examples from this repo's history: `feature/aida-gap-g-mechanism-challenge`, `fix/aida-migrate-to-epic-preserves-references`, `docs/root-readme-rename-banner`.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/), with the **plugin name as the scope**:

```
fix(ai-dev-assistant): correct worktree path resolution
docs(code-quality-tools): clarify security gate usage
```

When a commit is part of a **plugin release**, include the new version in the subject:

```
feat(ai-dev-assistant 5.19.0): mechanism-challenge gate
chore(drupal-htmx 1.6.1): bump dependency pin
```

**One plugin per PR is the norm.** If your change touches more than one plugin, consider splitting it into separate PRs unless the changes are genuinely coupled (e.g. a repo-wide doc pass).

## Plugin releases: the 4-file version-bump rule

When a PR changes a plugin's version, the following files move together, in lockstep, in the same commit:

1. `<plugin>/plugin.json` — bump the `version` field.
2. `<plugin>/CHANGELOG.md` — add an entry for the new version.
3. `<plugin>/README.md` — update any version references.
4. Root `.claude-plugin/marketplace.json` — update that plugin's entry (including its version).

In addition, the marketplace's own `metadata.version` in `.claude-plugin/marketplace.json` gets bumped:

- **patch** — pointer/doc-only updates to the catalog entry
- **minor** — a new plugin added to the marketplace
- **major** — a breaking change to the catalog schema itself

If you're not releasing a new plugin version (docs-only, internal refactor with no version bump), none of the above applies — just make your change and open the PR.

**Parallel-PR conflict note:** because `marketplace.json` and each plugin's `CHANGELOG.md` are shared files, two PRs bumping versions at the same time will conflict on those lines. This is expected — rebase and deconflict the version lines before merge; the maintainer will help resolve if needed.

## Plugin folder anatomy

The marketplace catalog is `.claude-plugin/marketplace.json` — it is the **only** valid marketplace manifest in this repo. Each plugin is a top-level folder containing:

- `plugin.json` — plugin manifest (name, version, description)
- `README.md` — user-facing documentation
- `CHANGELOG.md` — version history
- `CONVENTIONS.md` — plugin-root conventions (note: **not** `CLAUDE.md` — a plugin-root `CLAUDE.md` is not loaded as context by Claude Code)
- optional `commands/`, `skills/`, `agents/`, `hooks/`, `.claude/rules/` (path-scoped rule files)

## Validating plugin changes

Before opening a PR that touches a plugin's structure (commands, skills, agents, hooks, frontmatter), run:

```
/plugin-creation-tools:validate <plugin-path>
```

This checks frontmatter, structure, and best practices, and should pass before you push.

## Non-Claude-Code tools

If you're contributing from or targeting a tool other than Claude Code (Cursor, Codex, Copilot, Gemini, Cline, OpenCode, Windsurf), see `PORTABILITY.md` at the repo root for how these skills port across tools.

## A note on AI assistance

Many contributions to this repo are made with AI assistance, and commit trailers noting AI co-authorship are common in this repo's history. That's optional — it's not required of contributors and is out of scope for this document.
