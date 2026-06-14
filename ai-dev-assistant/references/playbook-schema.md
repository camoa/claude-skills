# Playbook Schema v1.0

**Introduced:** ai-dev-assistant v3.15.0
**Owner:** `commands/playbook-capture.md`, `commands/playbook-review.md`, `scripts/playbook-read.sh`
**Consumers:** `skills/guide-integrator`, `commands/research.md`, `commands/design.md`, `commands/implement.md`, `commands/complete.md`

A "playbook" is a curated collection of opinionated rules ("plays") that govern development decisions. Playbooks come in two layers:

- **Published playbook sets** — namespaced dev-guides categories (e.g., `<framework>/best-practices/<author>/*`). Multiple authors coexist; users subscribe per project via `Playbook Sets` in `project_state.md`.
- **Local project playbook** — a single markdown file the user maintains, declared via `User Playbook` in `project_state.md`. Can override published opinions or extend them with topics published sets don't cover. **Local always wins on conflict.**

This schema specifies the **recommended structure** for a local playbook file. Convention but not required — plays without the recommended structure load as raw text and Claude can still read them; they just don't surface in structured tooling like `/playbook-review` or future `/validate:playbook`.

## 1. File location

The user declares the absolute path via `**User Playbook:**` in `project_state.md`. Common conventions in the wild:

- `<project>/docs/technical/guides/development-patterns.md`
- `<project>/docs/conventions.md`
- `<project>/docs/playbook.md`
- `<project>/CONTRIBUTING.md` (if it doubles as opinion record)

The framework respects whatever path the user declares. No filename enforcement.

## 2. Recommended structure

```markdown
# Playbook: <project name>

Brief description of what this playbook covers.

## <Domain — e.g., CSS / SCSS>

### <Title — concrete rule statement>

**What:** <one-line restatement of the rule>
**Rationale:** <why this rule; what breaks without it>
**When it applies:** <scope — file types, contexts, exceptions>
**Example:**

```scss
// Wrong
font-size: 2.125rem;

// Right
@include font-size($h2-font-size);
```

### <Next play title>

**What:** ...
**Rationale:** ...
**When it applies:** ...
**Example:** ...

## <Next domain section>

### <Play>
...
```

## 3. Field contracts

Each play (an `### H3` block under an `## H2` domain section) carries four optional-but-recommended bold-prefixed fields:

| Field | Type | Required? | Purpose |
|---|---|---|---|
| `**What:**` | one-line statement | Recommended | Restate the rule clearly. Used as the citation summary in conflict logs and `/playbook-active` |
| `**Rationale:**` | prose | Recommended | Why the rule exists; what breaks without it. Surfaces when Claude is asked to explain a decision |
| `**When it applies:**` | prose | Recommended | Scope: file types, contexts, exceptions. Helps the agent know when to apply vs not |
| `**Example:**` | code block(s) | Recommended | Wrong/right pairs. Most useful for code-style rules |

Plays may include other content (additional prose, additional code blocks, links). The four fields above are what `playbook-read.sh` extracts; everything else is preserved as raw text in the play's `body` field.

## 4. Play structure rules (for parser)

`scripts/playbook-read.sh` parses the file with these rules:

- **`# H1`** — single, optional, file-level title. Ignored by parser (decorative).
- **`## H2`** — domain section. Each play inherits the most-recent H2 as its `section` field.
- **`### H3`** — one play. The H3 text becomes the play's `title`.
- **Body** — everything between this `### H3` and the next H3 or H2. Parser scans for the four bold-prefixed fields and extracts them; everything else stays in `body_raw`.
- **No frontmatter** at the file level. Plays are self-contained markdown.

Plays at the top of the file (before any `## H2`) inherit `section: "<root>"`.

## 5. Free-form fallback

A playbook file without `### H3` plays loads as a single synthetic play:

```json
{
  "title": "<file-name>",
  "section": "<root>",
  "applicability": "free-form",
  "body_raw": "<entire file contents>"
}
```

Claude has the content available; it just won't surface in structured tooling. Users with existing playbooks in non-standard formats can opt in to structure incrementally — convert one section at a time.

## 6. Parsed output (JSON)

`scripts/playbook-read.sh` emits:

```json
{
  "schema_version": "1.0",
  "path": "/abs/path/to/playbook.md",
  "plays": [
    {
      "title": "Use @include font-size() not raw font-size:",
      "section": "CSS / SCSS",
      "what": "Never set font-size: directly...",
      "rationale": "Bootstrap's @include font-size() handles RFS scaling automatically.",
      "when_it_applies": "All headings, body text, and any element where typography responds to viewport.",
      "example_blocks": ["// Wrong\nfont-size: 2.125rem;\n\n// Right\n@include font-size($h2-font-size);"],
      "body_raw": "**What:** Never set...\n**Rationale:** ...",
      "source_lines": { "start": 18, "end": 41 },
      "applicability": "structured"
    },
    {
      "title": "<freeform-play-title>",
      "section": "<root>",
      "applicability": "free-form",
      "body_raw": "...",
      "source_lines": { "start": 1, "end": 1410 }
    }
  ],
  "warnings": [
    "Play 'Foo' (line 132): missing **Rationale:** field"
  ]
}
```

Empty `plays[]` allowed when file is empty. `warnings[]` is informational; never fatal.

## 7. Invariants

- **Read-only by parser.** `playbook-read.sh` never modifies the file. Writes happen only via `/playbook-capture` + `/playbook-review` (which use `Edit`/`Write` tools, not the parser).
- **Defensive parsing.** Malformed plays produce warnings, never throws. Empty/missing file produces empty `plays[]` + warning.
- **Source-line preservation.** Every parsed play carries its source line range, so `/playbook-review` can surgically edit individual plays without re-rendering the whole file.
- **Encoding:** UTF-8. Em-dashes, smart quotes, code blocks all preserved verbatim.

## 8. Versioning policy

- **Major bumps** (`2.0`) are breaking: changes to the `### H3 = play` rule, the four field names, or the parser output JSON shape.
- **Minor bumps** (`1.1`) are additive: new optional fields, additional metadata in output JSON, clarifications.
- **Patch bumps** do not exist for schema versioning.

v1.0 is the committed shape for v3.15.0.

## 9. Non-goals

- **No machine-readable enforcement.** This schema describes structure for parsing, not a JSON-Schema validator. `/validate:playbook` (deferred to v2) would be the layer that enforces structure if it ever ships.
- **No play-level frontmatter.** Plays are markdown, not YAML+markdown. Keeps authoring frictionless.
- **No play IDs / cross-references.** Plays are addressed by `title + section`; collisions on duplicate titles produce a warning + suffix (`title (2)`) but not enforcement.
- **No conditional/parameterized plays.** A play applies or it doesn't; no "this rule only when project uses Bootstrap 5+" logic. Authors split into multiple plays if they need conditional scope.
