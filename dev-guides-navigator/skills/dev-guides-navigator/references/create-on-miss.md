# Create-on-Miss (maintainer mode)

This is the **navigator side only** of the create-on-miss flow (v0.8.0+). When
guide search finds **no** guide for a topic **and** the local dev-guides source
repo is detected, the navigator **offers** to author the missing guide and
**hands off** to the repo's own `/create-guide` command. It never authors,
partitions, commits, or deploys anything itself.

For ordinary consumers (no repo present) this flow **never fires** — guide search
falls back exactly as it always has. Consumer behavior is unchanged.

## Navigator hard rules

- **Detect + offer + hand off — nothing more.** Authoring belongs to the
  dev-guides repo's own agents/scripts via `/create-guide`. The navigator stays
  thin.
- **Offer, never auto.** On a genuine miss, *ask* "no guide exists for X —
  author one?" Do not silently start writing.
- **Never author, commit, push, or deploy** from the navigator. Surface the
  handoff and STOP.
- **Maintainer-only.** No repo detected → consumer mode → no offer, no behavior
  change.
- **Misses only, not refreshes.** This flow fires when a topic is *absent*.
  Refreshing/updating an existing guide is out of scope for this wave.

## When it applies

All of these must hold:

1. **Genuine guide-search miss** — the guide-search flow (SKILL.md Core Workflow
   steps 1–7) plus the `references/guide-index.md` fallback keyword table are
   exhausted with **no** matching topic or guide. A weak/partial match is not a
   miss — only a true absence is.
2. **Maintainer mode** — the dev-guides source repo is detected (below).

If either is false, do not offer. (Recipe-search misses defer to guide search;
only a *guide-search* miss can escalate to create-on-miss.)

## Detection (maintainer mode)

Resolve a dev-guides **source** root, in priority order: explicit
`DEV_GUIDES_SRC` env/config first, then auto-probe the current working directory,
then the conventional `~/workspace/dev-guides` checkout. A candidate is the repo
only if it carries the full **4-part signature**:

- `mkdocs.yml`
- `scripts/generate_llms.py`
- `docs/agentic-recipes/` (directory)
- at least one `.claude/agents/guide-*` agent

```bash
# Returns DG_SRC (non-empty → maintainer mode; empty → consumer mode, unchanged)
candidates=()
[ -n "$DEV_GUIDES_SRC" ] && candidates+=("$DEV_GUIDES_SRC")
candidates+=("$PWD" "$HOME/workspace/dev-guides")

DG_SRC=""
for d in "${candidates[@]}"; do
  if [ -f "$d/mkdocs.yml" ] \
     && [ -f "$d/scripts/generate_llms.py" ] \
     && [ -d "$d/docs/agentic-recipes" ] \
     && ls "$d/.claude/agents/"guide-* >/dev/null 2>&1; then
    DG_SRC="$d"; break
  fi
done
[ -n "$DG_SRC" ] && echo "maintainer mode: $DG_SRC" || echo "consumer mode"
```

A partial signature (e.g. `mkdocs.yml` but no `docs/agentic-recipes/`) is **not**
a match — treat it as consumer mode. This avoids false positives on unrelated
MkDocs sites.

## The offer

On a genuine miss in maintainer mode, present a single, plain offer — for example:

> No dev-guides topic exists for **`<topic>`**. The dev-guides source repo is
> detected at `<DG_SRC>`. Author the missing guide via `/create-guide <topic>`?
> (It researches a source guide, pauses for your review, partitions it into
> `docs/<topic>/`, and opens a PR — it never merges or deploys.)

If declined → STOP (the user proceeds without a guide). If accepted → hand off.

## The handoff

`/create-guide` is a **dev-guides project slash command** (lives in that repo's
`.claude/commands/`), not a navigator/plugin command. The navigator cannot invoke
it programmatically — it instructs the user to run it:

- If the current session's cwd **is** the detected repo (`DG_SRC == $PWD`), the
  command is already loaded — tell the user to run `/create-guide <topic>`.
- Otherwise, tell the user to open a session in `DG_SRC` (or `cd` there) and run
  `/create-guide <topic>` — the command only loads when that repo's `.claude/` is
  active.

Then **STOP**. Do not attempt to replicate any authoring step.

## What `/create-guide` does (for accurate framing — do not reimplement)

A summary of the handoff target so the navigator can describe it honestly. The
command itself owns every step:

1. **Charter scope gate** — mechanics/how-to only; IA/methodology/strategy is
   refused and routed elsewhere.
2. **Miss check** — new topic only (`docs/<topic>/` must not exist).
3. **Branch off `main`.**
4. **Research + write the SOURCE guide** (`guide-framework-maintainer` agent),
   outside the repo in `~/workspace/claude_memory/guides/` — not committed.
5. **PAUSE for human review** of the source guide.
6. **Partition** into `docs/<topic>/` (`guide-partitioner`): atomic guides,
   `index.md` with `guide-meta:` + 3-column routing table, nav, category index,
   manifest entry.
7. **Populate `guide-meta:`** (`guide-meta-populator`, idempotent backstop).
8. **Backfill the Summary column** (idempotent).
9. **Normalize cross-partition links.**
10. **Local `mkdocs build` preview** (output gitignored, never committed).
11. **Stage `docs/**` + `mkdocs.yml` + `partition-manifest.json` only, commit,
    push branch, open PR — then STOP.**

**Deploy = merge.** `/create-guide` ends at an opened PR; it never pushes to
`main`, never merges, never deploys. A human reviewer merging the PR into
protected `main` is what triggers the CI index regeneration + GH Pages deploy.
The navigator therefore never participates in deploy at all.
