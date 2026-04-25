# Playbook Conflict Schema v1.0

**Introduced:** drupal-dev-framework v3.15.0
**Owner:** `scripts/playbook-conflicts-write.sh`
**Consumers:** `commands/playbook-active.md`, `skills/guide-integrator` (writer side)

`<project>/.claude/playbook-conflicts.log` is an append-only JSONL file that records every detected conflict between the active playbook layers. One line per detection. Used for diagnostic review by the user and by `/playbook-active`. No consumer reads it programmatically for decision-making in v1 — it's a receipt, not a state file.

## 1. Location

```
<project>/.claude/playbook-conflicts.log
```

The `.claude/` directory is per-project (different from `~/.claude/` which is per-user). Created on first conflict detection if absent.

## 2. Format

JSONL — one valid JSON object per line. Append-only. No header, no footer, no in-line comments.

## 3. Line shape

```json
{
  "schema_version": "1.0",
  "detected_at": "2026-04-24T23:45:00Z",
  "session_id": "<session-id-or-null>",
  "topic": "font-sizing",
  "conflict_type": "local-vs-shipped | multi-set-contradiction",
  "playbook_set_citation": {
    "set": "drupal/best-practices/camoa",
    "guide": "font-sizing-rfs",
    "summary": "Use @include font-size(); never raw font-size:"
  },
  "local_citation": {
    "path": "/abs/path/to/playbook.md",
    "section": "CSS / SCSS",
    "title": "Permits raw font-size: for non-text utility classes",
    "line": 18,
    "summary": "Permits raw font-size: for non-text utility classes"
  },
  "second_set_citation": null,
  "winner": "local",
  "resolution_source": "precedence-rule | per-topic-resolution | user-prompt"
}
```

## 4. Field contracts

| Field | Type | Values |
|---|---|---|
| `schema_version` | string | `"1.0"` at v3.15.0 |
| `detected_at` | string | ISO-8601 UTC with `Z` suffix |
| `session_id` | string \| null | Whatever session identifier the framework has access to; `null` when unknown |
| `topic` | string | A short topic key (e.g., `"font-sizing"`, `"bem-methodology"`). Free-form; should match across runs so dedup tooling can group by topic |
| `conflict_type` | enum | `"local-vs-shipped"` (covered by precedence rule) \| `"multi-set-contradiction"` (resolved by user prompt or stored resolution) |
| `playbook_set_citation` | object | Citation for the shipped opinion. Always present for both conflict types |
| `local_citation` | object \| null | Citation for the local opinion. Present when `conflict_type == "local-vs-shipped"`; `null` when `conflict_type == "multi-set-contradiction"` |
| `second_set_citation` | object \| null | Citation for the second shipped opinion. Present when `conflict_type == "multi-set-contradiction"`; `null` when `conflict_type == "local-vs-shipped"` |
| `winner` | enum | `"local"` (local-vs-shipped) \| `"<set-id>"` (the set ID that won the multi-set contradiction) |
| `resolution_source` | enum | `"precedence-rule"` (local-vs-shipped — local always wins) \| `"per-topic-resolution"` (multi-set, user chose previously, value applied from `project_state.md`) \| `"user-prompt"` (multi-set, user prompted this session) |

### 4.1 `playbook_set_citation` sub-object

| Field | Type | Description |
|---|---|---|
| `set` | string | The dev-guides path slug (e.g., `drupal/best-practices/camoa`) |
| `guide` | string | The specific guide ID within the set (e.g., `font-sizing-rfs`) |
| `summary` | string | One-line restatement of the play, for quick reading |

### 4.2 `local_citation` sub-object

| Field | Type | Description |
|---|---|---|
| `path` | string | Absolute path to the local playbook file |
| `section` | string | The H2 section under which the play lives |
| `title` | string | The H3 title of the play |
| `line` | integer | Source line number where the play starts |
| `summary` | string | One-line restatement |

## 5. Append semantics

`scripts/playbook-conflicts-write.sh`:

1. Validates the input JSON line is well-formed and has `schema_version: "1.0"` (refuses with stderr if not — never silently skips).
2. Creates `<project>/.claude/` if absent.
3. Appends the line + `\n` to `playbook-conflicts.log` using `>>` (atomic append on POSIX systems).
4. Does NOT dedupe. Caller is responsible for deciding whether to write (e.g., once per session per topic — caller-side state, not file-state).
5. Does NOT lock. Concurrent writes from multiple Claude Code sessions could interleave on slow filesystems; v1 accepts this risk (rare in practice).

## 6. Reading

`/playbook-active` reads with:

```bash
tail -n 50 <project>/.claude/playbook-conflicts.log | jq -r '...'
```

Default display: last 50 entries, formatted as a human-readable list. No paging in v1.

## 7. Invariants

- **Append-only.** No tool truncates, edits, or reorders. Users wanting to clear it run `rm` themselves.
- **One line per detection.** No multi-line entries. Newline-terminated.
- **UTF-8.** Citations may contain em-dashes, smart quotes, etc. — preserved verbatim.
- **Schema version on every line.** Even if v1.1 ships later, old lines stay v1.0; readers branch on `schema_version`.

## 8. Versioning policy

- **Major bumps** are breaking: changes to required field names, types, or enums.
- **Minor bumps** are additive: new optional fields. Existing readers ignore them.
- **Patch bumps** do not exist.

v1.0 is committed for v3.15.0.

## 9. Non-goals

- **No conflict resolution from the log.** The log records what happened; it does NOT influence future decisions. Future decisions re-detect, re-cite, and re-prompt as needed.
- **No automatic rotation/compaction.** Log grows monotonically. Real-world projects accumulate dozens, not thousands, of conflicts. v2 candidate if files grow large.
- **No schema validation tooling shipped.** v3.15.0 documents the shape; v2 could ship a `.schema.json` if hand-editing the log becomes a real pain.
- **No cross-project aggregation.** Each project has its own log. Cross-project rollups are user concern.
