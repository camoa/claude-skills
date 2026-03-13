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

- **Budget**: 2% of context window, with a 16,000-character fallback
- Long descriptions eat into this budget and can cause other skills to be excluded
- Balance pushiness with brevity — add trigger phrases, but don't pad with filler

Run `/context` to check if skills are being excluded due to budget limits. Override the budget with the `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable if needed.

## Checklist

- [ ] Starts with "Use when..." or action-focused opener, OR uses three-part structure
- [ ] Written in third person (not "you should")
- [ ] Includes specific symptoms/triggers
- [ ] Includes relevant keywords users might search
- [ ] Under 1024 characters (ideal: 200-500)
- [ ] Answers: "Should Claude load this skill right now?"
- [ ] Includes scope boundaries / negative triggers if skill could overtrigger
- [ ] Mentions file types if relevant (.pdf, .docx, etc.)

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
