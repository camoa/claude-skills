# Skill Patterns

Five common skill patterns identified in Anthropic's official guide. Choose the pattern that best fits your use case.

## Pattern 1: Sequential Workflow Orchestration

**Use when:** Users need multi-step processes in a specific order.

```markdown
## Workflow: [Process Name]

### Step 1: [First Action]
Call tool/script: `[tool_name]`
Parameters: [required inputs]

### Step 2: [Second Action]
Call tool/script: `[tool_name]`
Wait for: [dependency from Step 1]

### Step 3: [Third Action]
Call tool/script: `[tool_name]`
Parameters: [inputs from previous steps]
```

**Key techniques:**
- Explicit step ordering with numbered steps
- Dependencies between steps clearly stated
- Validation at each stage before proceeding
- Rollback instructions for failures

**Example:** Customer onboarding (create account → setup payment → create subscription → send welcome email).

## Pattern 2: Multi-MCP Coordination

**Use when:** Workflows span multiple services or MCP servers.

```markdown
## Phase 1: [Service A] (MCP: server-a)
1. [Action using server-a tools]
2. [Capture output for next phase]

## Phase 2: [Service B] (MCP: server-b)
1. [Action using server-b tools with Phase 1 data]
2. [Validate before proceeding]

## Phase 3: [Service C] (MCP: server-c)
1. [Final actions using server-c tools]
```

**Key techniques:**
- Clear phase separation by service
- Data passing between MCPs explicitly documented
- Validation before moving to next phase
- Centralized error handling

**Example:** Design-to-development handoff (Figma export → Drive upload → Linear task creation → Slack notification).

## Pattern 3: Iterative Refinement

**Use when:** Output quality improves with iteration.

```markdown
## Initial Draft
1. Gather data / generate first version
2. Save to temporary location

## Quality Check
1. Run validation: `scripts/check_quality.py`
2. Identify issues (missing sections, formatting, data errors)

## Refinement Loop
1. Address each identified issue
2. Regenerate affected sections
3. Re-validate
4. Repeat until quality threshold met

## Finalization
1. Apply final formatting
2. Generate summary
3. Save final version
```

**Key techniques:**
- Explicit quality criteria defined upfront
- Validation scripts for deterministic checks
- Clear stopping conditions (know when to stop iterating)
- Separate draft from final output

**Example:** Report generation, document review, code quality analysis.

## Pattern 4: Context-Aware Tool Selection

**Use when:** Same outcome requires different tools depending on context.

```markdown
## Decision Tree
1. Analyze input (file type, size, requirements)
2. Select approach:
   - [Condition A]: Use [tool/method A]
   - [Condition B]: Use [tool/method B]
   - [Condition C]: Use [tool/method C]
   - [Fallback]: Use [default method]

## Execute
Based on decision, run selected approach.

## Report Choice
Explain to user why that approach was selected.
```

**Key techniques:**
- Clear decision criteria (file size, type, collaborative needs)
- Fallback options for edge cases
- Transparency about choices made (explain why)

**Example:** Smart file storage (large files → cloud, collaborative docs → Notion, code → GitHub, temporary → local).

## Pattern 5: Domain-Specific Intelligence

**Use when:** Skill adds specialized knowledge beyond tool access.

```markdown
## Pre-Action Verification
1. Gather context via tools
2. Apply domain rules:
   - [Rule 1: check/verification]
   - [Rule 2: check/verification]
   - [Rule 3: check/verification]
3. Document verification decision

## Execute (if verified)
IF all checks pass:
  - Proceed with action
  - Apply domain-specific constraints
ELSE:
  - Flag for review
  - Create issue/case

## Audit Trail
- Log all checks performed
- Record decisions made
- Generate audit report
```

**Key techniques:**
- Domain expertise embedded in logic (compliance, security, financial rules)
- Verification before action (never skip checks)
- Comprehensive documentation and audit trail
- Clear governance (who reviews flagged items)

**Example:** Payment processing with compliance (sanctions check → jurisdiction verification → risk assessment → process or flag).

## Choosing a Pattern

| Pattern | Best For | Complexity |
|---------|----------|------------|
| Sequential Workflow | Ordered processes with dependencies | Low-Medium |
| Multi-MCP Coordination | Cross-service workflows | Medium-High |
| Iterative Refinement | Quality-driven output | Medium |
| Context-Aware Selection | Variable approaches to same goal | Medium |
| Domain-Specific Intelligence | Regulated or specialized domains | High |

Most skills use one primary pattern. Complex skills may combine patterns (e.g., Sequential + Domain-Specific for a compliance workflow).

## See Also

- `anthropic-skill-standards.md` - Official Anthropic standards
- `writing-skillmd.md` - SKILL.md structure guidance
- `creation-approaches.md` - Full creation workflow
