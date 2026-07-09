# Writing Effective SKILL.md

Detailed guidance on voice, style, structure, and word count for SKILL.md files.

## The Critical Distinction

**SKILL.md files are INSTRUCTIONS for Claude, not documentation about the skill.**

This is the most common mistake. When Claude reads a SKILL.md, it needs to know what to DO, not what the skill IS.

| Documentation (WRONG) | Instructions (CORRECT) |
|----------------------|------------------------|
| "This skill processes PDFs" | "Process PDFs using this workflow" |
| "Skills extend Claude's capabilities" | "When triggered, follow these steps" |
| "The form filling feature supports..." | "To fill forms, run scripts/fill_form.py" |
| "What Are Skills?" | "## Workflow" |
| "Guide for creating skills" | "Follow this workflow to create a skill" |

**Test your SKILL.md**: Read each sentence and ask "Does this tell Claude what to DO?" If it explains what something IS, rewrite it.

## Voice and Style

| Do | Don't |
|----|-------|
| "To create a document, use..." | "You should create a document by..." |
| "Extract text with pdfplumber" | "If you need to extract text, you can..." |
| Third person descriptions | First/second person instructions |
| Imperative/infinitive form | Narrative storytelling |

### Examples

**Good (imperative, third person):**
```markdown
## Creating Documents
To create a new document, initialize a Document object and add paragraphs.
Run scripts/create_doc.py for templated creation.
```

**Bad (second person, narrative):**
```markdown
## Creating Documents
When you want to create a document, you should first think about what you need.
If you're making a report, you might want to start with a template...
```

### Negation in the Body

A prohibition — "do NOT do X" — activates the concept of X in the model's attention at least as much as it suppresses it: the sentence puts X in front of the model, half-priming the very behavior the ban was meant to prevent. State the **positive target** instead — what Claude should do, not what it shouldn't.

| Avoid (negation) | Prefer (positive target) |
|---|---|
| "Do NOT write directly to the output file." | "Write to a temp file, then rename into place." |
| "Don't guess the schema." | "Read the schema file before generating queries." |
| "Never skip the validation step." | "Run validation as the last step before returning." |

Reserve a bare "don't" for a **guardrail paired with the positive** — a short warning appended after the instruction already states what to do, not standing alone as the only guidance:

```markdown
Write to a temp file, then rename into place. Don't write directly to the
target path — a partial write on failure corrupts it.
```

**This is a body-instructions rule, distinct from description negation.** The `description:` field uses negation deliberately and correctly for scope boundaries — "NOT for simple data exploration" tells Claude *when not to load the skill at all* (see `description-patterns.md` § Negative Triggers). That's a routing decision made once, before task execution starts. Negation-as-smell applies to the **body** — the instructions Claude executes turn-by-turn — where the prohibited concept re-enters active attention every time the model reads the line. Descriptions: negation is a legitimate tool. Bodies: state the positive target.

## Recommended Structure

```markdown
---
name: skill-name
description: Use when [triggers] - [what it does]
---

# Skill Name

## Overview
[1-2 sentence purpose statement]

## When to Use
- [Specific trigger 1]
- [Specific trigger 2]
- NOT for: [anti-patterns]

## Core Pattern
[Essential technique or workflow]

## Quick Reference
| Operation | Command/Code |
|-----------|--------------|
| ... | ... |

## Implementation
[Step-by-step with examples]

## Troubleshooting
| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| ... | ... | ... |

## See Also
- references/detailed-guide.md
- scripts/helper.py
```

> Section name follows the upstream Claude Code Skills guide, which uses `## Troubleshooting` (linked externally as the canonical anchor). Earlier templates used `## Common Mistakes`; that label only appears upstream as inline `**Common mistake**:` callouts inside Note blocks, never as a top-level section header.

## Word Count Targets

| Skill Type | Target | When |
|------------|--------|------|
| Getting-started | <150 words | Loads every conversation |
| Frequently-loaded | <200 words | Used often |
| Standard skills | <500 words | Normal usage |
| Complex reference | <5000 words | Use progressive disclosure |

### Why These Limits?

- **<150 words**: Skills that load in every conversation (like `using-superpowers`) must be minimal
- **<200 words**: Frequently triggered skills should minimize context impact
- **<500 words**: Standard skills balance completeness with efficiency
- **<5000 words**: Complex skills MUST use progressive disclosure (references/)

## Line Count Target

**Target SKILL.md under 250 lines; treat 500 as a hard ceiling.** The validator warns at ≥ 250 lines and errors at ≥ 500. Mature skills legitimately reach 250–400 lines — the warn is a nudge to consider extraction, not a defect. If approaching 500:
1. Move detailed content to `references/`
2. Link from SKILL.md: "See references/topic.md for..."
3. Keep only essential workflow in SKILL.md

Every line of SKILL.md body is loaded into context when the skill is invoked — extraction to `references/` is the progressive-disclosure mechanism that keeps the invocation cost low.

## Frontmatter Requirements

```yaml
---
name: processing-pdfs
description: Extracts text and tables from PDF files, fills forms. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
model: sonnet
context: fork
---
```

| Field | Required | Constraints |
|-------|----------|-------------|
| `name` | Yes | Lowercase, numbers, hyphens only. Max 64 chars. No "anthropic" or "claude". |
| `description` | Yes | Must include WHAT and WHEN. Third person only. **Two caps apply:** the Claude Code runtime truncates the combined `description` + `when_to_use` text at `maxSkillDescriptionChars` (default **1,536**, configurable in settings); the agentskills.io portability standard recommends a stricter **~1,024**. Target 1,024 for portable skills; 1,536 is the hard runtime limit past which text is silently dropped from the listing Claude sees. |
| `model` | No | Model to use when this skill is active. Values: `inherit`, `opus`, `sonnet`, `haiku` (same values as `/model`). **An inline current-turn override with no context isolation** — the override applies for the rest of the current turn, runs in the live conversation, and the session model resumes on your next prompt. **Footgun:** a sub-1M pin (`sonnet`/`haiku` ≈ 200k) overflows when the skill activates from a larger conversation. `inherit` is the safe default; `opus` is safe (1M tier); `sonnet`/`haiku` is the footgun. See "Don't pin a skill below the session window" below. |
| `allowed-tools` | No | Grants permission for the listed tools while the skill is active (does not restrict — every tool remains callable, but listed tools skip the permission prompt). Syntax: `"Bash(python:*) Bash(npm:*) WebFetch"`. **Workspace-trust gating:** for skills checked into a project at `.claude/skills/`, `allowed-tools` only takes effect *after* the workspace trust dialog is accepted (same gate as permission rules in `.claude/settings.json`). Review project skills before trusting a repo — a hostile skill can grant itself broad tool access this way. Plugin-shipped skills are not subject to this gate (trust is established at install time). |
| `disallowed-tools` | No | **Kebab-case.** Tools removed from Claude's available pool while this skill is active. Use for autonomous skills that should never call certain tools (e.g. block `AskUserQuestion` in a background loop). Accepts a space- or comma-separated string, or a YAML list. The restriction clears when you send your next message. **Do not confuse with the agent field:** agents use the camelCase `disallowedTools`. The camelCase form on a skill is silently ignored (validator rule **S15** flags it); the kebab form on an agent is silently ignored (rule **A04**). See `../05-agents/agent-tools.md` § The disallowedTools Field. |
| `context` | No | Set to `fork` to run skill in an isolated context (own context window). Use for heavy operations that would pollute the main context. |
| `agent` | No | When `context: fork`, specify agent type for the forked context. |
| `disable-model-invocation` | No | Set to `true` to prevent Claude from auto-invoking. User must call explicitly via `/name`. Reduces context cost to zero for triggered-only skills. |
| `user-invocable` | No | Set to `false` to hide from `/` menu. Claude can still invoke via Skill tool. For background knowledge users shouldn't invoke directly. Default is `true`. |
| `license` | No | License for the skill (e.g., MIT, Apache-2.0). |
| `compatibility` | No | Environment requirements (1-500 chars). Intended product, required system packages, network access needs. Example: `"Requires Python 3.10+, Claude Code only"` |
| `metadata` | No | Custom key-value pairs. Suggested keys: `author`, `version`, `mcp-server`, `category`, `tags`, `documentation`, `support`. |
| `hooks` | No | Skill-scoped lifecycle hooks. These hooks are active only while the skill is running and are automatically cleaned up when the skill finishes. Uses the same hook format as plugin hooks. |
| `argument-hint` | No | Hint shown during autocomplete to indicate expected arguments. Example: `argument-hint: "[issue-number]"` shows `/skill-name [issue-number]` in the autocomplete menu. |
| `effort` | No | Sets the reasoning effort level for the skill. Values: `low`, `medium`, `high`. Default: inherits from session. |

### Don't pin a skill below the session window

A skill's `model:` is an **inline, current-turn override with no context isolation** — the skill runs in the *live conversation* on the pinned model (Skills guide: *"the model to use when this skill is active… the override applies for the rest of the current turn"*). It is **not** a fresh subagent. So if you pin a model whose context window is smaller than a realistic session — `sonnet` or `haiku` (≈ 200k) — the skill **overflows the moment it activates from a conversation larger than that window**, producing an API context error until the user `/compact`s. This is a verified cross-plugin defect (BUG-1).

| Want | Do | Don't |
|------|----|----|
| Cheap model for heavy/mechanical work that needs only its input | Put the work in a **Task-dispatched agent** (`agents/<name>.md` with `model: haiku`/`sonnet`) — fresh, isolated context AND the cheap model | Pin the inline skill's `model:` to `sonnet`/`haiku` |
| A skill that needs the conversation context | `model: inherit` (runs on the 1M session model) | Pin a sub-1M model and hope the chat stays small |
| Deep reasoning in a skill | `model: opus` (1M tier — safe) | — |

**Rule of thumb:** `inherit` is the safe default; `opus` is safe (1M); `sonnet`/`haiku` is the footgun. Model pins on **agents** are exempt from this concern — agents always run in a fresh subagent context. The validator enforces this with rule **S14** (warns on a sub-1M skill pin; exempts agents and `opus`/`inherit`).

### Model Selection Guidelines

These apply to **agents** and to the safe skill values (`opus`, `inherit`) — not to inline sub-1M skill pins (see the section above):

| Model | Use When |
|-------|----------|
| `haiku` | Simple formatting, file listing, repetitive transforms, boilerplate — **in an agent**, not pinned on an inline skill |
| `sonnet` | Standard coding tasks — **in an agent**, not pinned on an inline skill |
| `opus` | Complex multi-step reasoning, architecture decisions, nuanced analysis — safe on a skill (1M tier) |
| `inherit` | The safe default for a skill that should run on whatever the session uses |

### Context and Invocation Examples

**Forked context** -- prevents heavy skill output from consuming main context:
```yaml
---
name: analyzing-codebase
description: Deep analysis of codebase architecture. Use when asked to audit or analyze overall code structure.
context: fork
agent: researcher
---
```

**Triggered-only skill** -- zero context cost until explicitly called:
```yaml
---
name: resetting-environment
description: Resets development environment to clean state.
disable-model-invocation: true
---
```

**Auto-only skill** -- hidden from `/` menu, Claude decides when to invoke:
```yaml
---
name: formatting-output
description: Formats command output for readability. Use when command output exceeds 50 lines.
user-invocable: false
---
```

> **Note:** `user-invocable: false` only controls `/` menu visibility. Claude can still invoke via the Skill tool. To block Claude from auto-invoking, use `disable-model-invocation: true` instead. These serve opposite purposes:
> - `user-invocable: false` — user cannot call, Claude can
> - `disable-model-invocation: true` — Claude cannot call, user can
>
> **Preload caveat:** A subagent with a `skills:` frontmatter list **cannot** preload a skill that sets `disable-model-invocation: true`. Preloading draws from the same set of skills Claude is allowed to invoke; a disabled-from-model skill is silently skipped (with a warning to the debug log). If you need a skill available to a specific subagent but not to the main session, use a different mechanism — don't combine `disable-model-invocation` with `skills:` preload.

### Naming Convention

**Prefer gerund form** (verb + -ing) for skill names:

| Good (Gerund) | Acceptable | Avoid |
|---------------|------------|-------|
| `processing-pdfs` | `pdf-processing` | `pdf-helper` |
| `analyzing-code` | `code-analyzer` | `utils` |
| `managing-git` | `git-manager` | `tools` |

Reserved words not allowed: `anthropic`, `claude`

## String Substitutions

Skill body text supports variable substitutions that are resolved at invocation time:

| Variable | Description |
|----------|-------------|
| `$ARGUMENTS` | Full argument string passed after the skill name |
| `$ARGUMENTS[N]` / `$N` | 0-based positional argument (e.g., `$ARGUMENTS[0]` or `$0` is the first argument) |
| `${CLAUDE_SKILL_DIR}` | Absolute path to the directory containing the SKILL.md file |
| `${CLAUDE_SESSION_ID}` | Current session ID |
| `${CLAUDE_EFFORT}` | Active [effort level](https://docs.anthropic.com/en/model-config#adjust-effort-level) for the current turn -- `low`, `medium`, `high`, `xhigh`, or `max`. Use it to adapt skill instructions to how much reasoning effort the user has dialed in (e.g. terser steps at `low`, fuller checklists at `high`+). Reflects the level the current model actually used (downgraded if requested effort exceeds support). |

Example usage in SKILL.md body:
```markdown
Look up issue $0 and summarize it.
Store results in ${CLAUDE_SKILL_DIR}/output/.
```

### Adaptive skills with `${CLAUDE_EFFORT}`

`${CLAUDE_EFFORT}` lets a skill scale its own thoroughness to the user's effort dial. Branch the instructions on the substituted value so a `low`-effort turn gets a terse path and a `high`/`max` turn gets the full checklist:

```markdown
## Review the change

The current effort level is `${CLAUDE_EFFORT}`.

- At **low** / **medium**: run the linter, report pass/fail, stop.
- At **high** / **xhigh** / **max**: run the linter, then trace each
  changed function for edge cases, check test coverage, and write a
  findings summary.

Match your depth to the effort level above — don't over-investigate a
`low` turn or under-investigate a `max` turn.
```

`${CLAUDE_EFFORT}` is substituted as a literal string before Claude reads the body, so the branch reads as plain instructions. Use it for skills where the right amount of work genuinely varies — audits, reviews, research. A skill whose work is fixed (format a file, rename a symbol) doesn't need it.

## Context Budget

Each skill consumes context when loaded. The budget defaults to **2% of the context window** with a **16,000-character fallback** if the window size is unknown. This includes the SKILL.md content and any dynamically injected output.

- Run `/context` to check current context usage and remaining budget
- Override the default budget with the `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable (value in characters)
- Keep skills concise to leave room for conversation context

## Where Skills Live & How They're Discovered

Skills load from several locations, and the discovery rules matter when you advise teams on layout:

| Source | Discovery |
|--------|-----------|
| **Plugin skills** (`skills/<name>/SKILL.md` in a plugin) | Loaded when the plugin is enabled. Plus the single-skill-at-root layout — root `SKILL.md`, no `skills/` subdir — auto-discovered (v2.1.142+). |
| **Project skills** (`.claude/skills/`) | Loaded from the starting directory **and every parent directory up to the repository root**. Starting Claude in a subdirectory still picks up skills defined at the repo root. |
| **Nested project skills** (`.claude/skills/` deeper in the tree) | Loaded **on demand**: when Claude works with a file under a subdirectory, it also discovers skills from that subdirectory's `.claude/skills/`. Editing `packages/frontend/file.ts` picks up `packages/frontend/.claude/skills/`. This is the monorepo pattern — each package ships its own skills. |
| **User skills** (`~/.claude/skills/`) | Available in every project. |

**Monorepo guidance**: in a monorepo, put repo-wide skills in the root `.claude/skills/` and package-specific skills in each package's `.claude/skills/`. The package skills only enter context when Claude touches that package's files, keeping the listing budget lean for unrelated work.

## Hot-Reload

Skills in directories added via `--add-dir` support **live change detection**. Edits to SKILL.md files in these directories are picked up automatically without restarting Claude Code. This is useful during skill development — edit, save, and invoke immediately.

## Dynamic Context Injection

Skill body text supports dynamic context injection using the exclamation mark prefix with backtick-wrapped commands. Lines using this syntax run the command at invocation time and inject the output into the skill context.

### Syntax

A line starting with exclamation mark followed by a backtick-wrapped command:
```
!`command here`
```

### Examples

Inject current git status when the skill loads:
```
!`git status`
```

Inject file contents at runtime:
```
!`cat .env.example`
```

Inject project structure:
```
!`ls -la src/`
```

### When to Use

- Skill needs awareness of current project state (git status, branch, changed files)
- Skill references configuration that varies per project
- Skill needs to adapt behavior based on runtime environment

### Guidelines

- Keep injected commands fast -- slow commands delay skill loading
- Avoid commands with large output; they consume context unnecessarily
- Use targeted commands (`git diff --stat` over `git diff`) to minimize output size

## Extended Thinking with Ultrathink

Skills can include the word "ultrathink" in their body text to encourage Claude to use extended thinking on complex tasks. This is particularly useful for skills that involve:

- Multi-step architectural reasoning
- Complex code refactoring decisions
- Weighing multiple trade-offs before acting
- Tasks where getting it right the first time matters

Place "ultrathink" in a natural instruction, such as:
```markdown
## Workflow
Before making changes, ultrathink about the implications across the codebase.
```

This signals Claude to engage deeper reasoning before responding, which improves quality on complex tasks at the cost of slightly longer response times.

## Section Guidelines

### Overview
- 1-2 sentences maximum
- State the purpose clearly
- No background or history

### When to Use
- Bullet list of specific triggers
- Include "NOT for:" anti-patterns
- Match the description field

### Core Pattern
- The essential technique or workflow
- Scannable format (bullets, tables)
- One excellent example if needed

### Quick Reference
- Table format preferred
- Most common operations only
- Commands, not explanations

### Implementation
- Step-by-step when needed
- Reference files, don't reproduce
- Brief examples (5-15 lines max)

### Troubleshooting
- Table format: Symptom | Likely Cause | Fix
- Real issues users actually hit, not hypothetical
- Brief, actionable fixes
- Match the upstream Skills-guide section name (`## Troubleshooting`) so users searching upstream docs find the same anchor in your skill

### See Also
- Link to references/ files
- Link to scripts/
- No external links unless critical

## Progressive Disclosure Patterns

### Pattern 1: Hub with References
```markdown
## PDF Processing

Quick start: `python scripts/process.py input.pdf`

For advanced features:
- **Form filling**: See references/forms.md
- **Merging**: See references/merge.md
- **OCR**: See references/ocr.md
```

### Pattern 2: Conditional Loading
```markdown
## Document Editing

For simple edits, modify content directly.

**For tracked changes**: See references/tracked-changes.md
**For complex formatting**: See references/formatting.md
```

### Pattern 3: Domain Organization
```
skill/
├── SKILL.md (overview + navigation)
└── references/
    ├── finance.md    # Load for finance questions
    ├── sales.md      # Load for sales questions
    └── support.md    # Load for support questions
```

## Reference File Guidelines

### Table of Contents for Long Files

For reference files longer than 100 lines, add a table of contents:

```markdown
# API Reference

## Contents
- Authentication and setup
- Core methods (create, read, update, delete)
- Advanced features (batch operations, webhooks)
- Error handling patterns
- Code examples

## Authentication and setup
...
```

### One Level Deep Only

**Avoid nested references.** All reference files should link directly from SKILL.md.

```
Bad (nested):
  SKILL.md → advanced.md → details.md → actual-info.md

Good (flat):
  SKILL.md → advanced.md
  SKILL.md → details.md
  SKILL.md → actual-info.md
```

### Avoid Time-Sensitive Information

Don't include dates or temporal references that will become outdated:

```markdown
# Bad
If you're doing this before August 2025, use the old API.

# Good
## Current method
Use the v2 API endpoint.

## Legacy patterns (deprecated)
<details>
<summary>v1 API (no longer supported)</summary>
...
</details>
```

## Testing Skills

### Test with Multiple Models

Skills behave differently across models. Test with:

| Model | Check For |
|-------|-----------|
| Claude Haiku | Does the skill provide enough guidance? |
| Claude Sonnet | Is the skill clear and efficient? |
| Claude Opus | Does the skill avoid over-explaining? |

### Create Evaluations

Build at least 3 test scenarios before finalizing:

```json
{
  "skills": ["pdf-processing"],
  "query": "Extract text from this PDF and save to output.txt",
  "files": ["test-files/document.pdf"],
  "expected_behavior": [
    "Reads the PDF using appropriate library",
    "Extracts text from all pages",
    "Saves to output.txt"
  ]
}
```

## Checklist Before Completion

### Core Quality
- [ ] Under 500 lines
- [ ] Imperative/third person voice
- [ ] Clear structure with headers
- [ ] One excellent example per pattern
- [ ] References linked, not duplicated
- [ ] No unnecessary content
- [ ] No time-sensitive information
- [ ] Consistent terminology throughout
- [ ] Current state only -- no historical narratives. Replace outdated content, don't keep it alongside new.

### Frontmatter
- [ ] Name uses gerund form (preferred)
- [ ] Name is lowercase, hyphens only
- [ ] Description is third person
- [ ] Description includes WHAT and WHEN
- [ ] Description under the 1,536-char runtime cap (`maxSkillDescriptionChars`); ~1,024 for agentskills.io portability

### References
- [ ] All references one level deep
- [ ] Files >100 lines have table of contents
- [ ] Progressive disclosure used appropriately

### Testing
- [ ] Tested with Haiku, Sonnet, Opus
- [ ] At least 3 evaluation scenarios
- [ ] Real usage scenarios tested
