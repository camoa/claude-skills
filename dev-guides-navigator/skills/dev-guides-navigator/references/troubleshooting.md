# Troubleshooting

What to do when a step in the navigator workflow fails.

| Problem | Fix |
|---------|-----|
| `curl` fails (network error) | Serve the last-fetched index from the store: `"$STORE_SH" index-content llms`. It is the full catalog as of the last successful fetch. An empty store means no index has ever been fetched — report that, do not guess a URL |
| No topic matches the task | Broaden keywords, check category sections in llms.txt, or task may not need a guide |
| Cache file path unknown | Use Bash: `echo ~/.claude/projects/*/memory/` to find the project memory directory |
| Guide content too large for context | Request only the specific section from the routing table, not the entire guide |
