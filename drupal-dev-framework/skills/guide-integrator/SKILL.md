---
name: guide-integrator
description: "Use when a phase command (research/design/implement) needs to load methodology references, online dev-guides, and project playbooks before task work begins. **v4.0.0+: deterministic detection** via scripts/dev-guides-detect.sh (replaces agent-mediated keyword detection). Delegates guide fetching to dev-guides-navigator. Loads playbook layers via scripts/playbook-load-deterministic.sh. Cross-references conflicts. Records loaded guide IDs into session_context.json loadedGuides[] to prevent re-loads."
version: 5.1.0
user-invocable: false
model: sonnet
---

# Guide Integrator

Load development references and integrate into architecture documents. Two sources: plugin methodology refs and online dev-guides (via navigator).

## Built-in References (Methodology)

| Topic | Reference File |
|-------|----------------|
| Test-Driven Development | `references/tdd-workflow.md` |
| SOLID Principles | `references/solid-drupal.md` |
| DRY Patterns | `references/dry-patterns.md` |
| Library-First/CLI-First | `references/library-first.md` |
| Quality Gates | `references/quality-gates.md` |
| Purposeful Code | `references/purposeful-code.md` |

## Activation

**PROACTIVE:** Activate at the START of every phase activity — do not wait for explicit request.

Activate when:
- **Any Phase 1 activity** — load guides for the task's Drupal domain before research
- **Any Phase 2 activity** — load architecture decision guides before design
- **Any Phase 3 activity** — load security, SDC, JS guides before implementation
- Designing features that match reference topics
- User mentions specific patterns (TDD, SOLID, DRY)
- Architecture drafting for any feature
- Auto-triggered by `architecture-drafter` agent

**Skip if:** The relevant guide is already listed in `loadedGuides[]` of the per-workspace `session_context.json` (see "Record Loaded Guide" below). The conversation context is an unreliable fallback; the file is the source of truth.

## Auto-Load Rules (Plugin References)

| Keywords Detected | Reference to Load |
|-------------------|-------------------|
| "test", "TDD", "unit test", "kernel test" | `references/tdd-workflow.md` |
| "service", "dependency", "inject", "SOLID" | `references/solid-drupal.md` |
| "duplicate", "reuse", "DRY", "extract" | `references/dry-patterns.md` |
| "form", "drush", "command", "service first" | `references/library-first.md` |
| "complete", "done", "quality", "gate" | `references/quality-gates.md` |

**v4.0.0+: deterministic detection.** As of v4.0.0, keyword detection runs via `${CLAUDE_PLUGIN_ROOT}/scripts/dev-guides-detect.sh` (not agent judgment). The script greps `task.md` + phase artifacts + alignment.md for the keywords above and returns a structured JSON of matched keywords + guide IDs. Phase commands invoke the script BEFORE prompting the user, populating the prompt's "Auto-loaded based on task keywords:" line from script output. This eliminates bypass-by-declaration (agent claiming "none matched" without running detection).

## Workflow

### 1. Load Plugin References (Methodology)

Based on detected keywords in the task:
1. Check `loadedGuides[]` (see "Record Loaded Guide" below). If the ID (e.g. `plugin:solid-drupal`) is already present, skip.
2. Identify which methodology references apply (see Auto-Load Rules)
3. Read each applicable reference file
4. Record the guide ID via the snippet in "Record Loaded Guide"
5. Extract patterns relevant to current task

### 2. Delegate Online Guides to Navigator

For Drupal-specific architecture decisions, invoke the `dev-guides-navigator` skill with the task keywords. For each topic the navigator returns:
1. Check `loadedGuides[]`. If the topic ID (e.g. `drupal/forms/form-validation`) is already present, skip re-fetching.
2. Fetch via the navigator (which handles its own content caching of `llms.txt`).
3. Record the topic ID via the snippet in "Record Loaded Guide".

The navigator handles:
- Hash-based caching of `llms.txt` (no redundant fetches)
- Topic matching with KG metadata disambiguation
- Routing to the correct guide via topic `index.md`
- Fetching the specific guide content

Do NOT fetch `llms.txt` or dev-guides URLs directly — the navigator does this with caching and disambiguation.

### 2b. Record Loaded Guide

For every guide actually loaded (methodology or dev-guide), append its ID to the per-workspace `session_context.json` `loadedGuides[]`. Idempotent — skip if already present.

Guide ID conventions:
- Plugin methodology refs: `plugin:<basename>` (e.g. `plugin:solid-drupal`, `plugin:tdd-workflow`)
- Dev-guides topics: the topic path as returned by `dev-guides-navigator` (e.g. `drupal/forms/form-validation`, `design-systems/radix-sdc`)

Run this after each successful load, substituting `{GUIDE_ID}`:

```bash
GUIDE_ID="{GUIDE_ID}"
[ -n "$GUIDE_ID" ] || exit 0   # guard against empty IDs polluting the list
WORKSPACE_HASH=$(echo -n "$PWD" | md5sum | cut -d' ' -f1)
SESS_FILE=~/.claude/drupal-dev-framework/sessions/${WORKSPACE_HASH}.json
[ -s "$SESS_FILE" ] || exit 0
jq --arg g "$GUIDE_ID" \
  'if (.loadedGuides // []) | index($g) then . else .loadedGuides = ((.loadedGuides // []) + [$g]) end' \
  "$SESS_FILE" > "$SESS_FILE.tmp" && mv "$SESS_FILE.tmp" "$SESS_FILE"
```

If `session_context.json` does not yet exist, skip silently — the next framework command will create it via `session-context-writer` and future loads will be recorded.

### 3. Extract Applicable Patterns

From all loaded sources (methodology refs + navigator results), identify:
- Patterns that apply to current feature
- Checklists to follow
- Warnings or anti-patterns
- Recommended approaches

### 4. Add to Architecture

Use `Edit` to add references section to architecture file:

```markdown
## Development References

### Plugin References (Methodology)
| Reference | Key Patterns |
|-----------|--------------|
| solid-drupal.md | Single responsibility, DI |
| library-first.md | Service → Form → Route |
| tdd-workflow.md | Red-Green-Refactor |

### Dev-Guides Applied (via Navigator)
| Topic | Key Decisions |
|-------|--------------|
| drupal/forms/ | ConfigFormBase vs FormBase |
| drupal/entities/ | Content entity vs config entity |

### Enforcement Points
| Phase | Principle | Source |
|-------|-----------|--------|
| Design | Library-First | references/library-first.md |
| Design | SOLID | references/solid-drupal.md |
| Design | Drupal patterns | dev-guides (via navigator) |
| Implement | TDD | references/tdd-workflow.md |
| Implement | DRY | references/dry-patterns.md |
| Complete | Quality Gates | references/quality-gates.md |
| Complete | Security | dev-guides drupal/security/ |
```

### 5. Summarize

Tell user what was integrated from each source: plugin methodology and dev-guides topics.

### 6. Load Playbook (v3.15.0+)

After loading methodology refs and dev-guides topics, load the project's playbook layers:

#### 6a. Read project state

Invoke `project-state-reader` skill to get `playbookSets[]`, `userPlaybook`, `userPlaybookState`, and `playbookResolutions[]`.

#### 6b-c. Deterministic load (v4.0.0+)

As of v4.0.0, the playbook load step is delegated to a single deterministic script that handles both shipped sets AND local playbook in one invocation:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/playbook-load-deterministic.sh" "<project_folder>"
```

The script reads `project_state.md` via `project-state-read.sh`, resolves `playbookSets[]` (records intent — actual fetch from dev-guides-navigator happens here in step 6b for guide CONTENT), loads `userPlaybook` via `playbook-read.sh`, and emits a structured JSON with `playbook_sets_loaded`, `user_playbook_loaded`, `plays_by_section` count map. The integrator stores the JSON as `<task>/_playbook-load.json` audit file (per `references/gate-audit-schema.md` v1.0). This replaces the previous agent-mediated load.

For each set in `playbook_sets_loaded[]`: delegate to `dev-guides-navigator` to fetch individual guide pages relevant to the current task domain. Record each loaded guide ID via the snippet in §2b. Track loaded guide titles + summaries for cross-reference.

#### 6d. Detect conflicts

Cross-reference local plays vs shipped guides AND multi-set vs multi-set:

- **Local-vs-shipped:** when a local play's `title` or `section` topic matches a shipped guide's topic AND their normative content differs → emit a conflict (winner: `local`).
- **Multi-set contradiction:** when 2+ shipped sets address the same topic with different normative content → emit a conflict (winner determined by `playbookResolutions[]` if present, else `null` and surface to user).

Emit `conflicts[]` in the return JSON:

```json
{
  "loaded_guides": ["plugin:solid-drupal", "drupal/forms/config-forms"],
  "loaded_playbook_sets": ["drupal/best-practices/camoa"],
  "loaded_local_playbook": { "path": "/abs/path", "play_count": 19 },
  "conflicts": [
    {
      "topic": "font-sizing",
      "type": "local-vs-shipped",
      "playbook_set_citation": {...},
      "local_citation": {...},
      "winner": "local"
    }
  ]
}
```

#### 6e. Surface conflicts once per session per topic

For each conflict in `conflicts[]`:

1. Check session-context state (a per-session "surfaced topics" set) to see if this topic was already surfaced.
2. If not surfaced: print one-line surface to the user (e.g. `"Playbook conflict on `font-sizing`: shipped says X, local says Y. Local wins."`).
3. Record to `<project>/.claude/playbook-conflicts.log` via `playbook-conflicts-write.sh`.
4. Mark topic surfaced for this session.

For multi-set contradictions WITHOUT a stored resolution: prompt the user to pick (1/2/cancel); on choice, persist to `project_state.md` `**Playbook Resolutions:**` map.

For local-vs-shipped: no prompt; precedence rule applies; just announce.

#### 6f. Record loaded playbook IDs

Record each loaded shipped-set guide and the local playbook into `loadedGuides[]` per §2b. Local playbook ID convention: `local:userPlaybook:<basename>`.

## Reference Locations

| Type | Location |
|------|----------|
| Plugin references (methodology) | `{plugin_path}/references/*.md` |
| Dev-guides (online) | Via `dev-guides-navigator` skill |

## Stop Points

STOP and ask user:
- Before adding patterns that conflict with existing architecture
