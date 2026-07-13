---
description: "Author or refine a project-level naming glossary — a lean term-to-definition list that keeps naming consistent across a project's tasks. Trigger: 'glossary', 'naming glossary', 'define term', 'ubiquitous language', 'naming conventions'. Distinct from architecture.md (per-task design) and from the user-ownable guides layer — this is a scratch vocabulary only."
allowed-tools: Read, Write, Edit, Bash, Glob
argument-hint: "[<term> — <one-line definition>]"
---

# Glossary

Author and maintain a **project-level** naming glossary — a lean term → one-line-definition list that keeps vocabulary consistent across a project's tasks (multiple tasks, multiple sessions, sometimes multiple contributors). Modeled on mattpocock/skills' `domain-modeling` `CONTEXT.md` pattern.

**This is a scratch vocabulary, not a spec.** Each entry is a name and a one-line definition, optionally an "avoid these synonyms" note — never rationale, never history, never acceptance criteria. If an entry needs more than two lines it belongs in `architecture.md`, not here.

**Distinct from:**
- `architecture/main.md` / `<task>/architecture.md` — **per-task design** (components, dependencies, data flow, decisions). The glossary holds only names and one-line meanings; it never carries design rationale.
- The user-ownable knowledge-layer / guides — that layer is portable, user-owned reference material. This glossary is agent-maintained scratch state for ONE project's naming and does not travel with the user across projects.

## Usage

```
/ai-dev-assistant:glossary                                          # show glossary; offer to add a term
/ai-dev-assistant:glossary <term> — <one-line definition>            # add or refine a term
/ai-dev-assistant:glossary <term> — <definition> // avoid: <a>, <b>  # add an avoid-synonyms note
```

## What this does

### Step 1 — Resolve project

Resolve the active project the same way `/playbook-active` and `/set-user-playbook` do: run `${CLAUDE_PLUGIN_ROOT}/scripts/project-state-read.sh "<project_folder>"` (Bash) and parse its JSON. If no project is already known in this session, check the registry at `~/.claude/ai-dev-assistant/active_projects.json` — a single active project auto-selects; multiple → ask which one; none → ask for a project path. Refuse with a helpful message if nothing resolves.

`GLOSSARY_PATH="<project_folder>/glossary.md"` — a **project-root** file, sibling to `project_state.md`, NOT under any task folder. This is what makes it project-level rather than per-task.

### Step 2 — Create if absent (idempotent)

If `glossary.md` does not exist, `Write` it with only the lean skeleton:

```markdown
# Glossary — <Project Name>

Scratch vocabulary for this project — a lean term → one-line-definition list,
NOT a spec. Maintained by `/ai-dev-assistant:glossary`. Read (soft, non-blocking)
at Research/Design/Implement phase entry so naming stays consistent across tasks.
Distinct from `architecture.md` (per-task design) — this file holds names only.

## Terms

<!-- - **<Term>** — <one-line definition>. _Avoid:_ <synonym>, <synonym> -->
```

Re-running `/glossary` when the file already exists does **not** recreate it or touch the header — proceed to Step 3. Creating on an already-present file is a no-op read, never a rewrite.

### Step 3 — Add / refine a term

**If `$ARGUMENTS` supplies `<term> — <definition>`** (accept `—`, `--`, or `:` as the term/definition separator; an optional trailing `// avoid: a, b` clause sets the synonym note):
1. Parse `term`, `definition`, optional `avoid[]`.
2. Look up `term` (case-insensitive) among the existing `## Terms` entries.
   - **Exists, definition unchanged** → no-op; print `Glossary already has "<term>" with that definition — no change.`
   - **Exists, definition differs** → show the current line, confirm the replacement (default `[y]`), then `Edit` the line in place.
   - **Absent** → append a new `- **<Term>** — <definition>.` line (plus `_Avoid:_ <a>, <b>` when given) under `## Terms`, keeping the list alphabetically sorted by term.
3. Confirm: `✓ Glossary updated: <path>`.

**If `$ARGUMENTS` is empty:**
1. Read and print the current `## Terms` list (or `no terms yet` if empty).
2. Ask: `Add a term? [y]es / [n]o (default n)`. On `[y]` prompt for `term`, `definition`, optional `avoid` synonyms, then apply the add/refine logic from step 3 above.

### Step 4 — Keep it lean (enforced softly)

Before writing, if the file would exceed **~40 terms** or **~120 lines**, print one advisory line (never blocks): `⚠ Glossary is growing large (<N> terms) — consider whether some entries belong in architecture.md instead.` Do not refuse the write.

## Idempotency

- Running with no args on an existing glossary never mutates it (read-only unless the user opts into `[y]` add).
- Adding the same `<term> — <definition>` twice is a no-op after the first write (Step 3's "definition unchanged" branch short-circuits).
- Step 2's create is skipped whenever the file already exists — the header is written exactly once.

## Related

- `/ai-dev-assistant:research <task>` / `/design <task>` / `/implement <task>` — each phase-entry context-load step does a soft, non-blocking read of `glossary.md` when it exists.
- `architecture/main.md` / `<task>/architecture.md` — per-task design; NOT where naming lives.
- `/ai-dev-assistant:playbook-capture` — captures opinionated build rules (a different artifact: playbook is "how to build it," glossary is "what things are called").
