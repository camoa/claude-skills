# Changelog

## 0.2.0 (2026-03-13)

### Fixed
- **WebFetch contradiction**: cache-format.md and CHANGELOG said "WebFetch for topic/guide pages" while SKILL.md said "NEVER use WebFetch" — all files now consistently use `curl -s` with raw GitHub URLs
- Added `allowed-tools: Read, Bash, Glob, Grep, Write` to SKILL.md — explicitly excludes WebFetch so Claude cannot default to it

### Changed
- Model upgraded from `haiku` to `sonnet` for more reliable enforcement of curl-only fetching
- Pushy description with comprehensive trigger phrases and proactive enforcement
- Added `version` and `user-invocable: true` to SKILL.md frontmatter
- Updated README with fetching rules, troubleshooting, and current usage

## 0.1.0 (2026-03-09)

- Initial release
- Hash-based caching workflow (`llms.hash` + `llms.txt`)
- KG metadata disambiguation via `guide-meta:` in topic `index.md`
- Two-hop routing: `llms.txt` -> topic `index.md` -> specific guide
- Fallback keyword table in `references/guide-index.md`
- All fetches use `curl -s` via Bash (raw content, no AI summarization)
