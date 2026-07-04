## Summary

<!-- What does this PR change, and why? -->

## Checklist

- [ ] Branched off `main` (kebab-case `<type>/<slug>` name, e.g. `fix/my-change`)
- [ ] This PR touches **one plugin** (or is a repo-wide doc/config change with no plugin-specific behavior)
- [ ] If this is a **plugin release**: the 4-file version bump is done in lockstep —
      `<plugin>/plugin.json`, `<plugin>/CHANGELOG.md`, `<plugin>/README.md`, and the
      root `.claude-plugin/marketplace.json` entry — and `metadata.version` in
      `marketplace.json` was bumped per the patch/minor/major rule
- [ ] `CHANGELOG.md` entry added for this change (if user-visible)
- [ ] `/plugin-creation-tools:validate <plugin-path>` run for any plugin-structure change (commands/skills/agents/hooks/frontmatter) and passing
- [ ] No secrets, credentials, or machine-specific absolute paths introduced

## Notes for the maintainer

<!-- Anything the maintainer should know before merging (e.g. version-line conflicts with another open PR). -->

This repo's `main` branch is protected — the maintainer will review and merge; contributors do not merge their own PRs.
