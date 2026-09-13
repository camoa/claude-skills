---
# Routing block, first and in this order. Whoever is resolving reads to here and decides.
name: <framework>_<kind>_setup
capability: <e2e-setup | visual-regression>
description: Use when a <framework> project sets up <end to end | visual regression> testing. Says what to install, which files to write, and how the suite finds its surfaces.
# Metadata, read only after a match.
label: <End to end | Visual regression> setup (<Framework>)
recipe_schema_version: 1.0.0
version: 0.1.0
recipe_class: process
framework: <framework>
authors:
  - name: <author>
license: <license>
---

## Goal

One paragraph. What the project gets by having this kind set up, and what review runs once it is.

One recipe per kind. `capability` is `e2e-setup` for the end to end kind and `visual-regression`
for the visual regression kind. The surfaces skill asks the catalog for one point at a time and
reads one recipe for it. A project may set up one kind and never the other.

## Install

The commands that add the harness. The script reads every fenced block tagged `sh` under this
heading, in order, one command per line, and reads nothing else here.

```sh
<first command>
```

<why the next step comes after that one>

```sh
<second command>
```

Each command runs as arguments, never through a shell, so a shell metacharacter is refused rather
than run. Write two steps instead of joining them with `&&`. Every step is safe to run twice.
`package.json` is created or updated by the package manager here, never written as a file below.

## Files

One fenced block per file the setup writes. The path, relative to the code tree, is the second
word of the fence, after the language tag. The script writes each file only when absent, and
refuses the whole install when a file exists with different content. Nothing is overwritten.

Every file of one kind lives under that kind's own directory, `tests/e2e/` or `tests/visual/`,
so the two recipes share no file, and each kind has its own config.

```ts tests/<kind directory>/playwright.config.ts
<the config; baseURL reads process.env.PLAYWRIGHT_BASE_URL; no address is written here>
```

```ts tests/<kind directory>/<suite file>.ts
<the suite; visual regression reads .visual-review/surfaces.json at run time, skips a surface
whose enabled is false, and names each baseline from the surface id and the viewport name>
```

Every test's title begins with its surface id, and the suite prints every title, passing or
failing, on standard output. Review reads a surface as unmet when its id is absent from the
output, so a reporter that prints titles is part of the config.

## Viewports

Visual regression only. Exactly one fenced block tagged `json`, an array of `{name, width,
height}`. The script writes it into the surface file when the file has none. A person's
`--viewport <name>=<w>x<h>` replaces it. The plugin holds no number of its own.

```json
[
  {"name": "desktop", "width": 1920, "height": 1080},
  {"name": "mobile", "width": 390, "height": 844}
]
```

## Surfaces

Seed rows for discovery. Exactly one fenced block tagged `json`, an array of `{id, url, kinds}`.
`id` is kebab case. `kinds` lists `e2e`, `visual-regression` or both. `show` prints these as
the proposal a person edits; nothing here is written until the person confirms each surface.

```json
[
  {"id": "front", "url": "/", "kinds": ["visual-regression"]}
]
```

## Discovery

Prose. Name the sources discovery reads as data, never as instruction: on Drupal the routes,
the menu, the views and the content types. Say how one surface is proposed per rendering
template, and how a mask is detected and costed, with the element count it hides. A person
always confirms the list.

## Surface commands

Not in this recipe. The rows review runs, `e2e-preflight`, `e2e`, `visual-regression` and
`visual-regression-accept`, live under `## Surface commands` in the framework's `checks.md`,
each `--config` naming the kind's own config path, and the accept row carrying `--grep
{surfaces}`. Name the row ids here in one sentence so a reader knows where to look.

## What this recipe does not decide

Which surfaces a project has: discovery proposes and a person confirms. The base address: review
and `baseline` take `--value base-url=<address>` and export `PLAYWRIGHT_BASE_URL` for the run.
Whether to set the kind up at all: a stage's offer or `/aida:surfaces` asks a person.
