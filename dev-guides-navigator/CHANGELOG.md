# Changelog

## 0.1.0 (2026-03-09)

- Initial release
- Hash-based caching workflow (`llms.hash` + `llms.txt`)
- KG metadata disambiguation via `guide-meta:` in topic `index.md`
- Two-hop routing: `llms.txt` -> topic `index.md` -> specific guide
- Fallback keyword table in `references/guide-index.md`
- Uses `curl` for raw llms.txt/hash fetches, WebFetch for topic/guide pages
