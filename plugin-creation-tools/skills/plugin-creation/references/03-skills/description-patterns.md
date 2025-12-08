# Description Patterns by Skill Type

The description field is the most critical part of a skill - it determines whether Claude loads your skill.

## The Formula

```
Use when [specific triggers/symptoms] - [what it does, third person]
```

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

## Checklist

- [ ] Starts with "Use when..." or action-focused opener
- [ ] Written in third person (not "you should")
- [ ] Includes specific symptoms/triggers
- [ ] Includes relevant keywords users might search
- [ ] Under 1024 characters (ideal: 200-500)
- [ ] Answers: "Should Claude load this skill right now?"

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
