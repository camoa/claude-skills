# Changelog

## 0.7.0 (2026-06-06)

### Added
- **Recipe Search mode** — a second routing path, symmetric to guide search, over the separate **agentic-recipes** catalog (`agentic-recipes.txt` + `agentic-recipes.hash`). Recipes are goal-oriented, prescriptive capability deliveries that **name** the guides/plays they need (never duplicate them) and carry a **verifier**. New `## Recipe Search` SKILL.md section: index-cache via `.hash`/`.txt`; match on `capability` + when-to-use (no match → "fall back to guide search" + STOP, never fabricate); body download-once keyed by the per-line `(sha:XXXXXXXX)` (raw markdown only, URL derived from the index line's site-url); apply by handing each named guide/play to the existing guide-search flow and **surfacing the verifier** to the caller.
- **Two modes, caller owns order** — a "Two modes" overview + a When-to-Use note state that the navigator exposes both guide search and recipe search with **no hardcoded order**; the caller (e.g. the drupal-dev-framework orchestrator) decides, typically recipe-search first then guide-search.
- **`dev-guides-recipes-cache.json`** — a new sibling cache file (same dasherized-cwd derivation as the guides cache), schema `{ index: { hash, fetched_at, content }, recipes: { <name>: { sha, fetched_at, content } } }`. Two-hash invalidation: `agentic-recipes.hash` gates the index; each per-line `sha` gates one body, checkable without a fetch. Documented in `references/cache-format.md` as a cross-plugin contract.
- **`disallowed-tools: WebFetch`** in SKILL.md frontmatter (CC-1) — turns the three prose "NEVER use WebFetch" warnings into a harness-level hard block, reinforcing the curl-only discipline for both modes.

### Unchanged
- **Guide search, `llms.txt`, and the guides cache (`dev-guides-cache.json`) are byte-for-byte untouched.** Recipe search is strictly additive.

## 0.6.0 (2026-05-21)

### Added
- **`Setup` hook for cache pre-warming** — new `hooks/setup-cache.sh` fetches `llms.hash` + `llms.txt` and writes the `{hash, fetched_at, content}` cache so the first navigator call in a project is instant. Fires only on `claude --init-only`, `claude -p --init`, or `claude -p --maintenance` — never on normal interactive startup. Pure optimization: degrades silently (no `jq`/`curl`, network down) to the existing lazy-fill-on-first-use path.
- README documentation for the `skillOverrides` setting (`user-invocable-only` / `name-only` / `off` for non-Drupal projects) and the `skillListingBudgetFraction` / `maxSkillDescriptionChars` skill-listing-budget settings.

### Changed
- **SKILL.md conciseness pass** (175 → 129 body lines). The Quick Reference + Common Mistakes, Examples, and Troubleshooting tables moved to new `references/quick-reference.md`, `references/examples.md`, and `references/troubleshooting.md`. SKILL.md keeps the 7-step workflow and a pointered See Also.

### Hygiene
- Plugin-root `CLAUDE.md` renamed to `CONVENTIONS.md` (validator ST03 — a plugin-root `CLAUDE.md` is not loaded as end-user context).
- `$schema` added to `plugin.json`.
- PreCompact hook migrated to exec form (`"args": []`).

## 0.5.1 (2026-05-21)

### Fixed
- **Cache schema normalized to a contract.** The on-disk cache had three
  incompatible shapes (`{hash,fetched}`, `{hash,fetched_at,llms_txt}`,
  `{hash,llms_txt:"see full content…"}`). Step 1 now always writes the full
  `llms.txt` markdown under a fixed `content` key with `hash` + `fetched_at`,
  and treats any cache lacking `content` as stale — refetch + backfill. This
  self-heals the legacy minimal/compact caches. The compact
  `llms_txt: "see full content…"` placeholder is no longer written.
- `references/cache-format.md` now mandates the `{hash, fetched_at, content}`
  schema and documents the exact cache-path derivation (dasherized cwd under
  `~/.claude/projects/<dir>/memory/`, with a glob fallback) as a contract that
  other plugins consume.

## 0.5.0 (2026-04-27)

### 2026-04-25 doc-refresh deltas

The 2026-04-25 Claude Code doc refresh promoted three new platform-level pages: `Admin Setup` (enterprise rollout), `Auto Mode Config` (auto-mode classifier reference, previously embedded in Permissions), and `Debug Your Config` (symptom-first triage via `/context`, `/memory`, `/doctor`, `/hooks`, `/mcp`, `/skills`, `/permissions`, `/status`). Decision: this navigator routes to **project guides** at `camoa/dev-guides` only — it does NOT route to Claude Code platform docs at `code.claude.com`. No keyword/routing changes; the three pages are listed only as out-of-scope cross-links so calling code knows they exist.

### Added
- `references/guide-index.md` — new "Out of scope: Claude Code platform docs" section listing the three new upstream pages with direct URLs and a one-line scope explanation.

### Verified
- No stale references to the old auto-mode location (auto-mode config used to live inside Permissions; now standalone). Index has no auto-mode entries.

## 0.4.0 (2026-04-20)

### Added
- Awareness of `tldr:` frontmatter and Summary column in topic routing tables
- Pre-filter workflow step to pick between candidate guides without fetching each

### Fixed
- SKILL.md frontmatter version was 0.2.0, out of sync with plugin.json 0.3.0
- Example in SKILL.md referenced non-existent `drupal/solid/` topic (actual: `drupal/solid-principles/`); also corrected the "NOT" reference from `dev-solid-principles` to `development/solid-principles`

## 0.3.0 (2026-04-08)

### Changed
- **PreCompact hook** — Simplified to output only cache location pointer. No longer dumps hash or topic count metadata into compaction.

## 0.2.3 (2026-03-20)

### Changed
- Maintenance: confirmed CLAUDE.md under 200-line limit (38 lines), no content to move
- Confirmed `user-invocable: true` is correct — no internal routing sub-skills requiring `false`

## 0.2.1 (2026-03-15)

### Added
- **PreCompact hook**: Preserves cache state (location, hash, topic count) before conversation compaction

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
