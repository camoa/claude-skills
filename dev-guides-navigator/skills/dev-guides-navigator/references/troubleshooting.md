# Troubleshooting

What to do when a step in the navigator workflow fails.

| Problem | Fix |
|---------|-----|
| `curl` fails (network error) | Fall back to `references/guide-index.md` for keyword-to-URL lookup |
| No topic matches the task | Broaden keywords, check category sections in llms.txt, or task may not need a guide |
| Cache file path unknown | Use Bash: `echo ~/.claude/projects/*/memory/` to find the project memory directory |
| Guide content too large for context | Request only the specific section from the routing table, not the entire guide |
