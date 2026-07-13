# Core Philosophy

Unified philosophy combining Anthropic's skill-creator principles with the guide-framework-maintainer approach.

## Why Skills Exist: Predictability

A skill's job is to wrangle determinism out of a stochastic system. The model is non-deterministic by nature — the same prompt can take a different path on different runs. A skill's root virtue is **predictability**: the same *process* every time the skill fires, not identical output. Two runs of a well-written skill should reach for the same tool, check the same condition, and follow the same order of steps — even when the prose they produce differs.

Several of the levers below serve that goal directly:
- **Progressive disclosure** keeps the process legible — Claude reads the same workflow steps instead of reconstructing them from scattered context each time.
- **Degrees of freedom** (below) matches how tightly a step must be pinned down to how fragile it actually is — a narrow bridge gets guardrails, an open field doesn't need them.
- **Leading words** (below) anchor a recurring step in the process to one cheap, stable token instead of re-deriving it from prose on every occurrence.

When editing a skill, ask whether the change alters which process Claude follows, or only how that process is phrased. Only the former is worth spending tokens on — the same question the no-op test (under Challenge Every Token, below) asks of individual lines.

## The Iron Laws

1. **Claude is already very smart** - Only add context Claude doesn't already have
2. **Reference, don't reproduce** - Point to source files, don't copy implementations
3. **Decision-focused, not tutorial-focused** - "When to use X vs Y" not "How to install X"
4. **One excellent example beats many mediocre ones** - Quality over quantity
5. **Context window is a public good** - Every token must justify its cost
6. **Documentation reflects current truth** - Docs describe what IS, not how we got here

## Content Strategy

| PRESERVE | REMOVE |
|----------|--------|
| Decision criteria ("when to use X vs Y") | Step-by-step tutorials |
| Performance guidelines with thresholds | Verbose installation instructions |
| When-to-use scenarios | Historical explanations |
| Integration patterns | Version change narratives |
| Brief code snippets for pattern recognition | Redundant code blocks |
| File path references to implementations | Full code reproductions |

## Degrees of Freedom

Match specificity to task fragility:

| Freedom Level | When to Use | How to Document |
|---------------|-------------|-----------------|
| **High** | Multiple approaches valid, context-dependent | Text-based instructions, heuristics |
| **Medium** | Preferred pattern exists, some variation OK | Pseudocode or scripts with parameters |
| **Low** | Operations fragile, consistency critical | Specific scripts, exact sequences |

Think of Claude as exploring a path: a narrow bridge with cliffs needs specific guardrails (low freedom), while an open field allows many routes (high freedom).

### Examples by Freedom Level

**High Freedom** (guidelines only):
```markdown
## Writing Style
Use clear, concise language. Prefer active voice.
Adapt tone to the audience and context.
```

**Medium Freedom** (pattern with flexibility):
```markdown
## API Integration Pattern
1. Authenticate with token
2. Make request with appropriate method
3. Handle response/errors

See scripts/api_template.py for base implementation.
Customize headers and endpoints as needed.
```

**Low Freedom** (exact script):
```markdown
## PDF Form Filling
Run exactly:
python scripts/fill_form.py --input form.pdf --data fields.json --output filled.pdf

Do not modify the script without testing.
```

## The DRY Principle

- Information lives in ONE place only
- SKILL.md OR references, never both
- Cross-reference between files, don't duplicate
- If it's in official docs, link to it

### Applying DRY

| Situation | Action |
|-----------|--------|
| Same info needed in SKILL.md and reference | Put in one place, link from other |
| Official docs cover the topic | Link to docs, add only unique context |
| Multiple skills need same info | Create shared reference, link from both |
| Code exists in codebase | Reference file path, don't copy |

## Leading Words

A **leading word** compresses a recurring behavioral pattern into one evocative, already-pretrained token — *tight* loop, *seam*, *deep module*, *tracer bullet* — and is then reused **as that token**, never re-explained as a full sentence each time it recurs. This is a steering technique, not a naming convention.

It works because the token recruits priors the model already holds from training — "tight loop" already carries change-one-thing/verify/repeat connotations without restating them. Define the term once, then let bare repetition of the word do the steering:

```markdown
## Iterating on the query

Work this as a **tight loop**: change one filter, re-run, check the row
count, repeat. Don't batch multiple filter changes before checking output.

...

## Handling a failed query

If a tight loop surfaces a null-count spike, stop and inspect before
continuing to the next filter.
```

The second mention doesn't re-explain "tight loop" — it just uses it, because the definition already landed once. Compare that to restating the behavior in full at every recurrence, which pays a paragraph's worth of tokens each time instead of a word's worth.

**Use a leading word when**: the pattern recurs 3+ times in one skill body, carries enough behavioral content to be worth a paragraph unabridged, and maps onto a term the model already has priors for (a software-engineering idiom, a well-known metaphor). Don't coin a private jargon term for a pattern used once — that's ceremony, not compression, and an unfamiliar token carries no priors to recruit.

## Context Window Budget

The "context window as public good" principle has specific, upstream-documented budget numbers. Plugin authors should design around all of them:

### Skill-description budget (at session start)

- **Dynamic budget**: 1% of context window, with an **8,000-character fallback**
- Claude Code shortens descriptions to fit this budget. Descriptions that get trimmed lose the keywords Claude uses to match your request.
- **Per-entry cap**: Each skill's combined `description` + `when_to_use` is truncated at **1,536 characters** regardless of the overall budget.
- **Override**: `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable raises the global limit.

Front-load your skill description: the first sentence matters most because it's what survives trimming.

### Skill-body budget (at invocation)

- **`SKILL.md` soft cap**: Keep under **500 lines**. Move detailed reference material to separate files.
- **Post-compaction cap**: Invoked skill bodies are re-injected at **5,000 tokens per skill** and **25,000 tokens total**. The oldest invoked skills are dropped first.
- **Truncation keeps the start**: Put the most important instructions at the top of `SKILL.md` — if the body is truncated, the tail is lost.

### What survives compaction

| Mechanism | After compaction |
|-----------|------------------|
| System prompt + output style | Unchanged |
| Project-root CLAUDE.md, unscoped rules | Re-injected from disk |
| Auto memory | Re-injected from disk |
| Path-scoped rules (`paths:` frontmatter) | Lost until a matching file is read again |
| Nested CLAUDE.md in subdirectories | Lost until a file in that subdirectory is read again |
| Invoked skill bodies | Re-injected (subject to the caps above) |
| Hooks | Not applicable — hooks run as code, not context |

**Design implication:** If your plugin ships a rule that must persist across compaction, do **not** use `paths:` frontmatter. Either drop the scope or move it into the project-root CLAUDE.md.

**Frame every addition as**: "Only add context Claude doesn't already have. Challenge each piece: Does Claude really need this?"

## Challenge Every Token

Before including content, apply **the no-op test**: does this line change what the model does versus what it would do without it? If no, delete it — you're paying context for nothing. The test is model-relative (a no-op for Opus may not be one for Haiku) and is settled by running the skill, not by debating whether the line "seems useful."

The test covers two kinds of redundancy:

- **Knowledge redundancy** — the line restates something the model already knows (an API's shape, a well-known convention). This is the original framing of point 1 below.
- **Behavioral redundancy** — the line asks for something the model would already do by default (e.g. "read the file before editing it"). Same test, harder to spot: it's easy to notice a restated fact, easy to miss an instruction that changes nothing about the actual process.

Concrete checks that fall out of the test:

1. **Does Claude already know this?** → Remove if yes
2. **Can I reference instead of reproduce?** → Reference if possible
3. **Is this decision-focused or tutorial-focused?** → Keep only decisions
4. **Is one example enough?** → Remove extras
5. **Does this justify its token cost?** → Run the no-op test; remove if it fails

## Lean Documentation

Documentation must reflect the current state of the system, not its history.

### Principles

- **Replace, don't append**: When content is superseded, remove the old version entirely. Do not keep both old and new alongside each other.
- **Delete irrelevant content**: Every doc edit is an opportunity to prune. If surrounding content no longer applies, remove it during the same edit.
- **Current state only**: Document what the system does now. No historical narratives about how it evolved, no version migration stories, no changelogs embedded in reference docs.
- **No "Previously..." or "In v1.x..." language**: If a reader needs history, that belongs in git history or a dedicated changelog file, not in reference documentation.

### Applying Lean Documentation

| Situation | Action |
|-----------|--------|
| New version replaces old behavior | Rewrite the section to describe current behavior only |
| Feature removed | Delete the section entirely |
| Two docs describe the same thing differently | Pick the correct one, delete the other |
| Doc mentions old versions for context | Remove version references, describe current state |
| Section is half-outdated | Rewrite fully or delete, never leave partial truths |

### Why This Matters

Stale documentation is worse than no documentation. It teaches Claude wrong patterns, wastes context tokens on irrelevant history, and creates confusion about what is actually true. Keeping docs lean and current is not just style preference; it directly impacts Claude's ability to help effectively.

## Env Vars Relevant to Plugin Authors

A small set of environment variables affects how plugin code runs and how authors share repro logs. Most env-var documentation is end-user concerns; these four are worth knowing as a plugin author:

| Variable | What it does | Why a plugin author cares |
|----------|--------------|---------------------------|
| `CLAUDE_CODE_HIDE_CWD` | Masks the working directory in UI output and screenshots | Set this before capturing logs/screenshots for tickets — prevents customer or internal-product paths from leaking. |
| `DISABLE_UPDATES` | Blocks **all** Claude Code update paths, including manual `claude update` | Stricter than `DISABLE_AUTOUPDATER`. If your plugin's docs assume a specific Claude Code version, suggest `DISABLE_AUTOUPDATER` (lets users still update manually) rather than `DISABLE_UPDATES`. |
| `DISABLE_AUTOUPDATER` | Disables automatic background updates only. `claude update` still works | Pair with `FORCE_AUTOUPDATE_PLUGINS=true` to keep plugins current while pinning Claude Code. |
| `CLAUDE_CODE_FORK_SUBAGENT` | Opt in to the experimental forked-subagents feature (v2.1.117+) | Changes how `general-purpose` subagent spawns work and forces every spawn to background. If your plugin spawns the general-purpose subagent or relies on synchronous spawning, document that fork mode changes those guarantees. |

Other env vars (terminal config, OTEL, voice, etc.) are end-user concerns and don't belong in plugin-author documentation.

## Summary

The core philosophy is: **Minimum viable context for maximum effectiveness**.

Skills succeed when they provide only what Claude needs, exactly when Claude needs it, in the most token-efficient form possible — in service of the goal stated at the top: the same process, run after run.
