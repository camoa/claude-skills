---
description: "Walk every play in the project's local user playbook, asking keep/update/remove per entry. Soft-nudge posture; quitting mid-review preserves committed edits. Designed to be /loop-able for periodic review. Introduced v3.15.0."
allowed-tools: Read, Write, Edit, Bash, Skill
---

# Playbook Review

Walk every play in the project-local user playbook one at a time. Per-play prompt: `[k]eep / [u]pdate / [r]emove / [q]uit`. Each edit writes immediately so quitting mid-review preserves committed work.

## Usage

```
/ai-dev-assistant:playbook-review
```

## What this does

### Step 1 — Resolve project context + load playbook

Run `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parse its JSON. If `userPlaybookState != "set"`:
> Refuse with: "No user playbook configured. Run `/ai-dev-assistant:set-user-playbook` first."

Invoke `scripts/playbook-read.sh` against the path. Parse JSON output.

If `plays.length == 0`:
> Print: "No structured plays found in `<path>`. (Free-form content present: <line count> lines.)" Exit cleanly.

### Step 2 — Print preamble

```
Reviewing <N> plays in <path>.
Per-play prompt: [k]eep / [u]pdate / [r]emove / [q]uit
Edits write immediately; quit mid-review preserves committed work.
```

### Step 3 — Per-play loop

For each play in order:

1. Print:
   ```
   <i>/<N>: "<title>"
   Section: <section>  Lines: <start>-<end>
   ───
   What: <what>
   Rationale: <rationale>
   When it applies: <when>
   <body excerpt, max 10 lines>
   ───
   ```

2. Ask: `[k]eep / [u]pdate / [r]emove / [q]uit`

3. Branch:
   - **`k`** → continue to next play.
   - **`u`** → enter draft-edit conversation:
     - Ask: "What changes? Paste new content or describe."
     - Compose updated play body.
     - Show unified diff.
     - Ask: `[y]es write / [n]o discard`
     - On `y`: use `Edit` to surgically replace lines `start..end` of the play with the new content; track that source lines have shifted for subsequent plays (re-parse if shift > 0).
     - On `n`: discard; treat as `keep`.
     - Continue to next play.
   - **`r`** → ask: `Confirm remove "<title>"? [y/n]`
     - On `y`: use `Edit` to remove lines `start..end` (plus surrounding blank lines for cleanliness); re-parse for line shift; continue.
     - On `n`: treat as `keep`.
   - **`q`** → exit loop. Print summary.

### Step 4 — Final summary

```
Reviewed <i>/<N> plays.
  Kept: <K>
  Updated: <U>
  Removed: <R>
  Skipped: <N - i> (quit mid-review)
```

### Step 5 — No automatic git commit

The local playbook is in the user's repo; the user runs `git add` + `git commit` themselves if they want a checkpoint. The framework does NOT auto-commit.

## Soft-nudge posture

- Never blocks
- Quit mid-review is first-class — committed edits stay; un-reviewed plays unchanged
- Each edit writes immediately (atomic per play; no batch)
- No "you should review more" nag

## Loop-able

Designed to fit `/loop` for periodic review:
```
/loop 30d /ai-dev-assistant:playbook-review
```

(or whatever cadence the user prefers — default cadence is zero; this is purely user-initiated)

## Error cases

| Scenario | Behavior |
|---|---|
| `userPlaybookState != "set"` | Refuse; exit 2 |
| Playbook file unreadable | Refuse; exit 2 |
| Parser warns about freeform fallback | Print: "File has no structured plays; review can't iterate. View raw with `/playbook-active --raw`." Exit cleanly |
| Edit/write fails mid-loop | Print error; commit what's been done; exit 1 |

## Related

- `/ai-dev-assistant:playbook-capture` — add a new play
- `/ai-dev-assistant:playbook-active` — read-only view
- `references/playbook-schema.md` — recommended structure
