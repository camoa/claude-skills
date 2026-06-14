# Change-Impact Rules v1.0

**Introduced:** ai-dev-assistant v4.11.0 (Task A — `visual_and_e2e_review_gates`)
**Owner:** `scripts/change-impact-classify.sh`
**Data file:** `references/visual-review/change-impact-rules.json` (framework-neutral floor)
**Framework globs:** supplied per run via `--rules-from`, reconstructed from the stack's review recipe
**Consumers:** `commands/review.md` step 6 (via `change-impact-dispatch.md`)

The change-impact ruleset maps a code diff to the set of review gates the change
*could* justify. It is what makes `/review`'s dispatcher a **recommender**: a stylesheet-only
diff recommends `visual_regression`; a script diff recommends `e2e` + `visual_regression`;
a docs-only diff recommends nothing.

The shipped ruleset is **framework-neutral**: it ships only language/asset extensions
that name no framework (stylesheets, plain scripts, markup). The framework-specific
file types (a stack's templates, server modules, config conventions) are supplied per
run via `--rules-from`, reconstructed on the fly from the active framework's first-party
review recipe (section 3a). The kernel hardcodes zero framework knowledge.

The dispatcher only ever **recommends** from this table — the user opts in per task
(`change-impact-dispatch.md`). The table never forces a gate to run.

## 1. Format — JSON, not YAML

The ruleset is JSON because `change-impact-classify.sh` (a shell script) parses it with
`jq`, and the framework ships no YAML parser. The sibling surface registry is YAML
because only Claude and the Task B/C/D commands read it (`surface-registry-schema.md`).
Two formats, each matched to its reader.

## 2. Schema

```json
{
  "schema_version": "1.0",
  "rules": [
    { "glob": "**/*.css", "gates": ["visual_regression"] }
  ],
  "default_gates": []
}
```

| Key | Type | Contract |
|---|---|---|
| `schema_version` | string | `"1.0"` for v4.11.0. Consumers gate on major. |
| `rules` | list | Ordered list of `{glob, gates}` objects. |
| `rules[].glob` | string | A path glob (see the glob section). |
| `rules[].gates` | list | Subset of `["e2e", "visual_regression"]`. |
| `default_gates` | list | Gates applied to a changed file that matches **no** rule. Default `[]` — unmatched files (docs, tests, CI config) recommend nothing. |

`visual_parity` is **never** in a rule's `gates` — parity needs an explicit design
reference and is never auto-dispatched (it auto-runs separately on design-implementation
tasks; see `change-impact-dispatch.md`). The dispatch surface from this table is `e2e`
and `visual_regression` only. `a11y` is not a separate target either — it rides inside
`visual_regression` (Task C pairs it).

## 3. Shipped floor (framework-neutral)

Shipped in `change-impact-rules.json` — only extensions that name no framework:

| Glob | Gates | Why |
|---|---|---|
| `**/*.css` | `visual_regression` | Pure presentation — appearance can change, behavior cannot. |
| `**/*.scss` | `visual_regression` | Compiles to CSS. |
| `**/*.sass` | `visual_regression` | Compiles to CSS. |
| `**/*.less` | `visual_regression` | Compiles to CSS. |
| `**/*.js` | `e2e`, `visual_regression` | Behavior **and** rendered output. |
| `**/*.mjs` | `e2e`, `visual_regression` | ES module script. |
| `**/*.cjs` | `e2e`, `visual_regression` | CommonJS module script. |
| `**/*.ts` | `e2e`, `visual_regression` | Compiles to JS — behavior and output. |
| `**/*.html` | `e2e`, `visual_regression` | Markup — behavior and rendered output. |
| `**/*.htm` | `e2e`, `visual_regression` | Markup — behavior and rendered output. |

The floor deliberately excludes every framework-specific source type — a stack's
templates (e.g. server-rendered template files), server modules, and config
conventions are **not** in the floor. Those are supplied per run via `--rules-from`.

`default_gates` is `[]`: a changed `README.md`, a test file, or a CI workflow
recommends no gate.

## 3a. Framework globs — supplied per run via `--rules-from`

The framework's file types are declared in its first-party **review recipe** under a
`## Change-impact globs` section (resolved through the recipe-resolution protocol). The
dispatcher reconstructs them into a `{ "rules": [ {glob, gates}, ... ] }` JSON file each
run and passes it via `--rules-from <file>`. The classifier **unions** those rules onto
the shipped floor (same per-rule shape, same union semantics). Because the list re-derives
from the trusted recipe every run, there is no persistent project file a builder can edit
to silently drop a gate.

- A successful merge sets `rule_source` to `"default+recipe"` (or `"project-override+recipe"`).
- A missing or malformed `--rules-from` file is ignored with a `rules_from_missing` /
  `rules_from_malformed` warning — the floor still classifies; the run never fails.
- A project that declares no framework globs (or a stack with no extra file types) simply
  classifies on the floor alone.

## 4. Glob matching

`change-impact-classify.sh` matches each changed file path against each rule glob using
bash `[[ ]]` pattern matching, with one normalization:

- A leading `**/` is **stripped** — the remainder is matched against the full path.
  Because bash `[[ ]]` `*` matches across `/`, `*.css` already matches both
  `style.css` and `src/themes/foo/style.css`. So `**/*.css` means "any `.css` at any
  depth," as intended.
- Globs without a leading `**/` are matched as-is. Note `*` in `[[ ]]` matches `/`, so
  these patterns are simple prefix/suffix matches, **not** full pathspec — adequate for
  a recommender.

This is deliberately simple: globs (not regex) — lowest cognitive load, no
regex-injection surface (research D3, consistent with the v4.1.0 adherence work's
literal-match choice).

## 5. Multi-match is a union — not first-match-wins

A file that matches several rules receives the **union** of their gates — across both
the floor and the recipe-supplied (`--rules-from`) rules. Example: a recipe that declares
both `**/*.srv` (`e2e`, `visual_regression`) and a more-specific `**/*.info.srv` (`e2e`)
classifies `my_module.info.srv` as the union `{e2e, visual_regression}`.

Union is the safe direction for a recommender: a more-specific rule can *add* coverage
but never silently *remove* it. First-match-wins is intentionally **not** used. Merge
order between floor and recipe rules is therefore irrelevant.

## 6. Project override

A project may fully replace the shipped floor with
`<project>/.visual-review/change-impact.json` — **same schema** as the data file. When
that file exists, `change-impact-classify.sh` uses it **instead of** the floor
(full replacement, not a merge — predictable, no layered-precedence surprises). The
classifier reports `rule_source: "project-override"` vs `"default"` so the dispatcher
can show which base ruleset was used. The recipe-supplied `--rules-from` rules (section
3a) still union onto whichever base applies, yielding `project-override+recipe` when both
are present.

`<project>` is the memory project folder (the one with `project_state.md`). A malformed
override file ⇒ the classifier falls back to defaults and emits a warning rather than
failing the review.

## 7. Versioning policy

- **Major bumps** (`2.0`): removed/reshaped keys, changed match semantics, changed
  union behavior.
- **Minor bumps** (`1.1`): new optional keys, new gate values in the `e2e` /
  `visual_regression` family.
- v1.0 committed for v4.11.0.

## 8. Non-goals

- No regex rules — globs only (no injection surface).
- No per-rule priority/ordering — union semantics make order irrelevant.
- No dispatch of `visual_parity` from this table — parity is reference-driven.
- No framework globs in the shipped floor — those come per run from the stack's recipe (`--rules-from`).
- No layered floor+override merge — a project override fully replaces the floor; the
  recipe `--rules-from` rules, by contrast, **union** onto whichever base applies.
