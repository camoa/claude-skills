---
description: "Verify that the task's phase artifacts cite dev-guides-navigator guides appropriate to the domain AND (v4.3.0+) that those citations cover the catalog guides relevant to the actually-changed code. Framework-owned gate — not a wrapper. Soft-nudge posture; never blocks. Introduced v3.13.0."
allowed-tools: Read, Write, Bash, Glob, Skill, Agent
argument-hint: "[<task-name>]"
---

# Validate: Guides

Verify that this task's phase artifacts reference Drupal development guides loaded via the `dev-guides-navigator` plugin. The premise: decisions made without consulting authoritative guides drift from community consensus. Catching "no guide citations in research.md or architecture.md" early prevents downstream architectural debt.

This is a **framework-owned** gate — it does NOT wrap a `code-quality-tools` skill. Implementation lives here in ai-dev-assistant.

## Usage

```
/ai-dev-assistant:validate-guides              # run against current task (soft-nudge)
/ai-dev-assistant:validate-guides <task-name>  # run against a specific task
/ai-dev-assistant:validate-guides <t> --hard-block         # /review-mode (warning→fail)
/ai-dev-assistant:validate-guides <t> --strict             # CI escalation (warning→fail)
/ai-dev-assistant:validate-guides <t> --no-code-inference  # disable v4.3.0 catalog-grounded inference
```

## What this does

<!-- /review:hard-block -->
This gate is **dual-mode** (v4.1.0+): standalone CLI invocation stays soft-nudge (existing v3.13.0 behavior); when invoked from `/ai-dev-assistant:review` with `--hard-block`, the gate promotes `warning` verdicts to `fail`. The HTML comment above is the **capability marker** read by `/review` Step 4 to assign `kind: "hard-block"` in `gates_run[]`.

1. **Resolve task context** — same resolution as other `/validate:*` commands:
   (a) read `session_context.json` if present
   (b) walk up from `$PWD` until you find `implementation_process/`
   (c) abort with "no project context" if neither resolves

   Locate the task folder under `<project>/implementation_process/in_progress/**/<task-name>/`.

2. **Applicability check (v3.14.2+)** — before inspecting artifacts, determine whether dev-guides apply to this task at all. The dev-guides catalog covers Drupal, Next.js, design systems (Bootstrap/Radix/Tailwind/DaisyUI), CSS, and cross-cutting methodology. For tasks whose codePath contains none of those domain markers (e.g., a Claude Code plugin marketplace, a pure docs project, a shell-script tools repo), guide citations are not expected and `fail` would be a false positive.

   Read `project_state.md` for `codePath` and `codePathState`. Then:

   - If `codePathState == "docs-only"` OR `codePathState == "unset"` → emit `verdict: "skipped"` with reason `"task has no code path declared (state: <state>); guide citation rule does not apply"`. Skip Steps 3-5.
   - If `codePathState == "set"` → quick-scan codePath for domain markers:
     - **Drupal:** any `*.info.yml`, `*.module`, `composer.json` containing `"drupal/core"`, or directory ending in `.theme`
     - **Next.js:** `package.json` containing `"next"` as a dep, or `next.config.{js,ts,mjs}`
     - **Frontend/CSS:** `*.scss`, `*.css`, `tailwind.config.*`, or `package.json` containing `"react"`/`"vue"`/`"svelte"`
   - If at least one marker matches → applicable; continue.
   - If NO markers match → emit `verdict: "skipped"` with reason `"codePath at <path> contains no Drupal/Next.js/frontend code; guide citation rule does not apply to this task type"`. Skip Steps 3-5.

   The applicability check is intentionally generous (any marker → applicable). False positives are cheaper than false negatives — if a task even smells Drupal-or-frontend, run the citation check.

   Detection is shallow (top-level + 1-deep) to keep the check fast. Implement via `Glob` + `Bash` `grep`. Cache result on `details.applicability` so consumers can see what fired.

3. **Inspect phase artifacts** — read any of these that exist in the task folder:
   - `research.md` (Phase 1 artifact) **plus any `research/<subject>.md` files** (v4.10.0+ split research — guide citations may live in the per-subject files, not the hub)
   - `architecture.md` (Phase 2 artifact) **plus any `architecture/<component>.md` files**
   - `implementation.md` (Phase 3 artifact)

4. **Extract guide citations** — scan for guide references in each artifact. Accept:
   - URLs matching `camoa.github.io/dev-guides/[a-z0-9/-]+` (the published dev-guides site)
   - Inline mentions of guide slugs in the form `drupal/<category>/<topic>`, `design-systems/<topic>`, `nextjs/<topic>`, or similar kebab-case paths
   - Markdown reference links `[...](https://camoa.github.io/dev-guides/...)`
   - Explicit "Loaded guide: <slug>" annotations if the `dev-guides-navigator` skill wrote them

5. **Catalog-grounded code-change inference (v4.3.0+).** Skip with `--no-code-inference` (records `code_inference.suppressed_by_flag: true`).

   **a) Build the changed-files union** — collect from three sources, dedupe by absolute path:
   - **Session-known changes** — files Claude has edited or written in the current conversation against `codePath`. Enumerate from your own awareness of `Edit` / `Write` tool use.
   - **`implementation.md` "Files Created/Modified" section** — parse listed paths; resolve relative paths against `codePath`.
   - **Git working tree** (when codePath is a git repo): combine `git status --porcelain` and `git diff --name-only HEAD`. Skipped silently if not git.

   If the union is empty → set `code_inference.source: "none"`, `sources_used: []`, skip to Step 6 with no domain-gap signal.

   **b) Locate the dev-guides catalog cache.** The `dev-guides-navigator` plugin writes it to `~/.claude/projects/<dasherized-cwd>/memory/dev-guides-cache.json`, where `<dasherized-cwd>` is the absolute working directory with every non-alphanumeric character replaced by `-` — **not** an `md5` hash (see the navigator's `references/cache-format.md`, the contract this consumes). Derive the precise path first, glob-fallback only if absent:
   ```bash
   DASHED=$(printf '%s' "$PWD" | sed 's/[^a-zA-Z0-9]/-/g')
   CATALOG="$HOME/.claude/projects/${DASHED}/memory/dev-guides-cache.json"
   if [ ! -f "$CATALOG" ]; then
     for d in ~/.claude/projects/*/memory/; do
       [ -f "${d}dev-guides-cache.json" ] && CATALOG="${d}dev-guides-cache.json" && break
     done
   fi
   ```
   The glob fallback (first match) mirrors the navigator's pre-compact hook. If no cache exists anywhere — or the cache file has no `.content` key (treat as missing) — emit `code_inference.warnings: ["catalog_cache_missing"]`, set `inferred_slugs: []`, do NOT demote verdict (no signal == no penalty).

   **Staleness check (caller-side, not agent-side):** `stat -c %Y "$catalog_path"` to read mtime; if older than 30 days (compare to `date +%s`), append `code_inference.warnings: ["catalog_cache_stale"]` AND proceed — staleness is informational, not blocking. Suggest in the CLI summary that the user run `/dev-guides-navigator --refresh` to update the cache.

   **c) Invoke `guides-matcher` agent** in `validation` mode with the union, the catalog path, optional `context_excerpts[]` from `implementation.md` Files Created/Modified, and `already_cited[]` from Step 4. Per `references/guides-matcher-schema.md` v1.0.

   **d) Compute `domain_coverage_gaps`** — agent's `matched_guides[].slug` MINUS prefix-match against `guides_cited[]`. Slugs the agent judged relevant but no artifact citation covers.

6. **Judge adequacy** — apply verdict rules in this order:
   - `skipped` → no phase artifacts exist yet (task hasn't progressed past creation)
   - `fail` → no guide citations found in any phase artifact AND at least one artifact exists with ≥200 lines of content (substantive work without guide consultation)
   - `warning` → ≥1 citation found overall but phase coverage uneven (research cites but architecture doesn't), **OR** `domain_coverage_gaps != []` (code touched domains the agent matched to catalog guides not cited; v4.3.0+)
   - `pass` → ≥1 citation in research.md AND ≥1 in architecture.md (if it exists) AND `domain_coverage_gaps == []`

   The 200-line substance threshold prevents false-positives on near-empty stub artifacts. Domain-gap demotion only applies when `code_inference.source != "none"` AND no `catalog_cache_missing` warning fired — tasks with no detected changes or no catalog still pass on phase coverage alone.

   **Hard-block promotion (v4.1.0+):** if `--hard-block` is set (passed by `/review`) OR `--strict` is set (CI escalation), promote `warning` → `fail`. Soft-mode and standalone CLI invocation unchanged. The argv flag is the runtime mode selector; the HTML capability marker near the top of this file is what `/review` Step 4 reads to decide whether to invoke with `--hard-block`. Also write `details.invoked_by: "review" | "cli" | "validate-all" | "validate-team"` in the envelope for audit provenance.

7. **Emit the shared envelope** (per `references/validation-gate-result.md`) with gate-specific details:

   ```json
   "details": {
     "source": "framework:guides",
     "applicability": {
       "decision": "applicable | skipped",
       "reason": "<one-line explanation>",
       "markers_found": ["drupal", "frontend"]
     },
     "checked_artifacts": ["<abs path to each artifact examined>"],
     "guides_cited": ["<slug>", "<slug>"],
     "guides_expected_min": 1,
     "code_inference": {
       "source": "session+implementation_md+git",
       "sources_used": ["session", "implementation_md", "git"],
       "changed_files_count": 12,
       "matcher_output": {"matched_guides": [...], "unmatched_files": [...], "warnings": []},
       "inferred_slugs": ["drupal/forms/config-forms", "drupal/services/dependency-injection"],
       "domain_coverage_gaps": ["drupal/services/dependency-injection"]
     }
   }
   ```

   - `applicability` — populated by Step 2; for `skipped` runs `checked_artifacts` / `guides_cited` / `code_inference` may be omitted.
   - `code_inference.matcher_output` — verbatim agent JSON, for audit replay.
   - `code_inference.inferred_slugs` — flattened slug list extracted from `matcher_output.matched_guides[].slug`.
   - `code_inference.source: "none"` when no files surfaced from any source; `suppressed_by_flag: true` when `--no-code-inference` was passed.

8. **Persist** — write envelope to:
   - `<task_folder>/validations/latest/guides.json` (overwrite)
   - `<task_folder>/validations/history.jsonl` (append)

9. **Print CLI summary** — show verdict, citations found, per-artifact gaps, and (when present) `domain_coverage_gaps` with the catalog slugs the agent matched but no artifact cites. On `fail` or domain-gap `warning`, suggest `/dev-guides-navigator <slug>` for each gap. On `skipped` due to applicability, print the applicability reason. Non-zero exit (1) only when invoked non-interactively.

## Verdict messages

Examples of what `messages[]` contains:

- `pass`: `["3 guide citations found across research.md and architecture.md", "guides-matcher: all matched slugs covered"]`
- `warning` (phase coverage): `["2 citations in research.md but 0 in architecture.md — architecture may be under-grounded"]`
- `warning` (domain gap, v4.3.0+): `["guides-matcher matched drupal/services/dependency-injection from changed files; no artifact citation covers it. Try /dev-guides-navigator drupal/services/dependency-injection"]`
- `skipped (applicability)`: `["codePath at /abs/path contains no Drupal/Next.js/frontend code; guide citation rule does not apply to this task type"]` or `["task has no code path declared (state: docs-only); guide citation rule does not apply"]`
- `fail`: `["No guide citations found in any phase artifact", "Suggest: /dev-guides-navigator with keywords from task.md Goal"]`
- `skipped`: `["No phase artifacts exist yet; run /research to begin"]`

## Why this gate exists

The `dev-guides-navigator` plugin exists precisely because AI-generated Drupal work drifts from community consensus when it doesn't load authoritative guides. This gate surfaces the "we didn't check" case and recommends action — it's NOT a block, just a visible signal during `/validate:all`.

**Applicability auto-skip (v3.14.2+):** the gate now skips with reason when codePath has no Drupal/Next.js/frontend markers, OR when codePathState is `docs-only` / `unset`. This makes the gate safe to include in `/validate:all` and `/validate:team` runs against non-Drupal tasks (Claude Code plugin work, shell-tool repos, pure-docs projects) without producing spurious `fail` verdicts. v1 had no auto-skip and relied on user judgment about when to invoke; v3.14.2 makes that judgment explicit and machine-checkable.

## Error cases

| Scenario | Behavior |
|---|---|
| No session context AND no `<task-name>` arg | Print "no task context" + exit 2 |
| `<task-name>` doesn't resolve to a folder | Print candidate suggestions + exit 2 |
| Task folder has no phase artifacts | Emit `verdict: skipped` with helpful message |
| Persistence write fails | Print CLI summary; mention failure in messages; exit 1 |

## Soft-nudge posture

- Manual invocation always runs
- `fail` verdict signals under-grounded work but never blocks downstream phases
- The recommendation ("run `/dev-guides-navigator`") is a suggestion; user decides if it's worth the time

## Catalog-grounded code-change inference (v4.3.0+)

Catches "research cited form guides but the implementation modified entity files" — phase-artifact coverage alone misses domain mismatch. The `guides-matcher` agent (haiku, read-only) matches the changed-files union against the cached `dev-guides-navigator` catalog so the taxonomy is always the live catalog, not a parallel hardcoded map. Inputs: session edits + `implementation.md` Files Created/Modified + git working tree (any/all available). Output: catalog slugs the agent judges relevant. Compared against `guides_cited[]` via prefix-match; gaps demote `pass` → `warning` (or `fail` under `--hard-block`/`--strict`).

See `references/guides-matcher-schema.md` for the agent's input/output contract and `agents/guides-matcher.md` for the agent itself.

## v2 candidates

- Per-task configurable `guides_expected_min` (e.g., "this complex task should cite ≥3")
- Detecting STALE citations (guide was updated since task cited it)
- Confidence-thresholded gap reporting (e.g., only demote on `confidence: high` matches)

See `implementation_process/in_progress/<this-task>/v2-candidates.md` for the full deferred-features inventory.

## Related

- `/ai-dev-assistant:validate-tdd` / `:validate-solid` / `:validate-dry` / `:validate-security` — sibling gate commands; wrappers
- `/ai-dev-assistant:validate-visual-parity` / `:validate-visual-regression` — visual gates
- `/ai-dev-assistant:validate-all` — sequential orchestrator
- `references/validation-gate-result.md` — the shared envelope contract
- `references/guides-matcher-schema.md` — agent I/O contract (v4.3.0+)
- `agents/guides-matcher.md` — the catalog-match subagent (haiku, read-only)
- `dev-guides-navigator` plugin — the guide discovery tool whose usage this gate verifies
