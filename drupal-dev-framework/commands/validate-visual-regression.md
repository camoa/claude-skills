---
description: "Capture a screenshot of a component/page and compare against the project's stored baseline to detect unintended visual changes. On diff, prompts user to classify as regression (bug) or intentional (update baseline) with inline approval. Framework-owned; uses Playwright MCP for capture, odiff/pixelmatch for diff. Soft-nudge posture. Introduced v3.13.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: <component> <viewport> [<url>]
---

# Validate: Visual Regression

Capture the current visual state of a component or page, diff it against the stored baseline, and classify any detected difference as regression or intentional. When intentional, the baseline is rotated inline (previous baseline slides to `.previous`; the fresh capture becomes the new baseline) per the screenshot store rotation rules.

Framework-owned — uses Playwright MCP (primary) or claude-in-chrome MCP (fallback) for capture; `odiff` (primary) or `pixelmatch` (fallback) for diff.

## Usage

```
/drupal-dev-framework:validate-visual-regression <component> <viewport> [<url>]
```

- `<component>` — kebab-case component/page identifier (e.g., `home-hero`, `article-card`, `admin-toolbar`). Used as the store key
- `<viewport>` — display size, `WIDTHxHEIGHT` format (e.g., `1920x1080`, `375x812`)
- `<url>` — optional; target URL to capture. If absent, attempt to resolve from task context (e.g., project `project_state.md` or last-used URL)

Example:
```
/drupal-dev-framework:validate-visual-regression home-hero 1920x1080 https://mysite.ddev.site
/drupal-dev-framework:validate-visual-regression article-card 375x812
```

## What this does

1. **Resolve task + project context** — same resolution as other `/validate:*` commands. Need the project path to locate the screenshot store.

2. **Validate args** — `<component>` matches `^[a-z0-9][a-z0-9-]*$`; `<viewport>` matches `^[0-9]+x[0-9]+$`. If `<url>` absent, attempt to resolve from project state; abort if none found with "pass a URL arg or set codePath's live URL in project_state.md".

3. **Read the store** — invoke `screenshot-store-reader` skill against the project folder. Look for an existing baseline at `<store>/<component>/<viewport>.png` with `role: baseline`.

4. **Capture current state** — via Playwright MCP:
   - Tool sequence: `mcp__plugin_playwright_playwright__browser_navigate <url>` → wait for page load → `mcp__plugin_playwright_playwright__browser_resize <width> <height>` → `mcp__plugin_playwright_playwright__browser_take_screenshot`
   - If Playwright MCP unavailable, fall back to `mcp__claude-in-chrome__*` tooling
   - Save capture to `<task_folder>/validations/tmp/<component>-<viewport>.png`
   - Record `captured_by` = `playwright-mcp` or `claude-in-chrome` accordingly

5. **Branch on baseline presence:**

   **5a. No baseline exists (first run for this component+viewport):**
   - Prompt user: `"No baseline exists for <component>/<viewport>. Accept the current capture as the first baseline? [y]es / [n]o"`
   - On `[y]` → invoke `scripts/screenshot-store-write.sh write-baseline <project> <component> <viewport> <capture-path> <captured_by> <task>`. Emit envelope with `verdict: pass`, messages `["First baseline established"]`. Persist + print summary.
   - On `[n]` → emit `verdict: skipped`, messages `["No baseline; user declined to establish one"]`. Persist + print.

   **5b. Baseline exists:**
   - Proceed to diff (step 6).

6. **Run the diff:**
   - If `command -v odiff` succeeds → `odiff <baseline.png> <capture.png> <task_folder>/validations/tmp/<component>-<viewport>.diff.png`. Parse diff percentage from output.
   - Else fall back to `pixelmatch` via Node (invoke as `npx pixelmatch` if available, or abort if no Node runtime) with the same args.
   - If both unavailable, emit `verdict: skipped`, messages `["No image diff tool installed; install odiff (brew install odiff-bin / port) or ensure npx pixelmatch is available"]`. Persist + exit.

7. **Apply tolerance** — v1 hard-coded 0.1% (0.001) pixel-diff threshold. If `diff_percent <= 0.001`, emit `verdict: pass`, messages `["No visual change detected (diff <= 0.1%)"]`. Skip to step 10.

8. **Diff > tolerance — classify:**
   Print the diff image path. Prompt user:
   > "Diff detected: `<diff_percent>%` pixels changed. Saved diff image: `<diff_path>`. Is this:
   >   [r] Regression (bug to fix — leave baseline as-is)
   >   [i] Intentional change (update baseline to reflect new design)
   >   [c] Cancel (abort without classifying)"

   Default: `[c]` if unclear. Never silent-advance.

   - `[r]` → emit `verdict: fail`. Messages include the diff percentage, the diff image path, and a prompt to investigate. Set `classification: "regression"`, `baseline_updated: false`. Go to step 10.
   - `[i]` → proceed to step 9 (inline approval + rotation).
   - `[c]` → emit `verdict: skipped`. Messages note user cancelled. Set `classification: "cancelled"`, `baseline_updated: false`. Go to step 10.

9. **Inline approval + baseline rotation** (only on `[i]`):
   - Invoke `scripts/screenshot-store-write.sh write-baseline <project> <component> <viewport> <capture-path> <captured_by> <task>`. The writer handles the 6-step rotation (prior_hash capture, `.previous` drop-and-rename, new capture install, new meta with provenance, post-write sha256 verification).
   - Parse writer's JSON output. On `status: "ok"` → emit `verdict: pass`, messages `["Intentional change accepted; baseline rotated. Previous baseline archived as .previous.png."]`, `classification: "intentional"`, `baseline_updated: true`.
   - On `status: "rollback"` or `"error"` → emit `verdict: fail`, messages include the writer's warnings. `baseline_updated: false`.

10. **Emit the shared envelope** (per `references/validation-gate-result.md`) with visual-specific details:

    ```json
    "details": {
      "source": "framework:visual-regression",
      "component": "<component>",
      "viewport": "<viewport>",
      "reference_path": "<abs path to baseline>",
      "capture_path": "<abs path to fresh capture>",
      "diff_path": "<abs path to diff image OR null>",
      "diff_percent": 0.042,
      "diff_tolerance": 0.001,
      "classification": "intentional",
      "baseline_updated": true
    }
    ```

11. **Persist** — write envelope to:
    - `<task_folder>/validations/latest/visual-regression.json` (overwrite — note: just `visual-regression.json`, not keyed by component, because `latest/` only holds most-recent-run-per-gate; per-component history is in `history.jsonl`)
    - `<task_folder>/validations/history.jsonl` (append)

12. **Print CLI summary** — verdict, component+viewport, diff percent, classification if any, persisted paths.

## Baseline lifecycle summary

| Scenario | Writer action | Store result |
|---|---|---|
| First capture, user approves | `write-baseline`, first-baseline special case | `<component>/<viewport>.png` + `.meta.json` created; no `.previous` |
| Second+ capture, no diff | None | No change; existing baseline unchanged |
| Diff detected, user classifies regression | None | No change; baseline unchanged |
| Diff detected, user classifies intentional | `write-baseline` with rotation | Previous current → `.previous`; fresh capture → current; new meta with `prior_hash` |
| Diff detected, user cancels | None | No change |

## Error cases

| Scenario | Behavior |
|---|---|
| No session context AND no task resolution | Abort; exit 2 |
| `<component>` or `<viewport>` malformed | Abort; exit 2 |
| `<url>` not provided AND not resolvable from project state | Abort; exit 2 |
| Playwright MCP AND claude-in-chrome MCP both unavailable | Emit `verdict: skipped`; exit 0 |
| `odiff` AND `pixelmatch` both unavailable | Emit `verdict: skipped`; exit 0 |
| Writer returns `status: rollback` | Emit `verdict: fail` with writer's warnings in messages; exit 1 |
| Store reader returns `hash_mismatch` on baseline | Surface warning; proceed with diff (baseline file corruption is still worth catching) |

## Soft-nudge posture

- The 0.1% tolerance is hard in v1 but liberal enough to absorb antialiasing + font-hinting noise
- `fail` verdict on regression does NOT block; user investigates at their pace
- Intentional-change approval happens INLINE — no deferred `/complete` batch step in v1 (v2 candidate)
- User `[c]ancel` is always safe — no partial writes; nothing rotates

## v2 candidates

- Per-component / per-viewport diff tolerance configuration
- Deferred-approval path via `/complete` batch hook (requires `.candidate` staging)
- Ignore regions (mask animated content, timestamps, etc.)
- Multi-DPR capture sets

See `implementation_process/in_progress/<this-task>/v2-candidates.md`.

## Related

- `/drupal-dev-framework:validate-visual-parity` — sibling visual gate; compares against a design comp, not a baseline
- `/drupal-dev-framework:validate-all` — orchestrator
- `scripts/screenshot-store-write.sh` — the writer invoked on intentional-change approval
- `skills/screenshot-store-reader` — the store reader
- `references/screenshot-store-schema.md` — `.meta.json` v1.0 + directory layout
- `references/validation-gate-result.md` — shared result envelope
