# Description Patterns by Skill Type

The description field is the most critical part of a skill - it determines whether Claude loads your skill.

## The Formula

Two valid structures (per Anthropic's official guide):

**Pattern A — Trigger-first** (best for technique/discipline skills):
```
Use when [specific triggers/symptoms] - [what it does, third person]
```

**Pattern B — Three-part** (best for toolkit/reference skills):
```
[What it does] + [When to use it] + [Key capabilities]
```

Both patterns must answer: "Should Claude load this skill right now?"

## Templates by Type

### Technique Skill
For skills that teach a method or approach.

```
Use when [symptom] or [situation] - [action verb] [problem] by [technique], providing [benefit]
```

**Example:**
> Use when tests have race conditions, timing dependencies, or inconsistent pass/fail behavior - replaces arbitrary timeouts with condition polling to eliminate flaky tests from timing guesses

### Reference Skill
For skills that provide documentation or lookup information.

```
Comprehensive [topic] with support for [features]. Use when Claude needs [task] for: (1) [Use case], (2) [Use case], (3) [Use case]
```

**Example:**
> Comprehensive document creation, editing, and analysis with support for tracked changes, comments, formatting preservation. Use when Claude needs to work with .docx files for: (1) Creating documents, (2) Editing content, (3) Working with tracked changes

### Discipline Skill
For skills that enforce process or prevent mistakes.

```
Use when [trigger situation] - requires [action] before [completing action]. [Key constraint or rule]
```

**Example:**
> Use when about to claim work is complete, fixed, or passing - requires running verification commands and confirming output before making success claims. Evidence before assertions, always.

### Toolkit Skill
For skills that provide utilities and tools.

```
[What it does] with [key features]. Use when [specific request pattern] like "[example user request]"
```

**Example:**
> Knowledge and utilities for creating animated GIFs optimized for Slack. Use when users request animated GIFs for Slack like "make me a GIF of X doing Y for Slack"

### Negative Triggers (Scope Boundaries)

For skills that may overtrigger, add explicit exclusions in the description itself:

```
description: Advanced data analysis for CSV files. Use for statistical
modeling, regression, clustering. Do NOT use for simple data exploration
(use data-viz skill instead).
```

```
description: PayFlow payment processing for e-commerce. Use specifically
for online payment workflows, not for general financial queries.
```

## Pushy Descriptions

Claude tends to undertrigger skills — it errs on the side of NOT loading a skill when unsure. Combat this by making descriptions slightly "pushy" with more trigger phrases and explicit keywords.

Key insight from Anthropic: **"If Claude isn't triggering your skill enough, make the description pushier."**

### Before/After Example

**BEFORE** (too conservative):
```
Use when creating new skills, editing existing skills
```

**AFTER** (pushy, with broad trigger coverage):
```
Use when creating new skills, editing existing skills, or verifying skills work before deployment. Make sure to use this skill whenever the user mentions skills, SKILL.md, skill authoring, plugin components, or wants to package any reusable behavior, even if they don't explicitly say "skill"
```

The "after" version explicitly tells Claude to trigger in edge cases and includes keywords the user might use without directly requesting the skill.

### Context Budget Awareness

Pushy descriptions must be balanced against the context budget. Skill descriptions consume part of the context window:

- **Dynamic budget**: 1% of context window across all skill descriptions combined, with an **8,000-character fallback**
- **Per-entry cap**: Each skill's `description` + `when_to_use` combined is truncated at **1,536 characters** in the skill listing, regardless of budget
- **Truncation keeps the start**, so **front-load** the key use case — text at the end is first to go
- Override the global limit with `SLASH_COMMAND_TOOL_CHAR_BUDGET`

Run `/context` to check if skills are being excluded due to budget limits.

## Trigger Phrase Enumeration

Explicitly listing the user utterances that should trigger a skill measurably improves activation. Use the `Use when user says 'X', 'Y', 'Z'` pattern.

**Before** (implicit triggers, relies on Claude inferring):
```
description: Audit code quality and security across Drupal and Next.js projects.
```

**After** (explicit trigger enumeration):
```
description: "Run a full code quality and security audit across Drupal and
Next.js projects. Use when user says 'full audit', 'check everything', 'quality
report', 'is this production ready', 'pre-merge check', 'audit this plugin'."
```

The enumerated phrases are the literal utterances users have been observed to say. They don't have to exhaustively cover every phrasing — 3 to 6 phrases that span the common ways of asking are enough.

## Action Verbs + Artifacts

Describe what the skill **produces** or **does**, not the domain it relates to.

| Weak (domain-framed) | Strong (action + artifact) |
|----------------------|----------------------------|
| "for design system work" | "scaffolds SDC component directories, generates Twig templates, wires up UI Patterns" |
| "helps with plugin development" | "creates plugin scaffolding, generates SKILL.md files, configures hooks.json, validates structure before packaging" |
| "brand content creation" | "generates branded HTML pages, PDFs, and carousels from a brand-philosophy.md using design tokens" |

## Synonym Coverage

Users ask for the same thing in multiple ways. Cover adjacent terms:

- A skill that creates HTML pages should mention **"landing page"**, **"web page"**, **"website"**, and **"UI components"** — not just "HTML page"
- A skill that authors skills should mention **"skill"**, **"SKILL.md"**, **"skill authoring"**, **"plugin component"**
- A skill that works with a specific file format should mention both the extension and the common noun (**".docx"** + **"Word document"**)

## Quoted YAML Form

Wrap multi-sentence descriptions in `"..."` to avoid YAML parsing edge cases on colons and commas:

```yaml
# Unquoted — safe but risky if the string contains a `:` or a leading special char
description: Run a full audit. Use when user says 'audit'.

# Quoted — always parses correctly
description: "Run a full audit. Use when user says 'audit', 'check everything'."
```

Both forms are valid. Quoted is safer as descriptions grow.

## Don't Let Scoring Tools Strip Intent

Automated "description quality" scoring tools sometimes flag intentional activation-strength modifiers as noise. **Preserve these when they're deliberate:**

- **`PROACTIVELY`, `MUST`, `NEVER`** — activation-strength modifiers. A scoring tool that strips `MUST use this skill before design work` to a milder phrasing has **reduced** accuracy, not improved it. If CLAUDE.md says a skill must fire before a class of task, the description should say so — even when a linter calls it "pushy".
- **`` !`command` `` dynamic-context injections** — these are a documented Claude Code skill feature that executes the command and injects its output into the description. A "simplifier" that deletes `!`... `` treats real functionality as syntax noise.
- **Domain-intelligence body prose** — creative/design/artistic skills encode quality bars in prose (art movements, craftsmanship mantras, anti-convergence rules). Generic "verbose = bad" scoring degrades output quality for these skills. The length is doing work.

If you review a description and the change is "shorter and milder" without a clear reason, check whether the skill relied on that exact phrasing.

## Checklist

- [ ] Starts with "Use when..." or action-focused opener, OR uses three-part structure
- [ ] Written in third person (not "you should")
- [ ] Includes specific symptoms/triggers
- [ ] Includes enumerated trigger phrases (`Use when user says 'X', 'Y', 'Z'`) where activation needs a boost
- [ ] Uses concrete action verbs describing what the skill produces
- [ ] Covers synonyms for the core concept
- [ ] Quoted YAML form for multi-sentence descriptions
- [ ] Combined description + `when_to_use` under **1,536 characters** (per-entry cap)
- [ ] Answers: "Should Claude load this skill right now?"
- [ ] Includes scope boundaries / negative triggers if skill could overtrigger
- [ ] Mentions file types if relevant (.pdf, .docx, etc.)
- [ ] Preserves `PROACTIVELY` / `MUST` / `NEVER` when deliberately present
- [ ] Preserves `` !`command` `` injections when deliberately present

## Keywords to Include

### Error Messages
Include specific error text Claude might encounter:
- "ENOTEMPTY", "timeout", "race condition"

### Symptoms
Describe observable behaviors:
- "flaky", "hanging", "inconsistent", "slow"

### Tools/Technologies
Name specific technologies:
- ".docx", "PDF", "React", "BigQuery"

### Synonyms
Cover alternative phrasings:
- "timeout/hang/freeze", "cleanup/teardown"
