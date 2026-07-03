---
description: "Verify that the task's phase artifacts cite plays from the loaded playbook (active sets + local user playbook). Framework-owned gate — heuristic any-of-three cite match (filename slug | normalized title | tldr-prefix). Soft-nudge standalone; promotes warning→fail when invoked from /review with --hard-block. Section-aware: skips 'Rejected'/'Considered Alternatives'/'Out of Scope' headings. Introduced v4.1.0."
allowed-tools: Read, Grep, Glob, Bash
argument-hint: "[<task-name>]"
---

# Validate: Playbook Adherence

Verify that this task's phase artifacts (`research.md`, `architecture.md`, `implementation.md`, `git diff`) cite plays loaded from the project's active playbook sets and local user playbook. Premise: framework loads plays at every phase entry (`_playbook-load.json`); without a cite-check, plays can be silently ignored.

Heuristic gate: cite-match is any-of-three (filename slug | normalized title | tldr-prefix), each searched as **literal strings** (Grep `-F`) — not regex — to avoid injection risk. False negatives expected with paraphrased citations; user override = `/review --skip-playbook-adherence <reason>`.

## Usage

```
/ai-dev-assistant:validate-playbook-adherence              # current task, soft mode
/ai-dev-assistant:validate-playbook-adherence <task-name>  # specific task
/ai-dev-assistant:validate-playbook-adherence <t> --hard-block   # /review-mode (warning→fail)
/ai-dev-assistant:validate-playbook-adherence <t> --strict       # CI escalation (warning→fail)
/ai-dev-assistant:validate-playbook-adherence <t> --base <branch>  # diff base (default: main). Pass the PR base for non-main branches — else merge-base main HEAD resolves to an ancient fork point (same issue as /review step 4).
```

Task name must match `^[a-z0-9_-]+$` (path-traversal mitigation). When `--skip-playbook-adherence` audit exists from `/review`, it takes precedence over `--strict`.

## What this does

1. **Resolve task context** — (a) run `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-read.sh` (Bash) and parse its JSON (`.project`, `.projectPath`, `.task`, `.taskPath`); (b) walk up from `$PWD` to find `implementation_process/`; (c) abort with usage on neither. Validate task-name charset; locate task under `<project>/implementation_process/**/<task-name>/`.

2. **Read playbook audit (defensive).** `jq -e .gate_specific <task>/_playbook-load.json 2>/dev/null` — on parse failure OR file absent, emit `verdict: "skipped"` reason `"no playbook audit found — task pre-dates v3.15.0 or playbook loader did not run"` and proceed to Step 8.

3. **Applicability check.** Extract `playbook_sets_loaded // []` and `user_playbook_loaded // null` (jq defaults handle missing keys). If **both** empty/null → nothing was declared → `verdict: "skipped"` reason `"no_playbook_declared"` (a genuine no-op / intentional opt-out — benign). Proceed to Step 8. **If a set IS declared (`playbook_sets_loaded` non-empty) or a user playbook is set, do NOT skip here** — proceed to Step 4; a declared playbook that *resolves to 0 plays* is a **vacuous** skip, detected and recorded distinctly at Step 8 (it is NOT the same as "nothing declared", and must not read as coverage). Also surface any `_playbook-load.json` `warnings[]` (notably `playbook_sets_declared_zero_local_plays`) into `messages[]`.

4. **Enumerate cite needles.** Build `needles[] = [{play_id, filename_slug, normalized_title, tldr_prefix}]`:
   - For each `set` in `playbook_sets_loaded[]`: `Glob ~/workspace/dev-guides/docs/<set>/*.md` (skip `index.md`). Per file: `filename_slug` = basename minus `.md`; `normalized_title` = `# H1` lowercased + non-alphanum stripped; `tldr_prefix` = frontmatter `tldr` first 40 chars lowercased. Fallback: `dev-guides-navigator` skill if local cache absent.
   - For `user_playbook_loaded`: `bash scripts/playbook-read.sh <path>`; per `.plays[]`, derive `filename_slug` from kebab-cased title, normalize title, take first 40 chars of `what` for `tldr_prefix`.

5. **Build artifact list.** `<task>/{research,architecture,implementation}.md` (skip absent files); `git diff $(git merge-base "$BASE" HEAD)..HEAD` written to a temp file, where `$BASE` is the `--base` argument (default `main`). Mirrors `/review` step 4's `$BASE` threading — on a branch cut from a non-`main` integration branch, `merge-base main HEAD` would resolve to an ancient fork point and the diff would balloon to the whole branch divergence.

6. **Cite-check (literal-string match per match-type, NOT regex).** For each needle, run 3 separate `Grep` calls with `-F` (literal/fixed-string) — one per match-type. Glob over artifact list. Set `needle.cited = (any call returned matches)`; record `cite_locations[] = [{file, line, match_type}]` per match. Match-type is determined by **which call produced the hit** (no post-hoc string classification needed). Per-play 3 Grep calls; ~20 plays in default camoa = ~60 calls. Scales linearly with playbook size.

7. **Section-aware skip.** Cite-locations falling under H2/H3 headings matching `^(##|###)\s+(rejected|not applied|considered alternatives|out of scope|anti-?patterns?)\b` (case-insensitive) DO NOT count toward `cited`. This prevents the "I considered but rejected this play" gaming vector. Implement: pre-scan each artifact for skip-section line ranges; `cite_locations` whose line falls inside a skip-range are filtered. Document caveat: only the listed heading patterns are excluded; novel "considered" sections will not.

8. **Aggregate verdict.** `cited = count(needles where .cited == true after Step 7 filter)`, `total = len(needles)`, `ratio = cited/total`:
   - `total == 0` → `verdict: "skipped"`, but **record WHY (vacuous vs no-op) — a skip must never read as coverage:**
     - if a playbook **was** declared (`playbook_sets_loaded` non-empty OR `user_playbook_loaded` non-null) yet **0 plays resolved** → reason `"declared_playbook_resolved_zero_plays"` and push a prominent `messages[]` warning: `"⚠ Declared playbook (<sets|user_playbook>) resolved to 0 plays — adherence was NOT verified; this skip is NOT coverage. Confirm the set is cached (dev-guides-navigator) or set a local user playbook (/ai-dev-assistant:set-user-playbook)."` (the GAP-C vacuous-skip case — the set is a name that resolved to nothing).
     - else (nothing was declared — should already be Step 3's `no_playbook_declared`) → reason `"no_playbook_declared"` (benign).
   - `ratio == 1.0` → `verdict: "pass"`
   - `ratio >= 0.5` → `verdict: "warning"` (soft) OR `"fail"` (when `--hard-block` OR `--strict`)
   - `ratio < 0.5` → `verdict: "fail"`

9. **Build envelope** per `references/validation-gate-result.md` v1.0:

   ```json
   {
     "schema_version": "1.0", "gate": "playbook-adherence", "task": "<name>",
     "run_at": "<ISO-8601 UTC>", "verdict": "<...>",
     "details": {
       "source": "framework:playbook-adherence",
       "invoked_by": "review | cli | validate-all | validate-team",
       "playbook_sets_loaded": [...], "user_playbook_loaded": "<path|null>",
       "cited_count": <int>, "total_plays": <int>,
       "uncited": [{"play_id", "filename_slug", "tldr_prefix"}, ...],
       "cite_locations": {"<play_id>": [{"file","line","match_type"}, ...]},
       "skipped_sections": [{"file","heading","line_range"}, ...]
     },
     "messages": [...]
   }
   ```

   `invoked_by`: argv `--invoked-by <source>` (default `cli`). `messages[]` includes per-uncited-play remediation hint (`"Uncited: <slug> — <tldr_prefix>"`); plus implicit-inheritance hint when `playbook_sets_source == "default"`. Write atomically to `<task>/validations/latest/playbook-adherence.json` (overwrite); append to `<task>/validations/history.jsonl`.

10. **Print CLI summary + exit.** Tabular: verdict, ratio, uncited list, skipped-sections summary. Exit `0` in soft mode (always); exit `1` on `fail` when `--hard-block` OR `--strict` set; exit `2` on invalid args (charset, malformed flags).

## Heuristic notes

Cite-matching is approximate: any-of-three literal-string match. False negatives possible when authors paraphrase. `--strict` (CI) or `--hard-block` (/review) inverts the bias. Section-aware skip handles the most obvious gaming vector ("Rejected" headings); authors who want to game further can craft creative section headers — that's a known limit, not a bug.

**Performance limit:** ~60 Grep calls per default camoa playbook (3 match-types × 20 plays × 1 multi-file glob). Sub-second on typical artifacts. ~100-play playbooks land at ~300 calls — still under tool-call rate limits but worth flagging. Mega-alternation batching is a v2 candidate (loses per-play attribution).

## Pointers

- Per-gate envelope: `references/validation-gate-result.md` v1.0
- Cite-checker algorithm: architecture.md C3 in this subtask's design folder
- Playbook structure: `references/playbook-schema.md` v1.0
- Sibling: `/ai-dev-assistant:upgrade-project` (sets explicit `**Playbook Sets:**` per project)

## Future hardening

`UserPromptExpansion` hook (Claude Code 2.1.118+, Hooks Reference) fires when a slash command expands into a prompt and **can block the expansion**. A future v2 could intercept `/complete` and other PR-creating commands at expansion time, validate that `_review.json` + `_playbook-adherence.json` audits exist with acceptable verdicts, and hard-block at the platform layer instead of the command-body layer. Tracked as a v2 candidate; not a v4.2.0 deliverable.

## Related

- `/ai-dev-assistant:review <task>` — invokes this gate at Phase 4 with `--hard-block --invoked-by review`
- `/ai-dev-assistant:validate-guides <task>` — sibling cite-check (dev-guides instead of plays)
- `/ai-dev-assistant:validate-all <task>` — aggregator includes this gate
- `/ai-dev-assistant:playbook-active` — see currently-loaded plays
- `/ai-dev-assistant:upgrade-project` — fix `playbook_sets_source: "default"` implicit inheritance
