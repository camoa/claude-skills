# Visual Regression Tests

Committed visual-regression baselines powered by
[`@lullabot/playwright-drupal`](https://www.npmjs.com/package/@lullabot/playwright-drupal)
and Playwright. Set up by `/drupal-dev-framework:setup-visual-regression`.

> This file is scaffolded by `/setup-visual-regression`. Edit freely — it is a
> normal project file once written.

## Quick start

```bash
# Run the whole visual suite (all surfaces, all viewports):
npx playwright test --project visual-chromium-desktop --project visual-chromium-tablet --project visual-chromium-phone

# Or, from the framework:
/drupal-dev-framework:validate:visual-regression
```

## Directory layout

```
tests/visual/
├── README.md                              — this file
├── <surface-id>.spec.ts                   — one spec per registry surface
└── <surface-id>.spec.ts-snapshots/        — committed baselines (DO commit)
    ├── <surface-id>-1-visual-chromium-desktop-linux.png
    ├── <surface-id>-1-visual-chromium-desktop-linux.meta.json   ← provenance
    └── <surface-id>-1-visual-chromium-desktop-linux.txt          ← a11y snapshot
```

Baselines (`*.spec.ts-snapshots/`) **are committed**. Transient run output
(`test-results/`, `playwright-report/`) is gitignored.

## DO NOT RENAME THE TEST

Every generated spec names its test exactly `'visual regression'`. That fixes
Playwright's snapshot ordinal at `-1-`, so the baseline filename is
deterministic:

```
<surface-id>-1-visual-chromium-<viewport>-linux.png
```

Renaming the test — or adding a second screenshot call inside one test —
changes the ordinal and **orphans every committed baseline** for that surface.
If you need multi-shot capture, use a separate spec file.

## When to run visual regression

| Cadence | For | How |
|---|---|---|
| **Per-PR (recommended default)** | The smoke + component surface set | CI on `pull_request`; classify diffs locally before pushing |
| **On-demand** | Active UI work — catch regressions early | `npx playwright test --project visual-chromium-*` |
| **Nightly** | Cross-browser tiers (Firefox/WebKit) | `schedule:` trigger; slower, lower priority |
| **Never per-commit on `main`** | — | Auto-updating baselines on `main` silently accepts regressions |

## Baseline recreation triggers

`/validate:visual-regression --update-baselines "<reason>"` requires a reason.
Use one of the recognized triggers so the `baseline-history.jsonl` log explains
*why* a baseline moved:

| Trigger | When |
|---|---|
| `intentional-ui-change` | A deliberate design/markup change |
| `prod-db-refresh` | Content changed, zero code change (most common non-code trigger) |
| `upstream-theme-update` | A base/parent theme was updated |
| `contrib-update` | A contrib module update changed rendering |
| `core-update` | A Drupal core update changed rendering |
| `fixture-change` | Test fixture/content changed |
| `bootstrap` | First baseline capture |

A freeform reason is accepted (logged with a warning) — but a recognized
trigger keeps the history legible.

## Baseline capture is platform-specific

Playwright bakes the capture platform into every baseline filename
(`-linux.png`, `-darwin.png`, `-win32.png`). A baseline captured on the wrong
platform is simply *not found* by a Linux CI run — a loud failure, never silent
drift.

| Dev host OS | Baseline capture approach |
|---|---|
| **Linux** (default expectation) | Host capture is canonical — matches CI `-linux.png` directly. Run `npx playwright test --update-snapshots` on the host. |
| **macOS / Windows** | Host capture produces `-darwin.png` / `-win32.png` — CI will not find them. Use one of: (1) capture in CI and commit the result — simplest; (2) `docker run --rm -v "$(pwd)":/work mcr.microsoft.com/playwright npx playwright test --update-snapshots`; (3) `ddev exec npx playwright test --update-snapshots`. All three produce `-linux.png`. |

## Masking dynamic regions

A surface's `masks` in `.visual-review/registry.yml` are CSS selectors painted
over before capture (timestamps, contextual links, ad slots). For regions best
declared in the template itself, add a `data-vrt-mask` attribute in the Twig
markup and list `[data-vrt-mask]` in the surface's `masks`.

## Repo size & Git LFS

Baseline PNGs are committed and marked `binary` in `.gitattributes`. A mid-size
program (~95 baselines × 3 viewports, ~10 revisions/year) adds roughly
600 MB/year of git history. Once the repository exceeds ~1 GB, migrate the
snapshots to Git LFS:

```bash
git lfs migrate import --include="tests/visual/**/*.png"
```

## References

- VR baseline management: https://camoa.github.io/dev-guides/testing/visual-regression/workflow/
- Playwright VR: https://camoa.github.io/dev-guides/testing/visual-regression/playwright/
- Full walkthrough: `references/visual-regression-walkthrough.md` (in the plugin)
