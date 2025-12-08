# Decision Frameworks

Complete decision trees for skill creation choices.

## Should I Create a Skill?

```
Have you done this task 5+ times?
├─ NO → Don't create skill yet
└─ YES → Will you do it 10+ more times?
    ├─ NO → Consider slash command instead
    └─ YES → Create a skill
```

## What Type of Skill?

```
What's the primary purpose?

├─ Teach a technique/workflow?
│  └─ TECHNIQUE SKILL
│     Focus: How-to guidance, examples
│     Example: TDD workflow, debugging methodology
│
├─ Enforce discipline/process?
│  └─ DISCIPLINE SKILL
│     Focus: Rules, rationalization counters
│     Example: Verification before completion
│
├─ Provide reference information?
│  └─ REFERENCE SKILL
│     Focus: Searchable documentation
│     Example: API reference, schema docs
│
└─ Provide tools/utilities?
   └─ TOOLKIT SKILL
      Focus: Scripts, integrations
      Example: PDF processing, doc creation
```

## Where Should Content Live?

```
Is this information...

├─ Core workflow Claude must know?
│  └─ SKILL.md body
│
├─ Detailed reference (>100 lines)?
│  └─ references/{topic}.md
│
├─ Reusable code?
│  └─ scripts/{name}.py
│
├─ Template/boilerplate?
│  └─ assets/{name}/
│
└─ Non-essential?
   └─ REMOVE IT
```

## Which Creation Approach?

```
What's your source material?

├─ Personal/team expertise?
│  └─ MANUAL (this skill or Anthropic skill-creator)
│
├─ Large external documentation?
│  ├─ Time-constrained?
│  │  └─ AUTOMATED (Skill Seeker MCP)
│  └─ Quality-critical?
│     └─ HYBRID (Scrape + Refine manually)
│
└─ Creating autonomous agent?
   └─ META-SKILL (agent-skill-creator)
```

## Skill vs Alternative?

```
What do you need?

├─ Claude should auto-detect and use?
│  └─ SKILL
│
├─ User must explicitly trigger?
│  └─ SLASH COMMAND
│
├─ External API/service integration?
│  └─ MCP SERVER
│
├─ Complex multi-step autonomous work?
│  └─ AGENT DEFINITION
│
├─ Always-on project context?
│  └─ CLAUDE.md
│
└─ None of these fit?
   └─ Reconsider if you need anything
```

## Component Selection

```
Is this content...

├─ Core workflow Claude must know?
│  └─ SKILL.md body
│
├─ Detailed reference loaded on demand?
│  └─ references/{topic}.md
│
├─ Reusable, tested code?
│  └─ scripts/{name}.py
│
├─ File used in output (template, image)?
│  └─ assets/{name}/
│
└─ None of the above?
   └─ DON'T INCLUDE IT
```

## Degrees of Freedom

```
How fragile is this task?

├─ Multiple valid approaches, context-dependent?
│  └─ HIGH FREEDOM
│     Use: Text-based instructions, heuristics
│     Example: "Use clear language, adapt to context"
│
├─ Preferred pattern exists, some variation OK?
│  └─ MEDIUM FREEDOM
│     Use: Pseudocode or scripts with parameters
│     Example: "Follow this template, customize as needed"
│
└─ Operations fragile, consistency critical?
   └─ LOW FREEDOM
      Use: Specific scripts, exact sequences
      Example: "Run exactly: python script.py --flag value"
```

## Include Code Example?

```
Need to show code?

├─ Pattern exists in codebase?
│  └─ Reference file path, don't copy
│
├─ Official docs have examples?
│  └─ Link to docs
│
├─ Pattern needs illustration?
│  └─ Brief snippet (5-15 lines) + file reference
│
├─ Full implementation needed?
│  └─ Put in scripts/, reference from SKILL.md
│
└─ No existing example?
   └─ Create minimal, tested example
```

## SKILL.md Too Long?

```
SKILL.md approaching 500 lines?

├─ Has detailed reference content?
│  └─ Move to references/{topic}.md
│     Link: "See references/topic.md for..."
│
├─ Has multiple domains/variants?
│  └─ Split by domain in references/
│     Example: references/aws.md, references/gcp.md
│
├─ Has conditional details?
│  └─ Keep brief overview, link to detail
│     Example: "For advanced: See references/advanced.md"
│
└─ Still too long?
   └─ Question if skill is too broad
      Consider splitting into multiple skills
```

## Testing Strategy?

```
What type of skill?

├─ Discipline-enforcing?
│  └─ Test under pressure
│     - Time pressure
│     - Sunk cost pressure
│     - Authority pressure
│     Success: Follows rule under max pressure
│
├─ Technique skill?
│  └─ Test application
│     - Normal scenarios
│     - Edge cases
│     - Missing information
│     Success: Applies technique correctly
│
└─ Reference skill?
   └─ Test retrieval
      - Can find information?
      - Can apply it correctly?
      - Any gaps in coverage?
      Success: Finds and uses info correctly
```
