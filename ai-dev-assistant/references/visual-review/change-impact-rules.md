# Change-Impact Rules v1.0

**Introduced:** ai-dev-assistant v4.11.0 (Task A — `visual_and_e2e_review_gates`)
**Owner:** `scripts/change-impact-classify.sh`
**Data file:** `references/visual-review/change-impact-rules.json` (canonical defaults)
**Consumers:** `commands/review.md` step 6 (via `change-impact-dispatch.md`)

The change-impact ruleset maps a code diff to the set of review gates the change
*could* justify. It is what makes `/review`'s dispatcher a **recommender**: a CSS-only
diff recommends `visual_regression`; a PHP diff recommends `e2e` + `visual_regression`;
a docs-only diff recommends nothing.

The dispatcher only ever **recommends** from this table — the user opts in per task
(`change-impact-dispatch.md`). The table never forces a gate to run.

## 1. Format — JSON, not YAML

The ruleset is JSON because `change-impact-classify.sh` (a shell script) parses it with
`jq`, and the framework ships no YAML parser. The sibling surface registry is YAML
because only Claude and the Task B/C/D commands read it (`surface-registry-schema.md`
§6). Two formats, each matched to its reader.

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
| `rules[].glob` | string | A path glob (§4). |
| `rules[].gates` | list | Subset of `["e2e", "visual_regression"]`. |
| `default_gates` | list | Gates applied to a changed file that matches **no** rule. Default `[]` — unmatched files (docs, tests, CI config) recommend nothing. |

`visual_parity` is **never** in a rule's `gates` — parity needs an explicit design
reference and is never auto-dispatched (it auto-runs separately on design-implementation
tasks; see `change-impact-dispatch.md`). The dispatch surface from this table is `e2e`
and `visual_regression` only. `a11y` is not a separate target either — it rides inside
`visual_regression` (Task C pairs it).

## 3. Default ruleset

Shipped in `change-impact-rules.json`:

| Glob | Gates | Why |
|---|---|---|
| `**/*.css` | `visual_regression` | Pure presentation — appearance can change, behavior cannot. |
| `**/*.scss` | `visual_regression` | Compiles to CSS. |
| `**/*.twig` | `visual_regression` | Markup/theming — visual surface. |
| `**/*.js` | `e2e`, `visual_regression` | Behavior **and** rendered output. |
| `**/*.ts` | `e2e`, `visual_regression` | Same. |
| `**/*.php` | `e2e`, `visual_regression` | Logic — can change behavior and rendered output. |
| `**/*.yml` | `e2e`, `visual_regression` | Config/routing/services — broad blast radius. |
| `**/*.module` | `e2e` | Hook logic — behavioral. |
| `**/*.info.yml` | `e2e` | Module/theme metadata — behavioral wiring. |

`default_gates` is `[]`: a changed `README.md`, a test file, or a CI workflow
recommends no gate.

## 4. Glob matching

`change-impact-classify.sh` matches each changed file path against each rule glob using
bash `[[ ]]` pattern matching, with one normalization:

- A leading `**/` is **stripped** — the remainder is matched against the full path.
  Because bash `[[ ]]` `*` matches across `/`, `*.css` already matches both
  `style.css` and `web/themes/foo/style.css`. So `**/*.css` means "any `.css` at any
  depth," as intended.
- Globs without a leading `**/` are matched as-is. Note `*` in `[[ ]]` matches `/`, so
  these patterns are simple prefix/suffix matches, **not** full pathspec — adequate for
  a recommender.

This is deliberately simple: globs (not regex) — lowest cognitive load, no
regex-injection surface (research D3, consistent with the v4.1.0 adherence work's
literal-match choice).

## 5. Multi-match is a union — not first-match-wins

A file that matches several rules receives the **union** of their gates. Example:
`mymodule.info.yml` matches both `**/*.yml` (`e2e`, `visual_regression`) and
`**/*.info.yml` (`e2e`) → union `{e2e, visual_regression}`.

Union is the safe direction for a recommender: a more-specific rule can *add* coverage
but never silently *remove* it. First-match-wins is intentionally **not** used.

## 6. Project override

A project may fully replace the defaults with
`<project>/.visual-review/change-impact.json` — **same schema** as the data file. When
that file exists, `change-impact-classify.sh` uses it **instead of** the defaults
(full replacement, not a merge — predictable, no layered-precedence surprises). The
classifier reports `rule_source: "project-override"` vs `"default"` so the dispatcher
can show which ruleset was used.

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
- No layered defaults+override merge — override is full replacement.
