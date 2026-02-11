# Anthropic Official Skill Standards

Distilled from "The Complete Guide to Building Skills for Claude" (Anthropic, Jan 2026).

Use this reference as the authoritative checklist when creating or validating skills. Cross-check every skill against these standards before packaging.

## File Structure

- `SKILL.md` (required, exact case) with YAML frontmatter
- `scripts/` (optional) - executable code
- `references/` (optional) - documentation loaded as needed
- `assets/` (optional) - templates, fonts, icons
- **No README.md** inside skill folder (repo-level README is fine for GitHub)

## Core Design Principles

1. **Progressive Disclosure (3 levels)**
   - Level 1: YAML frontmatter — always in system prompt, minimal info for when to trigger
   - Level 2: SKILL.md body — loaded when skill is relevant
   - Level 3: Linked files — Claude navigates as needed (references/, scripts/, assets/)

2. **Composability** — skills should work alongside others, not assume exclusivity

3. **Portability** — works across Claude.ai, Claude Code, and API without modification

## YAML Frontmatter Requirements

**Required fields:**
- `name`: kebab-case only, no spaces/capitals, should match folder name
- `description`: MUST include BOTH what it does AND when to use it (trigger conditions). Under 1024 chars. No XML tags.

**Optional fields:**
- `license`: e.g., MIT, Apache-2.0
- `compatibility`: 1-500 chars, environment requirements (intended product, system packages, network needs)
- `metadata`: custom key-value pairs (suggested: author, version, mcp-server, category, tags, documentation, support)
- `allowed-tools`: restrict tool access (e.g., `"Bash(python:*) Bash(npm:*) WebFetch"`)

**Forbidden:**
- XML angle brackets (< >) in frontmatter
- Skills with "claude" or "anthropic" in name
- Code execution in YAML

## Description Field

Structure: `[What it does] + [When to use it] + [Key capabilities]`

**Good examples:**
- "Analyzes Figma design files and generates developer handoff documentation. Use when user uploads .fig files, asks for 'design specs', 'component documentation', or 'design-to-code handoff'."
- "Manages Linear project workflows including sprint planning, task creation, and status tracking. Use when user mentions 'sprint', 'Linear tasks', 'project planning', or asks to 'create tickets'."
- "End-to-end customer onboarding workflow for PayFlow. Handles account creation, payment setup, and subscription management. Use when user says 'onboard new customer', 'set up subscription', or 'create PayFlow account'."

**Bad examples:**
- "Helps with projects." (too vague)
- "Creates sophisticated multi-page documentation systems." (missing triggers)
- "Implements the Project entity model with hierarchical relationships." (too technical, no triggers)

**Negative triggers** — for skills that overtrigger, add explicit scope boundaries:
```
description: Advanced data analysis for CSV files. Use for statistical
modeling, regression, clustering. Do NOT use for simple data exploration
(use data-viz skill instead).
```

## SKILL.md Body Structure

Recommended sections:
1. **Skill Name** (H1)
2. **Instructions** (H2) — step-by-step with clear actions, reference bundled resources
3. **Examples** (H2) — concrete user scenarios (User says → Actions → Result)
4. **Troubleshooting** (H2) — Error → Cause → Solution

### Best Practices for Instructions
- Be specific and actionable — include actual commands, validation steps
- Reference bundled resources clearly — `references/api-patterns.md`
- Use progressive disclosure — keep SKILL.md focused, move details to `references/`
- Include error handling — connection issues, auth failures, common mistakes
- Keep SKILL.md under 5,000 words — move detailed docs to references/

## Three Use Case Categories

Identify which category your skill falls into:

1. **Document & Asset Creation** — consistent, high-quality output (docs, presentations, designs, code)
   - Key techniques: embedded style guides, template structures, quality checklists
2. **Workflow Automation** — multi-step processes, consistent methodology
   - Key techniques: step-by-step with validation gates, iterative refinement loops
3. **MCP Enhancement** — workflow guidance on top of MCP tool access
   - Key techniques: coordinates MCP calls in sequence, embeds domain expertise, error handling

## Five Skill Patterns

### 1. Sequential Workflow Orchestration
Use when users need multi-step processes in a specific order.
- Explicit step ordering with dependencies between steps
- Validation at each stage
- Rollback instructions for failures

### 2. Multi-MCP Coordination
Use when workflows span multiple services.
- Clear phase separation (e.g., Figma → Drive → Linear → Slack)
- Data passing between MCPs
- Validation before moving to next phase

### 3. Iterative Refinement
Use when output quality improves with iteration.
- Initial draft → Quality check → Refinement loop → Finalization
- Explicit quality criteria and validation scripts
- Know when to stop iterating

### 4. Context-Aware Tool Selection
Use when same outcome needs different tools depending on context.
- Clear decision criteria (file size, type, collaborative needs)
- Fallback options
- Transparency about choices made

### 5. Domain-Specific Intelligence
Use when skill adds specialized knowledge beyond tool access.
- Domain expertise embedded in logic (compliance, security, financial rules)
- Verification before action
- Comprehensive audit trail

## MCP + Skills Synergy

MCP provides connectivity (what Claude can do). Skills provide knowledge (how Claude should do it).

**Without skills:** users connect MCP but don't know what to do, inconsistent results, each conversation starts from scratch.

**With skills:** pre-built workflows activate automatically, consistent tool usage, best practices embedded, lower learning curve.

## Testing

### Three Test Areas
1. **Triggering tests** — verify skill loads at right times
   - Should trigger on obvious tasks
   - Should trigger on paraphrased requests
   - Should NOT trigger on unrelated topics
2. **Functional tests** — verify correct outputs
   - Valid outputs generated, API calls succeed, error handling works, edge cases covered
3. **Performance comparison** — prove skill improves vs baseline
   - Compare tool calls, tokens consumed, error rates with and without skill

### Success Metrics
- Skill triggers on 90% of relevant queries
- Completes workflow in X tool calls
- 0 failed API calls per workflow
- Users don't need to prompt about next steps
- Workflows complete without user correction
- Consistent results across sessions

### Iteration Signals

**Undertriggering:** skill doesn't load when it should, users manually enabling it
→ Fix: add more detail/keywords to description

**Overtriggering:** skill loads for irrelevant queries, users disabling it
→ Fix: add negative triggers, be more specific

**Execution issues:** inconsistent results, API failures, user corrections needed
→ Fix: improve instructions, add error handling

## Distribution

- GitHub public repo with clear README (repo-level, NOT inside skill folder)
- Example usage with screenshots
- Organization-level deployment available (admin-managed, auto-updates)
- API: `/v1/skills` endpoint, `container.skills` parameter for Messages API
- Agent SDK integration for custom agents

## Quick Checklist

**Before starting:** 2-3 concrete use cases, tools identified, guide reviewed
**During development:** kebab-case folder, SKILL.md exists, frontmatter valid, description has WHAT+WHEN+capabilities, no XML tags, clear instructions, error handling, examples, references linked
**Before upload:** triggering tests (obvious + paraphrased + negative), functional tests, compressed as .zip
**After upload:** real conversation tests, monitor triggering, collect feedback, iterate
