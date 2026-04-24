---
description: "Compare current built output against a design comp reference (PNG/JPG, Figma URL via MCP, or HTML file rendered headless) to check visual parity. On diff, prompts user to classify as parity-miss (fix the build) or intentional deviation (update the reference). Framework-owned; shares capture + diff infrastructure with /validate:visual-regression. Soft-nudge. Introduced v3.13.0."
allowed-tools: Read, Write, Edit, Bash, Glob, Skill, Task
argument-hint: <component> <viewport> <reference> [<url>]
---

# Validate: Visual Parity

Compare the current built output against a design-comp reference and surface any parity gap. Unlike `visual-regression` (which compares against the project's own prior baseline), this compares against an **externally supplied target** — typically a Figma export, an HTML/React reference template, or a static image of the intended design.

Framework-owned. Shares capture + diff infrastructure with `/validate:visual-regression`.

## Usage

```
/drupal-dev-framework:validate-visual-parity <component> <viewport> <reference> [<url>]
```

- `<component>` — kebab-case identifier (e.g., `home-hero`, `article-card`)
- `<viewport>` — `WIDTHxHEIGHT` (e.g., `1920x1080`)
- `<reference>` — the design comp reference. Accepted in v1:
  - Path to a PNG/JPG file (passthrough)
  - A Figma URL (normalized via Figma MCP if available)
  - Path to an HTML file (rendered via headless browser)
  - Deferred to v2: React component paths, PSD, Sketch, Adobe XD — export to PNG first
- `<url>` — optional; target URL for the built output. Resolves from project state if absent

Example:
```
/drupal-dev-framework:validate-visual-parity home-hero 1920x1080 ~/designs/home-hero.png https://mysite.ddev.site
/drupal-dev-framework:validate-visual-parity article-card 375x812 "https://figma.com/file/abc123/redesign?node-id=12:45" https://mysite.ddev.site/article/sample
```

## What this does

1. **Resolve task + project context** — same resolution as other `/validate:*` commands.

2. **Validate args** — `<component>`, `<viewport>` regex checks. `<reference>` must be a PNG/JPG path, Figma URL matching `figma.com/file/`, or HTML file path. If format unsupported in v1, emit `verdict: skipped` with a message pointing to the v1 supported formats + the "export to PNG" workaround.

3. **Read the store** — invoke `screenshot-store-reader` for the project. Look for an existing parity reference at `<store>/<component>/<viewport>.png` with `role: parity_reference`.

4. **Normalize the reference to a PNG:**
   - **Path to PNG/JPG** → passthrough; use directly
   - **Figma URL** → invoke the Figma MCP server's export tool (e.g., `mcp__figma-mcp__get_image` or equivalent per the installed Figma MCP plugin). Save to `<task_folder>/validations/tmp/parity-reference-<component>-<viewport>.png`. Record `captured_by: "figma-export"`, `source: {type: "figma", uri: <url>}`
   - **HTML file path** → render via Playwright MCP: `mcp__plugin_playwright_playwright__browser_navigate "file://<abs-path>"` → resize to viewport → screenshot. Record `captured_by: "html-render"`, `source: {type: "html", uri: <abs-path>}`
   - If normalization fails (Figma MCP unavailable, etc.) → emit `verdict: skipped` with actionable message.

5. **Branch on imported-reference presence:**

   **5a. No parity reference exists OR the imported reference differs from the newly-normalized one:**
   - Prompt user: `"Import this reference as the parity target for <component>/<viewport>? [y]es / [n]o"`
   - On `[y]` → invoke `scripts/screenshot-store-write.sh write-parity-reference <project> <component> <viewport> <normalized.png> <captured_by> <task> <source_type> <source_uri>`. The writer handles rotation (same 6-step sequence as baselines; rotated meta keeps `role: parity_reference`). Proceed to step 6 using the NEW reference.
   - On `[n]` → emit `verdict: skipped`, messages `["No parity reference; user declined to import one"]`. Persist + print.

   **5b. Imported reference matches the normalized one (same sha256):**
   - Skip re-import; proceed directly to step 6.

6. **Capture current built output** — same as `visual-regression` step 4: Playwright MCP → `browser_navigate <url>` → resize → screenshot. Save to `<task_folder>/validations/tmp/<component>-<viewport>.png`.

7. **Run the diff** — same logic as `visual-regression` step 6: `odiff` primary, `pixelmatch` fallback. Output to `<task_folder>/validations/tmp/<component>-<viewport>.parity-diff.png`.

8. **Apply tolerance** — v1 hard-coded 0.1% (0.001). If within tolerance → emit `verdict: pass`, messages `["Built output matches design comp within 0.1% tolerance"]`.

9. **Diff > tolerance — classify:**
   Print diff image path. Prompt:
   > "Parity gap detected: `<diff_percent>%` pixels differ from the design comp. Saved diff image: `<diff_path>`. Is this:
   >   [g] Build gap (implementation doesn't match comp — fix the build)
   >   [i] Intentional deviation from the comp (update reference to reflect what's actually wanted)
   >   [c] Cancel"

   - `[g]` → emit `verdict: fail`. Messages include diff %, diff path, recommendation to update implementation. Set `classification: "build-gap"`, `baseline_updated: false`.
   - `[i]` → re-import the current capture as the new parity reference: `screenshots-store-write.sh write-parity-reference` with source set to the user's own built output (`source_type: "image"`, `source_uri: <capture-path>`). This is unusual — the user is saying "the comp is wrong; the build is correct." Rare but legitimate. Set `classification: "intentional"`, `baseline_updated: true`.
   - `[c]` → emit `verdict: skipped`, `classification: "cancelled"`.

10. **Emit the shared envelope** with visual-parity-specific details:

    ```json
    "details": {
      "source": "framework:visual-parity",
      "component": "<component>",
      "viewport": "<viewport>",
      "reference_path": "<abs path to imported parity reference>",
      "reference_source": {"type": "figma|html|image|url", "uri": "..."},
      "capture_path": "<abs path to fresh built-output capture>",
      "diff_path": "<abs path to parity-diff image OR null>",
      "diff_percent": 0.038,
      "diff_tolerance": 0.001,
      "classification": "build-gap",
      "baseline_updated": false
    }
    ```

11. **Persist + print** — same pattern as other gates.

## Key difference vs visual-regression

| Axis | `visual-regression` | `visual-parity` |
|---|---|---|
| Reference source | Own prior baseline (stored) | External design comp (imported) |
| On diff | "regression vs intentional change" | "build gap vs intentional deviation from comp" |
| Intentional approval writes | New baseline | New parity reference |
| Meta role | `baseline` | `parity_reference` |
| `.meta.json` `source` field | `null` | Populated with type + uri |

Same capture tooling, same diff tooling, same `.previous` rotation semantics, same shared envelope shape. Only the reference lifecycle differs.

## v1 format support

Per alignment.md non-goals:
- **v1 accepted:** PNG/JPG passthrough, Figma URL (via Figma MCP), HTML file (headless render)
- **Deferred to v2:** React components, PSD, Sketch, Adobe XD. Workaround: export to PNG first, then pass the PNG path.

## Error cases

| Scenario | Behavior |
|---|---|
| No session context AND no task resolution | Abort; exit 2 |
| `<reference>` format unsupported in v1 | Emit `verdict: skipped` with format list + workaround |
| Figma URL but Figma MCP not installed | Emit `verdict: skipped`; suggest installing the Figma MCP |
| HTML file path but Playwright MCP + claude-in-chrome both unavailable | Emit `verdict: skipped` |
| Writer returns `rollback` on intentional-deviation approval | Emit `verdict: fail` with writer warnings |

## Soft-nudge posture

Same as `visual-regression`: 0.1% tolerance, classification prompt is explicit and never silent-advances, `[c]ancel` is always safe, `fail` signals but never blocks.

## v2 candidates

Inherited from `visual-regression` — per-viewport tolerance, ignore regions, multi-DPR capture, deferred approval via `/complete`.

## Related

- `/drupal-dev-framework:validate-visual-regression` — sibling; compares against stored baseline instead of external comp
- `/drupal-dev-framework:validate-all` — orchestrator
- `scripts/screenshot-store-write.sh` — writer (in both `write-baseline` and `write-parity-reference` modes)
- `skills/screenshot-store-reader` — store reader
- `references/screenshot-store-schema.md` — canonical schema including `role: parity_reference` semantics + `source` field
