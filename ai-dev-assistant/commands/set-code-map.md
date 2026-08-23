---
description: "Use when a user wants to set, update, or clear a ai-dev-assistant project's Code Map — the path to an existing code-map artifact the user built with their own tool, distinct from codePath. Accepts an explicit path (validated to stay inside the project folder or codePath) or the --none sentinel to record an explicit decline. Never installs or runs a mapping tool; the user builds and refreshes the map. Updates project_state.md (source of truth). Introduced v5.26.0."
allowed-tools: Read, Edit, Bash
argument-hint: "[<path> | --none]"
---

# Set Code Map

Set, update, or clear the `Code Map` metadata for the active ai-dev-assistant project. The Code
Map is the path to a code-map artifact — a structural or architectural map of the code at
`codePath` — that the user built with their own tool. This command only records where that
artifact is. It does not build one.

## What this command does not do

- **It never installs a mapping tool, and never runs one.** The user creates the map. This
  command records where it lives.
- **It never writes to the map artifact.** Refreshing a stale map is the user's job; the
  framework can recommend an update, it does not produce one.
- **It does not judge whether a map is a good idea.** That conversation, and the readable-artifact
  shape a map should have, belongs to the `internal-prior-art-finder` skill's map-conversation
  reference. This command only takes the outcome of that conversation and writes it down.
- **It does not re-ask once the project has an answer.** Recording is once per project. A prior
  code search reads `**Code Map:**` from `project_state.md` and uses it (or its absence, or an
  explicit decline) without prompting again.

## Usage

```
/ai-dev-assistant:set-code-map /absolute/or/repo-relative/path/to/map-artifact
/ai-dev-assistant:set-code-map --none
/ai-dev-assistant:set-code-map                       # interactive: show current value, ask
```

## What this does

1. Resolves the active project by running `${CLAUDE_PLUGIN_ROOT}/scripts/session-context-read.sh`
   (Bash) and parsing its JSON (`.project`, `.projectPath`, `.task`, `.taskPath`). If no project
   is active, prompt the user to pick one via `/ai-dev-assistant:next` first.
2. **Reads current value** by running
   `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parsing its
   JSON — `codeMap` and `codePath` — so the confirm prompt can show what's changing and so the new
   value can be validated against `codePath`.
3. **Resolves the new value:**
   - With `<path>` arg: `realpath -m` normalize against `$PWD` if given relative, then validate
     per **Acceptance / rejection rules** below.
   - With `--none`: set to the `(none)` sentinel — an explicit decline, distinct from the field
     being absent (never asked).
   - With no arg: show the current value, then ask for a path or `--none`.
4. **Writes to `project_state.md`** — the `**Code Map:**` line (replace if it exists, insert into
   the metadata block if absent).
5. **Reports** what changed, and the containing root (`codePath` or the project folder) the stored
   path is relative to.

## What it writes

### project_state.md

In the metadata block, alongside the other `set-*` fields:

```markdown
# <Project Name>

**Created:** YYYY-MM-DD
**Code path:** /absolute/path/to/code
**Code Map:** <path to the map artifact>
...
```

If the `**Code Map:**` line exists, replace its value in place. Otherwise insert it immediately
after the `**Code path:**` line if present, or after `**Created:**` if `**Code path:**` is
absent.

**Stored form:** when the resolved path sits inside `codePath`, store it relative to `codePath`
(a map is a code artifact and travels with the repo). When `codePath` is unknown or
`(docs-only)` and the path sits inside the project's memory folder instead, store it relative to
the project folder, and say so in the confirmation. Either way the command reports the absolute
path it resolved before writing, so what got saved is never ambiguous.

**The `(none)` sentinel** is written verbatim as `**Code Map:** (none)` and means: the user was
asked, and declined. It is a distinct state from the line being absent (never asked) — both the
internal-prior-art search and any later run of this command must be able to tell the two apart,
the same distinction `**Code path:**` already draws between `unknown` and `(docs-only)`.

## Acceptance / rejection rules

- **Path accepted:** must resolve, after `realpath -m`, to a location inside `codePath` (when
  `codePath` is set to a real path) **or** inside the project's own memory folder. If the map file
  does not currently exist, warn but allow — the user may be pointing at a map they are about to
  build: `"Note: <path> does not exist yet. Saved anyway; the search will use it once it does."`
- **Path rejected (hard):** any of the following aborts with an error, no write happens:
  - Contains newlines or null bytes.
  - Cannot be normalized by `realpath -m`.
  - **Escapes both containers** — resolves outside `codePath` and outside the project folder.
    This is a hard rule, not a warn-and-allow: a map path is data a later search step reads
    without re-confirming, so an escaping path is dropped the same way `visual_review_path_escape`
    drops one, never carried forward on a warning.
- **`--none`:** always accepted; always overwrites whatever was there, including a previously set
  path.
- **Cancel (user declines to give a path or `--none` at the interactive prompt):** no change; exit
  with "No change."

## Examples

```
/ai-dev-assistant:set-code-map /home/user/workspace/my-module/.map/graph.json

→ Reading project at /home/user/.../projects/my_project
  Current Code Map: (not set)
  codePath: /home/user/workspace/my-module
  Path resolves inside codePath.
  Setting Code Map to: .map/graph.json (relative to codePath)
  ✓ Updated project_state.md
```

```
/ai-dev-assistant:set-code-map --none

→ Setting Code Map to: (none)
  Recorded as declined — the map conversation will not be re-asked for this project.
  ✓ Updated project_state.md
```

```
/ai-dev-assistant:set-code-map /home/user/workspace/my-module/.map/graph.json

→ Note: /home/user/workspace/my-module/.map/graph.json does not exist yet.
  Saved anyway; the search will use it once it does.
  ✓ Updated project_state.md
```

```
/ai-dev-assistant:set-code-map /etc/some-map.json

→ Error: /etc/some-map.json escapes both codePath and the project folder. Not saved.
  Point at a location inside the project folder or the code at codePath.
```

## Errors

| Error | Resolution |
|---|---|
| `No active project. Run /ai-dev-assistant:next first.` | Select a project via /next, then retry. |
| `Path '<p>' is not absolute after normalization.` | Provide a valid path; relative paths are normalized against `$PWD`. |
| `Path '<p>' contains invalid characters.` | No newlines or null bytes; re-enter. |
| `Path '<p>' escapes both codePath and the project folder.` | Point at a location inside the project folder or the code at `codePath`. |
| `project_state.md not found at <p>` | Ensure the project is properly initialized (should not happen for /new-created projects). |

## Related commands

- `/ai-dev-assistant:set-code-path` — sets `codePath` itself, which this command's containment
  check validates against. Set `codePath` first when both are unknown.
- `/ai-dev-assistant:research` — the internal prior-art step reads `**Code Map:**` automatically
  once set; it never re-prompts.
- `/ai-dev-assistant:status` — shows Code Map in the project overview.

## Discoverability

- README Commands table
- Command frontmatter `description` (this file)
- Plugin CONVENTIONS.md Project Metadata section
- marketplace.json description
- The `internal-prior-art-finder` skill's map conversation, which points here once the user says
  they have (or want) a map

## Output

Prints the resolved Code Map value and the container it was recorded relative to (or `(none)` for
an explicit decline).

Writes the `**Code Map:**` field in `project_state.md`. Nothing else on disk changes — this
command does not touch `~/.claude/ai-dev-assistant/active_projects.json` and never writes to the
map artifact itself.
