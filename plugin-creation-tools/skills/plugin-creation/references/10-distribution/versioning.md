# Versioning Plugins

Use semantic versioning to communicate changes and manage updates.

## Semantic Versioning

Format: `MAJOR.MINOR.PATCH`

| Component | When to Increment | Example |
|-----------|-------------------|---------|
| MAJOR | Breaking changes | 1.0.0 → 2.0.0 |
| MINOR | New features (backward compatible) | 1.0.0 → 1.1.0 |
| PATCH | Bug fixes (backward compatible) | 1.0.0 → 1.0.1 |

## What Counts as Breaking?

### Breaking Changes (MAJOR)

- Removing commands
- Renaming commands
- Changing command behavior significantly
- Removing agents or skills
- Changing required arguments
- Removing hook events

### New Features (MINOR)

- Adding new commands
- Adding new agents
- Adding new skills
- Adding optional arguments
- Adding new hook events
- New configuration options

### Bug Fixes (PATCH)

- Fixing command behavior
- Fixing hook execution
- Correcting documentation
- Performance improvements
- Security fixes (unless breaking)

## Version Locations

Set version in **one place only** — do not set it in both plugin.json and the marketplace.json entry.

- **Relative-path plugins** (local/monorepo): set version in the marketplace.json entry, omit from plugin.json.
- **External source plugins** (GitHub, npm, pip): set version in plugin.json manifest, omit from the marketplace.json entry.

### plugin.json

```json
{
  "name": "my-plugin",
  "version": "2.1.0"
}
```

### marketplace.json

```json
{
  "plugins": [
    {
      "name": "my-plugin",
      "version": "2.1.0"
    }
  ]
}
```

## CHANGELOG Format

Use Keep a Changelog format:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [2.1.0] - 2025-01-15

### Added
- New `/optimize` command for performance analysis
- Support for TypeScript files in formatter

### Changed
- Improved error messages in deployment command

### Fixed
- Fixed race condition in hook execution

## [2.0.0] - 2025-01-01

### Changed
- BREAKING: Renamed `/deploy-staging` to `/deploy`
- BREAKING: Changed argument order for `/review`

### Removed
- BREAKING: Removed deprecated `/old-command`

### Added
- New `deployment-agent` for CI/CD tasks

## [1.5.0] - 2024-12-15

### Added
- New security scanning skill
- Hook support for pre-commit validation
```

## Release Process

### 1. Determine Version

Based on changes since last release:
- Any breaking changes? → MAJOR
- New features? → MINOR
- Only fixes? → PATCH

### 2. Update Files

```bash
# Update plugin.json
# Update marketplace.json
# Update CHANGELOG.md
```

### 3. Commit

```bash
git add .
git commit -m "Release v2.1.0"
git tag v2.1.0
git push origin main --tags
```

### 4. Announce

For significant releases:
- Update README if needed
- Notify team/users
- Document migration for breaking changes

## Migration Guides

For breaking changes, provide migration guide in CHANGELOG:

```markdown
## [2.0.0] - 2025-01-01

### Migration Guide

**From v1.x to v2.0:**

1. `/deploy-staging` renamed to `/deploy`:
   - Old: `/deploy-staging production`
   - New: `/deploy production`

2. `/review` argument order changed:
   - Old: `/review file.js summary`
   - New: `/review summary file.js`

3. Removed `/old-command`:
   - Use `/new-command` instead
   - Same functionality with improved output
```

## Pre-Release Versions

For testing before stable release, append a hyphenated label:

```
2.0.0-alpha.1
2.0.0-beta.1
2.0.0-rc.1
```

Example: `2.0.0-beta.1` indicates the first beta build of the upcoming 2.0.0 release. Pre-release versions sort before the stable release and signal opt-in testing status.

## Version Display

Users can check installed versions:

```bash
/plugin list
```

Output includes version information.

## Best Practices

1. **Start at 1.0.0** for initial release
2. **Document all changes** in CHANGELOG
3. **Be conservative** with breaking changes
4. **Provide migration guides** for MAJOR versions
5. **Use pre-release** for testing
6. **Tag releases** in git

## See Also

- `packaging.md` - preparing plugins
- `marketplace.md` - distribution
- [Keep a Changelog](https://keepachangelog.com/)
- [Semantic Versioning](https://semver.org/)
