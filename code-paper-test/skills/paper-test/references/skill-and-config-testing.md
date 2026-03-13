# Testing Skills, Commands, Agents, and Configs

Extend paper testing to non-code artifacts by tracing instructions through Claude instead of code through a CPU.

## The Mapping

| Code Concept | Skill/Config Equivalent |
|-------------|------------------------|
| Input values | User message / `$ARGUMENTS` |
| Line-by-line trace | Step-by-step instruction following |
| Branch (if/else) | Conditional steps ("If no arguments...") |
| Method call | Tool call (Read, Grep, Write, Agent) |
| Return type | Output format (markdown, file, message) |
| Dependency verification | Does referenced tool/skill/file exist? |
| Contract verification | Does frontmatter match body? All required fields present? |
| Null access | Missing `$ARGUMENTS`, empty input |
| N+1 performance | Context budget — how much window does it consume? |
| Edge case | Ambiguous user message, tool call fails, no matches found |
| Error propagation | Step 3 fails — does step 4 handle it or crash? |
| Race condition | Parallel agent output conflicts |

---

## When to Use

- Reviewing a skill or command before publishing
- Validating a plugin before release
- Debugging why a skill doesn't trigger or produces wrong output
- Comparing two versions of a skill
- Auditing agent team coordination
- Verifying config files match what code expects

---

## 1. Trigger Analysis

Will Claude actually invoke this skill? Test with multiple phrasings.

```
TRIGGER TEST: [skill name]
Description: "[the skill's description field]"

Test phrases (would Claude match this skill?):
  "paper test this code"         → MATCH? [YES/NO/MAYBE]
  "find bugs in my service"      → MATCH? [YES/NO/MAYBE]
  "review this for issues"       → MATCH? [YES/NO/MAYBE]
  "audit the payment module"     → MATCH? [YES/NO/MAYBE]
  "trace the login flow"         → MATCH? [YES/NO/MAYBE]

Undertrigger risk:
  Phrases that SHOULD invoke but probably won't:
  - "[phrase]" — missing trigger word in description

Overtrigger risk:
  Phrases that would match but shouldn't:
  - "[phrase]" — description too broad, steals from other skills

Competing skills:
  - [other skill name] — could Claude choose this instead?
  - Resolution: [which should win and why]
```

### What Makes a Good Trigger

**Pushy descriptions include:**
- Multiple trigger phrases covering synonyms
- "Use when user says..." with concrete examples
- "Use proactively when..." for automatic activation
- "MUST" / "ALWAYS" for enforcement

**Red flags for undertriggering:**
- Description is a definition, not a trigger ("A tool that..." vs "Use when...")
- Only one trigger phrase
- No synonyms or alternate phrasings
- No proactive activation guidance

---

## 2. Instruction Tracing

Follow the skill's steps with a concrete scenario. Instead of tracing code with variable values, trace instructions with Claude's likely behavior.

```
SKILL TRACE: [skill name]
SCENARIO: User says "[concrete message]"
CONTEXT: [what's in the conversation, what files exist]

Step 1: [instruction text from skill]
  Claude would: [what Claude actually does]
  Tool calls:   [Read X, Grep Y, Write Z]
  Output:       [what's produced — text, file, message]
  Risk:         [what could go wrong]
    - Tool returns empty results → [does step handle this?]
    - File doesn't exist → [does step handle this?]

Step 2: [instruction text]
  Depends on: Step 1 output
  Claude would: [...]
  Risk: What if Step 1 produced empty/unexpected results?
    - Step 1 found no files → Step 2 tries to read non-existent file → ERROR

Step 3: [instruction text with conditional]
  Condition: "[if X then Y]"
  Evaluation: [X is true/false because...]
  TAKES: [which branch]
  Risk: Is the condition clear enough for Claude to evaluate?

FINAL OUTPUT:
  What user sees: [the actual response]
  Files created:  [list]
  Side effects:   [tool calls, writes, etc.]

FLAWS FOUND:
  - Step [N]: [issue — e.g., "no handling for empty grep results"]
    FIX: [add conditional: "If no matches found, tell user and suggest alternatives"]
  - Step [N]-[M]: [issue — e.g., "20-line instruction block, Claude will drift"]
    FIX: [break into smaller numbered steps]
```

---

## 3. Frontmatter Verification

Check that all frontmatter fields are present, correct, and consistent.

```
FRONTMATTER CHECK: [skill/command/agent name]

Required fields:
  - name:           [present?] [matches filename convention?]
  - description:    [present?] [includes trigger phrases?] [pushy enough?]
  - model:          [present?] [appropriate — sonnet for simple, opus for complex?]
  - allowed-tools:  [present?] [includes ALL tools the body references?]
  - user-invocable: [present if skill should be user-accessible?]
  - version:        [present?] [matches plugin.json version?]

Agent-specific:
  - maxTurns:       [present?] [reasonable limit?]
  - isolation:      [worktree if read-only or needs independence?]

Command-specific:
  - argument-hint:  [present if command takes arguments?]
  - context:        [fork if produces large output?]

BODY-FRONTMATTER CONSISTENCY:
  Tools used in body:     [list every tool name mentioned in instructions]
  Tools in allowed-tools: [list from frontmatter]
  Gap:                    [tools used but NOT in allowed-tools — FLAW]
  Extra:                  [tools in allowed-tools but never used — unnecessary]

  Skills/commands referenced in body: [list]
  Do they exist in the plugin?        [verify each — YES/NO]

  Files/paths referenced in body:     [list]
  Do they exist?                      [verify each — YES/NO]
```

---

## 4. Context Budget Analysis

Skills consume context window when loaded. Too much content = Claude forgets earlier conversation.

```
CONTEXT BUDGET: [skill name]

SKILL.md size:         [N] lines
Referenced guides:
  - [guide name]:      [N] lines
  - [guide name]:      [N] lines
Total if all loaded:   [N] lines (~[estimate]K tokens)

Budget guideline: Skills should be under 500 lines; reference guides extend via progressive disclosure.

Risk assessment:
  - If context is 20% full:  [fits comfortably / tight / won't fit]
  - If context is 50% full:  [fits / tight / won't fit]
  - If context is 80% full:  [fits / tight / won't fit — Claude may truncate]

Optimization:
  - Can any sections be moved to reference guides? [list candidates]
  - Are any reference guides loaded unnecessarily? [list]
  - Could the skill use `${CLAUDE_SKILL_DIR}` to load guides on demand?
```

---

## 5. Instruction Fidelity Testing

Will Claude follow ALL steps faithfully, or drift/skip/summarize?

```
FIDELITY CHECK: [skill name]

Total steps: [N]
Total instruction lines: [N]

Risk factors:
  Long steps (>20 lines):
    - Step [N]: [title] — [N] lines
      Risk: Claude may summarize rather than follow each sub-instruction
      Fix: Break into smaller numbered sub-steps

  Conditional steps:
    - Step [N]: "If [condition]..."
      Risk: Claude may skip evaluation and always take one branch
      Fix: Make condition explicit with examples of both outcomes

  Enforcement language:
    - Steps with MUST/NEVER/ALWAYS: [list]
      Assessment: [enforceable? or will Claude soften?]

  Late steps:
    - Steps [N]-[M] come after complex earlier steps
      Risk: By this point, Claude may have used significant context on earlier steps
      Fix: [add bold reminder, or front-load critical instructions]

  Repetition instructions ("for EACH item"):
    - Step [N]: "For each [X], do [Y]"
      Risk: Claude may do 2-3 of 10 items and summarize the rest
      Fix: Add "Do ALL items — do not skip or summarize any"
```

---

## 6. Agent/Team Command Testing

For commands that spawn agent teams.

```
AGENT TEAM TEST: [command name]

SPAWN CONFIGURATION:
  Agent 1: [name]
    Model:     [sonnet/opus]
    MaxTurns:  [N] — [reasonable?]
    Isolation: [worktree? — should they be independent?]
    Tools:     [scoped appropriately?]

  Agent 2: [name]
    [same fields]

COORDINATION CHECK:
  - Do agents write to same file?     → [YES = CONFLICT RISK / NO]
  - Task dependencies correct?        → [verify DAG: no cycles, all deps exist]
  - Quality gate:                      → [do agents validate completeness before done?]
  - What if an agent fails/times out?  → [handled? fallback?]

OUTPUT SYNTHESIS:
  - Lead reads files from: [list paths]
  - Agents write files to: [list paths]
  - Paths match?          [YES/NO — mismatch = lead can't find agent output]
  - Output format captures all findings? [YES/NO — anything lost in synthesis?]

SCENARIO TRACES:
  Trace 1: All agents complete successfully
    → Lead reads all files → synthesizes → report produced ✓

  Trace 2: Agent 2 times out (maxTurns exceeded)
    → Lead reads available files → [what happens? partial report? error?]

  Trace 3: Target is a skill file, not code
    → Agents recognize non-code target? → [switch to instruction tracing?]
```

---

## 7. Config File Testing

For YAML, JSON, services.yml, routing.yml, and other config files.

```
CONFIG TEST: [config file path]

TYPE: [YAML / JSON / .env / services.yml / routing.yml / schema.yml]

STRUCTURE CHECK:
  - Valid syntax?       [parse without errors]
  - Required keys present? [list required keys and check each]
  - Types correct?      [string where string expected, int where int expected]
  - No unused keys?     [keys present but never read by code — dead config]

CODE REFERENCE CHECK:
  For each key in the config:
    Key: [key name]
    Read by: [file:line where code reads this key]
    Used as: [type — string, int, bool, array]
    Matches? [config value type matches usage]

  For each config read in code:
    Code reads: [key name]
    Exists in config? [YES/NO]
    Default if missing: [value / none — RISK if none]

SERVICE DEFINITION CHECK (services.yml):
  Service: [service.id]
    Class: [fully qualified class name] → EXISTS? [YES/NO]
    Arguments:
      - [argument] → [type matches constructor parameter?]
    Tags: [tag names] → [collector exists for this tag?]

ROUTING CHECK (routing.yml):
  Route: [route.name]
    Path: [/path/{param}]
    Controller: [class::method] → EXISTS? [YES/NO]
    Requirements: [param constraints] → [validated in controller?]
```

---

## Quick Reference: Code vs Skill Testing

| What You're Testing | Trace Method | Key Checks |
|---------------------|-------------|------------|
| PHP/JS/Python function | Line-by-line with values | Dependencies, contracts, edge cases |
| SKILL.md | Step-by-step instructions | Triggers, fidelity, tools, context budget |
| Command .md | Step-by-step + agent spawns | Arguments, prerequisites, spawn configs |
| Agent .md | Frontmatter + body | maxTurns, isolation, description, enforcement |
| services.yml | Key-by-key | Class exists, arguments match constructor |
| routing.yml | Route-by-route | Controller exists, params validated |
| plugin.json | Field-by-field | Version consistency, keywords relevant |
| hooks.json | Event-by-event | Script exists, exit codes handled |

---

## Example: Paper Testing a Skill

```
SKILL TRACE: guide-integrator
SCENARIO: User starts Phase 2 design work, skill should activate proactively

Step 1: "Check current phase from task file"
  Claude would: Read the current task file to determine phase
  Tool calls: Glob for task files, Read the active task
  Output: Phase 2 detected
  Risk: No active task file → step fails silently

Step 2: "Load relevant guides for this phase"
  Claude would: Based on Phase 2, load architecture decision guides
  Tool calls: Read guide files from dev-guides path
  Output: SOLID, Library-First, DRY guides loaded
  Risk: Guide path doesn't exist → Read fails → no guides loaded
    Does step handle this? NO — needs fallback message

Step 3: "Skip if already loaded in this session"
  Condition: "guides already loaded earlier"
  Evaluation: How does Claude know? No session state tracking.
  Risk: Claude may reload guides every time (wastes context)
    OR Claude may skip when it shouldn't (false positive)
  Fix: Add explicit check: "Search conversation for 'Loaded guides:' message"

FRONTMATTER CHECK:
  allowed-tools: [not set] — FLAW: should be Read, Glob, Grep
  model: [not set] — acceptable (inherits from parent)

FIDELITY CHECK:
  "PROACTIVE: Activate at the START of every phase activity"
  — Enforceable? MAYBE — depends on Claude remembering across turns
  — Fix: Add to agent body prompt as bold reminder

FLAWS FOUND:
  1. No error handling if guide path doesn't exist
  2. No reliable way to detect "already loaded" state
  3. Missing allowed-tools in frontmatter
```
