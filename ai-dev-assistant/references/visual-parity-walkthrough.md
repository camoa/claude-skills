# Visual Parity v2 — Walkthrough

> _Drupal-flavored component — a stack-neutral version is in progress. The Drupal specifics below are the current reference implementation._

**ai-dev-assistant v4.14.0 (Task D — `visual_and_e2e_review_gates`)**

The full rationale, examples, and workflow behind `/setup-visual-parity` +
`/validate:visual-parity`. The command files are the contract; this is the narrative.

Visual **parity** compares the built output against an *external design reference* — a
Figma export, a prod URL, an HTML/React template, a static comp. Visual **regression**
(Task C) compares the build against its own committed baseline. They are siblings: same
`@lullabot/playwright-drupal` + host-side Playwright stack, same surface registry, same
soft-gate posture — they differ only in what the build is measured against.

## 1. What changed from v3.13.0

| v3.13.0 `validate-visual-parity` | v4.14.0 |
|---|---|
| Ad-hoc Playwright MCP capture of the build | Committed `tests/parity/` suite, host-side Playwright + Lullabot (the Task C stack) |
| `<component> <viewport> <reference>` positional args | Registry-driven — surfaces with a `parity_reference` |
| `odiff` / standalone pixelmatch | `pixelmatch` inside `parity-compare.mjs` |
| **Bare pixel-% verdict** | **Two-layer diff** — coarse pixel-% + structured CSS-actionable diff |
| Reference re-imported into the screenshot store | Reference registered in `registry.yml`; static files committed under `tests/parity/references/` |

The headline fix: a bare pixel-% is unactionable. An AI matches a design *graphically*
("looks close") but drifts on spacing, font-weight, exact colours. v4.14.0 reports
**what** differs in CSS terms — `font-weight 400 vs 500`, `gap 12px vs 16px` — a fix
list, not a percentage.

## 2. The two-layer diff

1. **Coarse pixel diff** — `pixelmatch`, loose tolerance (`PARITY_MAX_DIFF_RATIO`,
   default `0.05`). Answers "is something off?" The tolerance is deliberately loose:
   cross-render antialiasing noise swamps a tight one, and the pixel ratio is *not* the
   actionable signal — so tightening it is the wrong lever.
2. **Structured CSS-actionable diff** — `getComputedStyle` on a curated selector set,
   compared property-by-property. Emits `{selector, property, build, reference}` rows.
   This is the deliverable.

A surface **fails** when the pixel diff exceeds tolerance **or** the CSS diff is
non-empty. That second clause is the point: a surface with a perfect pixel score but a
`font-weight 400 vs 500` drift still fails — because the build does not match the
design intent.

## 3. Capability is tiered by reference type

A CSS-actionable diff needs CSS on **both** sides. A flat PNG has none.

| `reference_type` | Reference DOM? | CSS diff |
|---|---|---|
| `html-template` | yes — `file://` render | **Full** |
| `react-template` | yes — pre-rendered HTML / served URL | **Full** |
| `prod-url` | yes — a live site | **Full** |
| `figma` | no — a PNG export | **build-only** |
| `image` | no — a static PNG/JPG | **build-only** |

For `figma`/`image` the gate reports the coarse pixel diff plus the *build side's own*
computed styles, honestly labelled `css_diff_mode: "build-only"`. It never fabricates a
reference comparison. **Prefer `html-template`/`react-template` when CSS precision
matters** — and such a template is *buildable-from*, not only diffable-against (see §8).

## 4. Setup — `/setup-visual-parity`

Parity **hard-depends** on `/setup-visual-regression` — it reuses that command's
Lullabot install, `playwright.config.ts`, surface registry, and viewport matrix. Run
visual-regression setup first; `/setup-visual-parity` refuses otherwise.

`/setup-visual-parity` then: installs `pixelmatch` + `pngjs`; scaffolds `tests/parity/`
(+ `references/` for committed static comps) and copies in `parity-compare.mjs`;
appends one `parity-chromium-<viewport>` project per registry viewport; walks each
surface asking whether it has a design reference; generates one spec per surface that
gets one.

## 5. Registering a reference

Per surface you supply `type`, `uri`, and optionally `compare_selectors`:

- **`figma`** — export the frame to PNG manually; register the path. Setup copies it to
  `tests/parity/references/<surface-id>.png` so it is committed — **one comp per
  surface**. A static comp is a single fixed size; under `--all-viewports` it is
  compared against every viewport, coarsely (dimension-mismatch) for non-matching ones.
  A build page much taller than the comp is compared only on the comp-height region —
  breakage below the comp's fold is not caught (prefer a renderable reference, or a
  single-viewport run, when this matters). Figma MCP/API live integration is future-only.
- **`html-template` / pre-rendered `react-template`** — an in-repo path; rendered
  headless for comparison, and usable as a build input (§8).
- **`react-template` (served)** / **`prod-url`** — an `http(s)` URL fetched live each
  run.
- **`image`** — a static PNG/JPG path, committed like `figma`.

`compare_selectors` lists the elements whose computed styles are compared. Absent → a
default set (`h1`–`h3`, `button`/`.button`/`.cta`, `main`). Keep it short and
surface-specific.

## 6. Running the gate

```bash
/ai-dev-assistant:validate:visual-parity                 # default viewport only
/ai-dev-assistant:validate:visual-parity --all-viewports # every viewport
```

`visual-parity-gate.sh` creates a timestamped `parity-results/<run>/`, runs the
`parity-chromium-*` Playwright projects host-side, and merges the per-surface
`.parity.json` fragments each spec wrote. Single-viewport is the default for fast
iteration; `--all-viewports` for a full sweep.

Parity also **auto-runs** (soft) inside `/review` on design-implementation tasks — the
change-impact dispatcher fires it when the task touches a surface that has a
`parity_reference`. It is never part of the VR/E2E per-task opt-in question.

## 7. Classifying a gap

For each failed surface the gate shows the pixel diff, the diff image, and the
**CSS-actionable diff list**, then asks (`visual-parity-gate-fail` prompt):

- **`[g]` Build gap** — the build is wrong; the CSS-diff list is the fix list. Verdict
  `fail`.
- **`[i]` Intentional deviation** — the build is correct; the comp is stale. Verdict
  `pass`. Parity has **no baseline machinery** — `[i]` does *not* rewrite the reference;
  it records the decision and may annotate `registry.yml` `notes`.
- **`[c]` Cancel** — skip; verdict `skipped`.

## 8. Design-drives-build

If a task implements a designed feature, the registered design reference should be used
to **create** the implementation — fed into `/implement` as a build input — not merely
checked at `/review`. `/implement` prints a one-line soft-nudge when a buildable
(`html-template`/`react-template`) reference is registered for a surface. It is a
strong nudge, not enforcement: hard-requiring it would block legitimate cases and break
the framework's recommender posture.

## 9. There is no baseline machinery

Parity has no committed "truth" to rotate. A reference is updated by re-exporting it
(a fresh Figma PNG, an updated template) and editing the surface's `parity_reference`
in `registry.yml`, then `/validate:visual-parity --update-reference-hash` to accept the
new file hash. The gate detects reference-file drift (sha256) and surfaces it — it
never silently accepts a changed reference.

## 10. Artifacts — committed vs transient

| Path | Committed? |
|---|---|
| `tests/parity/*.spec.ts` (verbatim copies), `tests/parity/parity-compare.mjs`, `tests/parity/parity-surfaces.json`, `tests/parity/README.md` | yes |
| `tests/parity/references/*` (static `figma`/`image` comps) | yes |
| `parity-results/` (per-run captures, diff images, `.parity.json`) | **no — gitignored** |

## 11. CI

Parity runs host-side like the regression gate — `npx playwright test --project
parity-chromium-*` against a reachable DDEV (or `PLAYWRIGHT_BASE_URL`) site. In `--ci`
mode there are no classification prompts: any gap → `fail`. `prod-url` references in CI
must be publicly reachable (v1 supports public pages only — auth-aware fetching is
deferred).

## 12. v2 candidates

- Figma MCP/API live reference acquisition (v1 is manual PNG export).
- Headless React rendering from `.jsx`/`.tsx` source (v1 needs a pre-rendered artifact).
- Auth-aware `prod-url` fetching (cookies/headers).
- Structural DOM auto-matching instead of a curated `compare_selectors` list.
- Component-level parity (v1 is page-surface level).

## 13. Pointers

- `commands/setup-visual-parity.md` · `commands/validate-visual-parity.md`
- `scripts/visual-parity-gate.sh` · `references/visual-review/parity-compare.mjs`
- `references/visual-review/surface-registry-schema.md` (v1.1 — the `parity_reference` object)
- `references/gate-audit-schema.md` (v1.3 — the `visual_parity` gate_type)
- dev-guides: `testing/visual-regression/playwright/`, `testing/visual-regression/pixelmatch/`,
  `testing/visual-regression/workflow/`
