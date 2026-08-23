# Code-map guidance — the conversation, and the shape of a readable map

Loaded once, at step 3, only when no `**Code Map:**` line is recorded in `project_state.md` and the
project has never declined one. Read this at that moment, not before — most runs never load it.

**No tool is named here, on purpose.** A map accelerates finding a candidate; it is never the
mechanism, and which concrete tool suits a given stack is asset-layer knowledge, resolved through the
project's existing process-recipe path, not hardcoded into this engine. This file carries the shape a
map has to have to be usable here, and the questions worth asking before pointing at one — not a
product name.

## What a map is, and why it's optional

A structural artifact of the codebase — file, symbol, and dependency relationships, sometimes
capability-level summaries too — built by a separate tool the user runs, on the user's own schedule.
With no map recorded, the code search in step 3 reads the codebase directly with `Grep`/`Glob`/`Read`
and runs at full function. A map is a speed-up for a large repository, never a requirement.

## The readable-artifact shape

A map is usable here only if it can be read the way everything else this skill reads is read — plain
files on disk, no infrastructure to stand up. Concretely:

- **Plain files** — JSON, Markdown, HTML, or similar, sitting at a path this skill can `Read`. A map
  exposed *only* through a running server or an MCP tool this session doesn't have connected is not
  readable here, however good the map itself is.
- **Reaches the functional layer, ideally.** The question a prior-art search asks is "what capability
  already exists," not "what symbols exist." A map that ingests docs, configs, and schema alongside
  code gets closer to that layer than a pure call-graph; a structural-only map still helps narrow
  *where* to look, it just can't answer the capability question by itself — the actual code still has
  to confirm every candidate (step 3's rule: the verdict is always read from the code, never from the
  map's summary of it).
- **No required key for the code-parsing layer.** Local, deterministic extraction (tree-sitter and
  similar) needs no account or paid service. An optional semantic pass over docs or media calling out
  to a model is the user's own choice and the user's own key — never something this skill depends on.

## Four questions worth asking about a candidate tool

Before recommending any tool (through the process-recipe layer, never by name in this file), verify
against its own documentation, not assumption:

1. **Does it rebuild on commit?** Some install a post-commit hook and stay current automatically;
   others require a manual re-run.
2. **Is a rebuild incremental?** Re-extracting only changed files matters on a large repository —
   the difference between a map refresh costing seconds versus minutes.
3. **Does the artifact record its own build timestamp or the commit it was built at?** Many don't
   document this at all. Don't assume one does.
4. **Does the tool expose a status or freshness command?** If it does, it's a **bonus** input this
   skill's caller can fold in through `map-currency.sh --freshness-report <path>` — a file the tool
   already wrote, never a command this framework runs. If it doesn't, currency still has to be
   established some other way; see below.

A tool documenting none of the above is not a disqualifier. It changes nothing about how currency
gets checked, because that check never depends on the tool in the first place.

## How currency is actually established

Regardless of what a tool documents, currency comes from comparing the **map artifact's modification
time against the repository's last commit** — filesystem plus git, works for any tool including one
that reports nothing about itself. That's `scripts/map-currency.sh`'s job, called in step 3 after this
guidance, never here. A stale map is disclosed as stale and the code is searched directly anyway; a
map that hasn't seen this morning's commit is worse than no map, never treated as a clean "nothing
found."

## The conversation itself

Ask once, plainly: does a map exist for this repository, or is one wanted? Three outcomes:

- **Yes, one exists** — ask where. Validate the path resolves inside `codePath` or the project folder
  before reading anything from it (an escaping path is dropped with a warning, never followed). Point
  the project at it with `/set-code-map`, which records the `**Code Map:**` line in
  `project_state.md`. That line, once written, is read automatically from then on and never re-asked.
- **No, but one is wanted** — guide the user to the process-recipe layer's tool recommendation and
  the shape criteria above; the user runs the setup, this framework never installs or runs the tool.
  Once they've built it, the same `/set-code-map` step records it.
- **No, and none is wanted** — record the decline. A decline is a real answer, not a deferred yes; it
  is never re-offered on a later run. The code search proceeds directly, at full function, exactly as
  if this file had never been read.

**Never performed by this skill, in any branch:** installing a tool, running one unattended, writing
to the user's map artifact, or refreshing a map on the user's behalf. Refreshing is recommended when
`map-currency.sh` reports `stale`; it is never performed here.
