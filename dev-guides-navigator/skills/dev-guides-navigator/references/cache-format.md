# Cache Format

## Location

```
~/.claude/projects/{project-hash}/memory/dev-guides-cache.json
```

## Structure

```json
{
  "hash": "<contents of llms.hash>",
  "llms_txt": "<contents of llms.txt>"
}
```

## Flow

**First time (no cache):**
1. `curl -s` both `llms.hash` and `llms.txt`
2. Save both to cache file

**Subsequent times (cache exists):**
1. `curl -s` `llms.hash` (tiny file)
2. Compare with cached hash
   - Same → use cached `llms.txt`
   - Different → re-fetch `llms.txt`, update cache

**Finding a guide:**
1. Match task keywords against cached `llms.txt` topics
2. WebFetch the topic's `index.md` (routing table)
3. Pick the specific guide from "I need to..." table
4. WebFetch that individual guide `.md`
5. Apply the guide content to the task
