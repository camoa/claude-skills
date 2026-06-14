# Visual Regression v2 — Walkthrough

**Introduced:** ai-dev-assistant v4.13.0 (epic `visual_and_e2e_review_gates`, Task C)
**Audience:** maintainers and users of the framework's visual-regression gate.

This walkthrough covers the reworked `/validate:visual-regression` gate:
setup → surface discovery → baseline bootstrap → run → classify → update. It is
reference material — loaded only when explicitly read.

## 1. What changed from v3.13.0

v3.13.0 shipped a `validate-visual-regression` command that captured screenshots
via ad-hoc Playwright MCP calls and compared them against a `.screenshots/`
store in the memory project. Task C **evolves** it — it does not start fresh.

| | v3.13.0 | v4.13.0 |
|---|---|---|
| Capture | ad-hoc Playwright MCP, in-session | committed `tests/visual/*.spec.ts` + the framework's VR package |
| Invocation | `<component> <viewport>` one at a time | registry-driven multi-surface, multi-viewport batch |
| Baselines | `.screenshots/` in the memory project | `tests/visual/*.spec.ts-snapshots/` in codePath (committed) |
| Diff | standalone odiff / pixelmatch | pixelmatch via Playwright's `toHaveScreenshot()` |
| a11y | — | a11y snapshot paired with every PNG |
| Masks | — | per-surface CSS selectors from the registry |

**Kept verbatim:** the 9-field `.meta.json` provenance schema, the
`validation-gate-result.md` envelope, and the regression/intentional/cancel
classification UX.

## 2. Setup — `/setup-visual-regression`

`/setup-visual-regression` is an idempotent 10-step wizard. It:

1. Checks that the site under test is reachable via `PLAYWRIGHT_BASE_URL` — the
   URL must resolve for Playwright to run host-side. (This is not a
   containerization check.)
2. Installs the framework's VR package (resolved by the process recipe) +
   `@playwright/test` at the codePath root, plus the Chromium browser.
3. Extends `playwright.config.ts` with one `visual-chromium-<viewport>` project
   per derived viewport, and tightens `maxDiffPixelRatio` to `0.005`.
4. Derives the viewport matrix (see the viewport matrix section).
5. Offers to migrate a legacy `.screenshots/` store (see the migration section).
6. Runs AI-assisted surface discovery (see the surface discovery section).
7. Scaffolds `tests/visual/` — one starter spec per surface + `README.md`.
8. Writes `.gitattributes` (`tests/visual/**/*.png binary`).
9. Sets `**Visual Review:** enabled .visual-review/registry.yml` in
   `project_state.md`.
10. Prompts for a first baseline capture (see the baseline capture section).

The surface registry (`<codePath>/.visual-review/registry.yml`) is **shared
with `/setup-e2e`** — running both is order-independent; each command adds only
its own `projects[]` entry and its own surfaces.

## 3. Surface discovery

`/setup-visual-regression` does NOT auto-seed generic starter URLs. Surface
discovery is supplied by the framework's visual-regression process recipe,
resolved via the process-recipe-loader. The recipe enumerates real coverage
candidates and proposes two groups:

- **Front-end / public pages — default-ON.** Home, primary routes, one sample
  URL per key content area. This is what changes in normal site work.
- **Admin / editorial UI — default-OFF, opt-in.** Admin and back-office routes.
  Rarely affected by normal front-end work — enable only when the admin UI is
  the product.

You edit and confirm the list before anything is written to the registry. The
discovery step is re-runnable to pick up newly-added site pages, and
`--add-surface <url>` appends a single surface without hand-editing YAML.

## 4. Viewport derivation

The viewport matrix is **derived, not hardcoded** — a three-path waterfall:

1. **Breakpoint configuration** — parse the project's viewport breakpoint source
   (a design token file, style config, or equivalent); extract `min-width`
   values, apply canonical device heights.
2. **No breakpoints source** — scan the project's CSS for `@media`
   `min-width`/`max-width` queries, cluster within 50px, propose 2–4 viewports.
3. **Headless / admin-only / no CSS** — ask the user (defaults `375, 768, 1440`).

Every path **proposes** — you confirm before it is written to `registry.yml`.

## 5. Baseline bootstrap

The first run on a surface has no baseline. `/setup-visual-regression`'s final
step (and `/validate:visual-regression --bootstrap`) captures first baselines —
**always user-confirmed**:

1. `baseline-manager.sh` runs in **plan mode** first and prints the exact
   surfaces + viewports it would capture.
2. You see the plan and a literal `[y]/[n]` prompt.
3. Only on `[y]` does it re-run with `--confirmed` — which executes
   `npx playwright test --update-snapshots` host-side and appends
   `baseline-history.jsonl`.
4. For each baseline PNG, a `.meta.json` provenance sidecar is written next to
   it (the `captured_by` field records the capture tool).

A regression run with a missing baseline **fails loudly** with a remediation
message — it never silently auto-creates a baseline.

## 6. Running the gate

```
/ai-dev-assistant:validate:visual-regression
```

Resolves the registry, runs the whole `tests/visual/` suite in one
`npx playwright test` invocation across every `visual-chromium-*` project
(one per viewport), and diffs each surface against its committed baseline. The
site is reached over HTTP via `PLAYWRIGHT_BASE_URL` — Playwright itself runs
host-side.

## 7. Classifying a diff

When a surface differs from its baseline, the gate pauses per surface and emits
the `visual-regression-gate-fail` prompt:

- **`[r]` Regression** — a bug. The baseline is left unchanged; verdict `fail`.
- **`[i]` Intentional** — the new design is correct. The baseline is updated
  (via the `baseline-manager.sh` two-stage confirm — the `[i]` choice IS the
  approval, followed by a final "about to write" `[y]/[n]`), the provenance
  sidecar is rewritten, verdict `pass`.
- **`[c]` Cancel** — skip this surface; verdict `skipped`.

Each surface is classified before the next — prompts are never batched.

## 8. Updating baselines — the trigger catalog

`/validate:visual-regression --update-baselines "<reason>"` regenerates
baselines. `<reason>` is **required** and should be a recognized trigger so
`baseline-history.jsonl` explains why a baseline moved:

| Trigger | When |
|---|---|
| `intentional-ui-change` | A deliberate design/markup change |
| `prod-db-refresh` | Content changed, zero code change (most common non-code trigger) |
| `upstream-theme-update` | Base/parent theme updated |
| `dependency-update` | A package or dependency update changed rendering |
| `platform-update` | A framework or platform update changed rendering |
| `fixture-change` | Test fixture/content changed |
| `bootstrap` | First baseline capture |

Updates are **selective** — `--update-baselines` always scopes with `--grep` to
the affected surfaces. A blanket update (all surfaces) requires an explicit
confirmation with a louder warning. Every regeneration is user-confirmed and
logged.

## 9. The codePath-native store

Baselines are committed Playwright snapshots:

```
<codePath>/tests/visual/home-hero.spec.ts-snapshots/
├── home-hero-visual-chromium-desktop-linux.png
├── home-hero-visual-chromium-desktop-linux.meta.json   ← provenance sidecar
└── home-hero-visual-chromium-desktop-linux.txt          ← a11y snapshot
                                            (only when a recipe supplies an
                                             accessibility-aware capture)
```

- **PR-native** — a baseline change diffs alongside the code change; reviewers
  see exactly what moved.
- **No `.previous` tier** — git history IS the baseline history. The prior
  hash is still recorded in the sidecar's `prior_hash`.
- **Platform suffix** — `-linux.png`. A baseline captured on macOS/Windows is a
  different filename (`-darwin.png`) that CI will not find — drift fails loudly,
  never silently. See `tests/visual/README.md` for the per-platform capture
  policy.

Full schema: `references/screenshot-store-schema.md`.

## 10. Migrating a v3.13.0 `.screenshots/` store

`/setup-visual-regression` detects an existing memory-project `.screenshots/`
store and offers a one-time guided migration (`[y]/[n]/[d]efer`). On `[y]`,
`migrate-screenshots-to-codepath.sh` copies each `<component>/<viewport>.png`
into the codePath-native layout, rewrites `captured_by` →
`migrated-from-screenshots-store`, generates a stub spec, and adds a stub
registry entry (`url: "/"` + a `# TODO: verify URL` comment). The legacy store
is **never auto-deleted** — you remove it after verifying the migration.
`/setup-visual-regression --migrate` re-enters this flow after a `[d]efer`.

## 11. a11y baseline pairing

When a project's process recipe supplies an accessibility-aware capture helper,
that helper writes a `.txt` accessibility-tree snapshot alongside every PNG (the
framework-neutral native capture the plugin ships produces only the PNG). On
later runs, a change in the a11y tree surfaces in the
Playwright report. **v1 policy: warning-only** — a11y diffs do not hard-block
the gate; you triage them in the normal classification flow. A future
per-surface `a11y_block: true` registry flag can make them hard-block on
critical surfaces (login form, primary nav).

## 12. Masks

Dynamic regions (timestamps, contextual links, ad slots) produce false diffs.
Add CSS selectors to a surface's `masks` in `registry.yml`; the generated spec
resolves them to Playwright `Locator`s and paints them out before capture. For
regions best declared in the template, add a `data-vrt-mask` attribute in the
template markup and list `[data-vrt-mask]` in `masks`.

## 13. CI — GitHub Actions

Run the visual suite on `pull_request`. Baselines are committed, so CI just
compares — it never writes:

```yaml
name: Visual Regression
on: pull_request
jobs:
  visual:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npx playwright install --with-deps chromium
      # Point Playwright at your CI-hosted site:
      - run: npx playwright test --project=visual-chromium-desktop --project=visual-chromium-tablet --project=visual-chromium-phone
        env:
          PLAYWRIGHT_BASE_URL: ${{ secrets.CI_SITE_URL }}
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: playwright-report, path: playwright-report/ }
```

CI runs on Linux — it matches the canonical `-linux.png` baselines. Never
auto-update baselines on `main` from CI: that silently accepts regressions.
Run cross-browser tiers nightly (`schedule:`), not per-PR.

## 14. Coexistence with the E2E gate (Task B)

The E2E gate (`/setup-e2e`) and the visual gate share **one Playwright install,
one `playwright.config.ts`, one surface registry**. They differ only at the
test-library layer:

```
codePath/
├── playwright.config.ts        ← one config; e2e-* and visual-* projects[]
└── tests/
    ├── e2e/                    ← behavioral tests           (testDir)
    └── visual/                 ← VR tests                   (testDir)
```

Setup is idempotent and order-independent — run `/setup-e2e` and
`/setup-visual-regression` in either order; each adds only its own entries.

## 15. Server configuration

Set `PLAYWRIGHT_BASE_URL` to the site URL before invoking the gate. The site
must be reachable over HTTP/HTTPS from the host running Playwright. `/setup-*`
prompts for the site URL if it cannot be resolved from the environment. To set
up `tests/visual/` and the registry manually, follow the setup sections above
and provide the URL when prompted.

## 16. v2 candidates

- Per-surface `a11y_block: true` registry flag (hard-block a11y on critical
  surfaces).
- SDC component-level isolation capture (deferred to a future epic — Spike #1).
- Multi-browser beyond Chromium (Firefox/WebKit nightly tier).
- Per-surface `maxDiffPixelRatio` tuning.

## 17. Pointers

- `commands/setup-visual-regression.md` · `commands/validate-visual-regression.md`
- `references/screenshot-store-schema.md` — store layout + `.meta.json` schema
- `references/visual-review/surface-registry-schema.md` — the coverage manifest
- `references/visual-review-walkthrough.md` — the epic-wide three-surface model
- `scripts/derive-viewport-matrix.sh` · `scripts/visual-regression-gate.sh` · `scripts/baseline-manager.sh` · `scripts/migrate-screenshots-to-codepath.sh`
