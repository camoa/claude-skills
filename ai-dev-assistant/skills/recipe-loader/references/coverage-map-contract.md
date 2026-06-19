# Coverage Map Contract

The artifact `recipe-loader` emits — consumed by `orchestrator_core` (and surfaced to the human for
confirm/prune). Mirrors ai-dev-assistant's own `## Coverage Mapping` concept (unit → coverage, gaps flagged), on
the *task-aspect* axis. Persisted to `<task_folder>/coverage-map.json` when a task folder is in
context; also returned in-context.

## Shape

```json
{
  "schema_version": "1.0",
  "task_aspects": ["<aspect>", "..."],
  "entries": [
    {
      "aspect": "<which aspect this informs>",
      "kind": "recipe | guide | play",
      "ref": "<capability (recipe) | slug (guide/play)>",
      "recipe_name": "<recipe name — kind:recipe only, else null>",
      "recipe_sha": "<index-line sha — kind:recipe only, else null>",
      "relevance": "high | medium | low",
      "via": "recipe:<capability> | residual-guide-search",
      "provenance": "upstream | local",
      "verified": false
    }
  ],
  "uncovered_aspects": ["<aspect with no source>"],
  "warnings": ["recipe_matched_no_machine_deps:<capability>", "recipe_body_unverified:<name>", "slug_not_in_catalog:<slug>", "navigator_unavailable"]
}
```

## Field contracts

| Field | Notes |
|---|---|
| `task_aspects[]` | The concerns the task touches (step 1). The rows the map accounts for. |
| `entries[]` | One per matched source. May be empty (then every aspect is in `uncovered_aspects`). |
| `entries[].kind` | `recipe` (a matched capability), `guide`, or `play`. |
| `entries[].ref` | For `recipe`: the `[capability]`. For `guide`/`play`: the catalog slug. |
| `entries[].recipe_name` | **`kind:recipe` only** — the matched recipe's name (from `recipe-names.txt`), the durable handle the orchestrator persists + re-fetches the body by. `null` for `guide`/`play`. |
| `entries[].recipe_sha` | **`kind:recipe` only** — the index-line sha the body was integrity-checked against (step 5). `null` for `guide`/`play`. Lets the orchestrator detect a stale cached body before persisting it. |
| `entries[].relevance` | Ranking for confirm/prune; guards over-matching. |
| `entries[].via` | `recipe:<capability>` (declared by a matched recipe) or `residual-guide-search`. |
| `entries[].provenance` | Derived from the **source**: `upstream` (from the upstream catalog cache) or `local` (from a local store). NOT a fixed default. |
| `entries[].verified` | `true` **only** when sourced from the upstream catalog cache (today's only first-party source); `false` for local/unverified; **`false` when the source is unknown (fail-closed)**. Never default `true`. |
| `uncovered_aspects[]` | Every aspect with **no** informing source. Always present (possibly empty). |
| `warnings[]` | Non-fatal observations (see below). |

## Invariants (enforce these)
1. **0..N** — recipe matches are never capped at one.
2. **Residual-always** — residual guide-search runs even when ≥1 recipe matched; its results appear
   with `via: residual-guide-search`.
3. **Never silently under-cover** — every aspect not covered by an entry MUST appear in
   `uncovered_aspects[]`. Omission is a contract violation.
4. **Ranked + prunable** — `entries[]` carry `relevance`; the map is surfaced for confirm/prune
   before any body is loaded downstream.
5. **Provenance always present, fail-closed** — every entry has `provenance` + `verified`, **derived
   from the source, never defaulted to `true`**: `verified:true` only for upstream-catalog-sourced
   entries, `false` otherwise (incl. unknown source). recipe-loader only *surfaces* these; the
   orchestrator gates execution (halts on `verified:false`). The cache exposes **no** provenance field
   today, so a future local-gen overlay MUST mark local entries; until then only upstream-catalog
   entries are `verified:true`.
6. **Lazy** — the map lists sources cheaply (from index lines / routing blocks); it does not embed
   guide/recipe bodies. Bodies load per-step downstream.
7. **Dedup is per `(aspect, kind, ref)`, least-trusted wins** — a shared slug across two aspects
   yields two entries (no dropped aspect); a true collision keeps the lower-trust entry (a
   `verified:false` twin is never hidden by `verified:true`). Numeric/`null` `ref` is coerced to
   string before keying.
8. **`kind:recipe` carries its durable handle** — every `kind:recipe` entry MUST set
   `recipe_name` + `recipe_sha` (both present in `recipe-names.txt`). They are the orchestrator's
   handle to persist the adopted body (write `<task_folder>/adopted-recipe-<safe_name>-<sha8>.md`) and to
   re-fetch / integrity-check it later. `guide`/`play` entries set both to `null`.

## Warning codes
| Code | Meaning |
|---|---|
| `recipe_matched_no_machine_deps:<capability>` | A matched recipe has no `requires_*` frontmatter; its aspect fell to residual guide-search. |
| `slug_not_in_catalog:<slug>` | A recipe declared a guide/play slug absent from the catalog (dangling edge). Surfaced, not repaired. |
| `navigator_unavailable` | The navigator could not be invoked; recipe layer skipped, guides-only degrade. |
| `recipe_cache_missing` | No recipes cache present and the navigator could not populate it. |
| `recipe_body_unverified:<name>` | A matched recipe's cached body sha ≠ its index-line sha (drift/missing); the body was NOT used and its deps skipped. **Orchestrator: treat as halt-and-escalate.** |

## The orchestrator_core seam (to ratify)
This shape (field names + the `<task_folder>/coverage-map.json` location) is the **proposed**
contract for `orchestrator_core` (child ③), which re-reads the map from disk to drive its run-loop
and to apply the unverified-execution halt against `verified:false` entries. **Ratify it jointly
when `orchestrator_core` is designed** — it is not frozen here.
