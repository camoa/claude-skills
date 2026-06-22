# Store Contract (C1)

Canonical reference for the shared content store and per-project lockfile used by
`dev-guides-navigator`. This is the handshake `ai-dev-assistant` builds to when it
reads cached guide, task-recipe, and process-recipe content from the shared store.

This file is the self-contained, executable summary of the store and lockfile contract.
It is everything an implementer needs to build against; no external design document is
required.

---

## 1. Store Layout

```
~/.claude/dev-guides-store/          # machine-level, shared across projects
  indexes/
    llms.json                        # { hash, fetched_at, content }
    agentic-recipes.json             # { hash, fetched_at, content }
    process-recipes.json             # { hash, fetched_at, content }
  blobs/
    <key>                            # raw body bytes; key is caller-supplied content id
```

`DEV_GUIDES_STORE_DIR` overrides the root (used in tests). All index JSON files share
the same three-key shape: `{ hash, fetched_at, content }` — identical to the legacy
`dev-guides-cache.json` schema.

---

## 2. Per-Project Lockfile

Path: `<project-memory-dir>/dev-guides.lock.json`

`<project-memory-dir>` is `$HOME/.claude/projects/<dasherized-cwd>/memory` — the same
derivation used by the legacy cache files (see `cache-format.md` for the exact bash
one-liner).

Schema:

```json
{
  "guides":          { "<topic>/<file.md>": "<sha256>" },
  "task_recipes":    { "<name>": "<sha8>" },
  "process_recipes": { "<phase>/<framework>/<url-slug>": "<sha8>" }
}
```

Example process-recipe key: `e2e-setup/drupal/e2e-setup-atk`.

- All three classes are plain footprints of what the project touched — a `"<key>": "<id>"`
  string map. Nothing is pinned.
- `guides` entries (guide-body caching — **active**) record `"<topic>/<file.md>": "<sha256>"`,
  where the sha256 comes from the topic's `guide-index.json` manifest
  (`https://camoa.github.io/dev-guides/<topic>/guide-index.json`, a `{ "<file.md>": "<sha256>" }`
  map over the raw markdown bytes). Written whenever a guide body is materialized.
- `task_recipes` value is a plain JSON string (the sha8).
- `process_recipes` value is a plain JSON string (the sha8) — identical in shape to
  `task_recipes`.
- The `<url-slug>` (name segment) is the **trailing path segment of the recipe's `site-url`**
  (e.g. for `https://camoa.github.io/dev-guides/process-recipes/drupal/e2e-setup-atk/` the
  slug is `e2e-setup-atk`), NOT the `<name>` field from the index line — this avoids
  duplicated framework tokens like `drupal_e2e_setup_atk`.
- The lockfile records only what the project actually touched.

---

## 3. Blob-Addressing Convention

The blob key is the **exact content-id the index line already provides** — no
re-computation by the caller:

| Class | Key | Source |
|-------|-----|--------|
| Task recipes | 8-char hex sha8 | `(sha:XXXXXXXX)` from the `agentic-recipes.txt` line |
| Process recipes | 8-char hex sha8 | `(sha:XXXXXXXX)` from the `process-recipes.txt` line |
| Guide bodies | sha256 | per-topic `guide-index.json` manifest (`{ "<file.md>": "<sha256>" }`) |

The lockfile stores the same id that addressed the blob — so `lockfile[key].sha` is
always a valid argument to `blob-get`.

---

## 4. Freshness Policy

All three classes share **one** policy: **auto-fresh**.

| Class | Policy |
|-------|--------|
| Guides (index + bodies) | Auto-fresh — revalidate index on every use; re-fetch body when sha changes |
| Task recipes (index + bodies) | Auto-fresh — same two-hash discipline |
| Process recipes (index + bodies) | Auto-fresh — same two-hash discipline; nothing pinned |

**Guide-body freshness — fetch `guide-index.json` on use.** A guide body manifest is
**not** gated by `llms.hash`. A body edit changes that file's sha256 in the topic's
`guide-index.json`, but the topic's `llms.txt` line (count + description) need not change —
so `llms.hash` can be unchanged while a body has changed. The manifest is small, so the
navigator fetches it on every body serve to detect body changes; it does **not** assume
"`llms.hash` unchanged ⇒ bodies unchanged."

Process recipes are auto-fresh like everything else: revalidate the index by its `.hash`,
serve the line's current `(sha:…)`, and fetch the body only when that sha's blob is absent.
A changed upstream sha is fetched, not pinned. There is no pin-and-notify policy; process
recipes revalidate on use exactly like guides and task recipes.

---

## 5. Kernel as Only Writer

`${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-store.sh` is the **only writer** of the
shared store and the lockfile. No skill, agent, or hook writes directly to
`~/.claude/dev-guides-store/` or edits `dev-guides.lock.json` — all mutations go
through the kernel's subcommands (`revalidate`, `blob-put`, `lock-set`).

---

## 6. Compat Shims (transitional) + staged retirement plan

Two per-project compat shims exist, written by the navigator from the shared store:

| Shim | Writer(s) | Reader(s) | Read-cutover status |
|------|-----------|-----------|---------------------|
| `dev-guides-cache.json` (guides / `llms.txt`, `{hash,fetched_at,content}`) | navigator SKILL Mode-1 `cp indexes/llms.json → …`; `hooks/setup-cache.sh` (pre-warm) | `ai-dev-assistant` `scripts/dev-guides-detect.sh`, `commands/validate-guides.md` (→ `guides-matcher`), navigator `hooks/pre-compact.sh` | **READS REPOINTED.** All readers now resolve the **shared store** `indexes/llms.json` first (honouring `DEV_GUIDES_STORE_DIR`), falling back to this shim only when the store is cold/absent. Same `{hash,fetched_at,content}` shape ⇒ a plain `.content` read works on either. |
| `dev-guides-recipes-cache.json` (recipes, `{index, recipes:{name:{sha,content}}}`) | navigator SKILL Modes 2/3 via the kernel's `legacy-recipes-shim` | `ai-dev-assistant` `skills/recipe-loader` (**REPOINTED**), `skills/work-order-compiler` (kernel `wo-compile.sh lockfile-sha`, still on shim) | **PARTIALLY CUT OVER (ai-dev-assistant 5.15.0).** `recipe-loader` now reads the **shared store directly** — index via `indexes/agentic-recipes.json` `.content`, each body via the content-addressed `blobs/<sha8>` keyed by the index-line sha it already holds (so **no `lock-read`** is needed — the multi-source remap the deferral worried about doesn't apply to this consumer). This also fixes GAP-B: the shim was cwd-keyed, so a build cwd ≠ the task's codePath read the wrong project's cache; the shared store has no project keying. `wo-compile.sh lockfile-sha` (work-order-compiler) **still reads the shim** — it resolves a sha *from* the lockfile, so it genuinely needs `index-content` + `lock-read` + `blob-get`; left on the shim until its own cutover. |

### Why guides reads were safe to cut over in one pass
The store's `indexes/llms.json` is byte-for-byte the same schema as the guides shim,
so repointing is a pure path change with a degrade-safe fallback. Every guides reader
picks the first candidate (store → cwd shim → glob shim) that actually yields `.content`.

### Staged retirement plan
1. **Now (this cutover):** guides reads repointed store-first-with-fallback; **all shim
   writers KEPT** (the guides `cp`/`setup-cache.sh` and the `legacy-recipes-shim`). The
   fallback still depends on the guides shim, so retiring its writer now would remove the
   safety net for no benefit. Recipes readers untouched.
2. **Follow-up A (recipes read cutover) — PARTIALLY DONE (ai-dev-assistant 5.15.0):**
   `recipe-loader` is **repointed** to the store directly — index via `indexes/agentic-recipes.json`
   `.content`, body via the content-addressed `blobs/<sha8>` (it already has the sha from the matched
   index line, so it skips `lock-read`). **Remaining:** `wo-compile.sh lockfile-sha`
   (work-order-compiler) still reads the shim — it must resolve a sha *from* the `task_recipes` lockfile,
   so it needs `index-content` + `lock-read` + `blob-get`. The recipes shim is read-free only once that
   consumer also cuts over.
3. **Follow-up B (writer retirement):** once a release has soaked with store-first reads
   and no fallback hits are observed, drop the guides `cp` shim + the `legacy-recipes-shim`
   call, and stop `setup-cache.sh` writing the legacy path (or repoint it to pre-warm the
   store index). Retire a writer **only** after every reader of that shim is store-first.
