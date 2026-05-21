# Quick Reference

The condensed workflow and the common mistakes to avoid. The full step-by-step
method is in `SKILL.md`.

## Workflow at a glance

| Step | Action |
|------|--------|
| Cache check | `curl -s` llms.hash, compare with cached hash |
| Find topic | Match task keywords in cached `llms.txt` |
| Get routing table | `curl -s` raw GitHub URL for topic `index.md` |
| Disambiguate | Check `guide-meta:` concepts/not fields |
| Pre-filter | Read Summary column in routing table; pick best-match guide |
| Get guide | `curl -s` raw GitHub URL for specific guide `.md` |
| Apply | Extract patterns and implement, don't summarize |

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Using WebFetch instead of curl | **Always use `curl -s`** — WebFetch returns AI summaries or 400KB HTML shells |
| Reading guide and only summarizing | Extract patterns and apply to current task |
| Grabbing first keyword match | Check guide-meta `not` fields for disambiguation |
| Fetching llms.txt every time | Check llms.hash first, use cache |
| Ignoring `requires` | Load prerequisites first |
