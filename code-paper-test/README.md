# Paper Test

Systematically test code, skills, commands, and configs through mental execution — trace logic line-by-line with concrete values to find bugs, logic errors, missing code, edge cases, AI hallucinations, and contract violations before deployment.

## What is Paper Testing?

Paper testing is the practice of mentally executing code with concrete test cases to find issues before running it. Unlike code review (which focuses on style and patterns), paper testing **actually runs** the code in your head with real values to catch:

1. **Bugs** - Logic errors, null access, off-by-one errors
2. **Missing code** - Edge cases not handled, error paths missing
3. **Contract violations** - Mismatched interfaces, missing abstract methods
4. **Dependency issues** - Wrong method names, incorrect return types
5. **AI hallucinations** - Invented methods, mixed API versions, wrong assumptions

### Beyond Code: Testing Skills and Configs

Paper testing extends naturally to non-code artifacts. When you "paper test" a skill, you trace **instructions through Claude** instead of code through a CPU:

- **Skills/Commands** — Will Claude invoke this? Does it follow all steps? Do tool references exist?
- **Agent configs** — Are spawn parameters correct? Do agents coordinate without conflicts?
- **Config files** — Do YAML/JSON values match what code expects? Are required keys present?

See `references/skill-and-config-testing.md` for the full methodology.

## Why Paper Testing Now? The AI-Enabled Renaissance

### Classic Era → Decline → Revival

**Paper testing was effective** for simple algorithms and procedural code, but **became impractical** with:
- External libraries (thousands of dependencies)
- OOP complexity (inheritance, polymorphism, DI)
- Framework magic (annotations, auto-wiring)
- Modern scale (millions of lines)

**AI changes everything** in 2025. What was impossible for humans is trivial for AI:

- **Verify external dependencies instantly** - Check if methods exist, signatures match, return types correct
- **Navigate OOP complexity** - Trace inheritance chains, verify interfaces, validate DI
- **Detect AI-generated bugs** - Spot hallucinated methods, mixed API versions, wrong assumptions
- **Mental execution at scale** - Follow state through complex object graphs and middleware chains

### The Problem: AI Code Generation

With AI generating 30-60% of modern code:

- **AI hallucinates methods** that sound right but don't exist (`$entity->getFieldValue()` → doesn't exist)
- **Mixes API versions** (Drupal 7 patterns in D10 code)
- **Guesses signatures** (parameter order, return types)
- **Assumes behavior** without verification

**Traditional testing can't catch these early:**
- Unit tests only run if code compiles
- Integration tests miss logical errors
- Static analysis doesn't verify external dependencies

**AI-powered paper testing catches them before deployment:**
- Verifies every external call exists
- Checks actual method signatures
- Traces logic with concrete values
- Validates code contracts

## Installation

```bash
claude plugins add camoa-skills/code-paper-test
```

## When to Use

The skill is automatically invoked when you ask questions like:

- "Paper test this code" / "Trace this code" / "Test without running"
- "Find bugs in this code" / "Check for edge cases"
- "Validate this implementation" / "Review this logic"
- "Paper test this skill" / "Test this command" / "Validate this agent"
- "Check this config" / "Verify this YAML"

Or use it explicitly:

- Before deploying changes
- Debugging without a debugger
- Reviewing unfamiliar or AI-generated code
- Reviewing skills, commands, agents, or plugin configs
- Validating complex logic (loops, conditionals, recursion)

### Competing Testers (Agent Team)

For complex or security-critical code, use the agent team command:

```
/code-paper:test-team src/Service/PaymentService.php
```

Spawns 3 competing testers — Happy Path Validator, Edge Case Hunter, and Red Team Attacker — who independently analyze the code in isolated worktrees and then debate findings. Each tester has a 15-turn limit for cost control.

Also works with skills and configs:

```
/code-paper:test-team skills/paper-test/SKILL.md
```

Auto-detects skill files and switches to instruction tracing mode.

## How It Works

The skill guides you through a systematic workflow:

### 1. Define Test Scenarios

Pick concrete input values — happy path, edge cases, error cases.

### 2. Trace Line by Line

Follow each line, writing variable state after execution.

### 2b. Track Data Flow

At function boundaries, track type transformations and coercions.

### 3. Verify External Dependencies

For every external call, verify:
- Method actually exists
- Parameters are correct
- Return type matches usage
- Error cases handled
- Config values match expectations

### 4. Verify Code Contracts

For classes with relationships (extends, implements, uses, injects):
- Check all abstract methods implemented
- Verify interface signatures match
- Confirm parent constructors called
- Validate service dependencies exist

### 5. Document Flaws

Report bugs found with line numbers, severity scores, and fixes.

### 6. Analyze Untested Paths

Identify code paths that were never exercised and assess risk.

## Features

### Progressive Disclosure

The main SKILL.md provides the workflow. Detailed guides in `references/`:

| Guide | Purpose |
|-------|---------|
| **core-method.md** | Complete paper testing methodology |
| **dependency-verification.md** | How to verify external calls |
| **contract-patterns.md** | All code contract verification patterns (8 types) |
| **ai-code-auditing.md** | Specific checks for AI-generated code |
| **hybrid-testing.md** | Module-level testing strategy |
| **common-flaws.md** | Catalog of frequent bugs |
| **advanced-techniques.md** | Progressive injects, red team, attack surface, scenario workflows, state machine validation, AAR format |
| **severity-scoring.md** | Consistent severity rubric for flaw prioritization |
| **blind-ab-comparison.md** | Comparing two implementations side by side |
| **rubric-scoring.md** | Structured grading for code quality assessment |
| **skill-and-config-testing.md** | Testing skills, commands, agents, and configs |

### Contract Pattern Coverage

Comprehensive verification templates for:

1. **Inheritance** - Abstract methods, parent calls
2. **Plugin Systems** - Annotations, base classes, configuration
3. **Dependency Injection** - Service existence, interfaces
4. **Interface Implementation** - All methods, correct signatures
5. **Traits** - Requirements, conflicts, abstract methods
6. **Event/Hook Systems** - Signatures, return expectations
7. **Middleware/Decorators** - Chain calls, request/response handling
8. **Service Collectors** - Tagged services, priorities, interfaces

### Hybrid Testing Strategy

For modules with multiple components:

- **Flow-based testing** - Real user workflows end-to-end
- **Component testing** - Each component with edge cases
- **Coverage-driven** - Every component in at least one flow + edge cases

### Skill/Config Testing

For non-code artifacts:

- **Trigger analysis** — Will Claude invoke this skill? Test multiple phrasings
- **Instruction tracing** — Follow steps through Claude's execution
- **Frontmatter verification** — All fields present and consistent?
- **Context budget** — Does the skill fit in the context window?
- **Instruction fidelity** — Will Claude follow all steps or drift?
- **Agent team coordination** — Do spawned agents conflict?

## Example

```php
function getDiscount($total, $coupon) {
  if ($coupon == 'SAVE10') {
    $discount = $total * 0.10;
  }
  if ($coupon == 'SAVE20') {
    $discount = $total * 0.20;
  }
  return $discount;
}
```

Paper test reveals:

```
SCENARIO: No coupon provided
INPUT: $total = 100, $coupon = null

TRACE:
Line 2: if ($coupon == 'SAVE10')
        → null == 'SAVE10' = false
        → SKIP

Line 5: if ($coupon == 'SAVE20')
        → null == 'SAVE20' = false
        → SKIP

Line 8: return $discount
        → $discount is UNDEFINED

FLAW FOUND:
  Line 8: Returns undefined variable when no coupon matches
  Severity: HIGH (Reach: 2, Impact: 2, Reversibility: 1, Exploitability: 2 = 7)
  FIX: Initialize $discount = 0 at start of function
```

## AI Code Auditing

Specific checks for AI-generated code:

- **Method existence** - AI often invents plausible method names
- **API version mixing** - AI may use old API patterns
- **Return type assumptions** - AI assumes convenient returns
- **Parameter order** - AI may guess wrong order

## Benefits

- **Find bugs before deployment** - Catch issues in development
- **No test setup required** - Pure mental execution
- **Works on any code** - Legacy, new, AI-generated
- **Works on skills and configs** - Test Claude instructions, not just code
- **Catches contract violations** - Verifies all relationships
- **Consistent severity scoring** - Prioritize fixes objectively
- **Fast** - Paper test in minutes vs hours of debugging

## Version

**0.4.0** (Current) - Methodology depth + skill/config testing + infrastructure
- 6 new methodology steps: data flow tracking, error propagation, config validation, performance patterns, untested path analysis, state machine validation
- 4 new reference guides: severity scoring, blind A/B comparison, rubric scoring, skill/config testing
- Skill/config testing: trace instructions through Claude, not just code
- Agent team: `maxTurns: 15`, `isolation: worktree`, removed experimental flag
- Pushy descriptions with comprehensive trigger phrases

**0.3.0** - Competing Testers agent team command

**0.2.0** - Plugin conventions and model routing

## License

MIT

## Author

camoa

## Repository

https://github.com/camoa/claude-skills
