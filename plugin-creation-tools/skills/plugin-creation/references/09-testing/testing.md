# Testing Plugins

How to validate plugins and their components work correctly before deployment.

## Testing Overview

| Component | Test Method | Success Indicator |
|-----------|-------------|-------------------|
| **Skills** | Ask matching questions | Auto-triggers, workflow runs |
| **Commands** | Run `/command-name` | Appears in `/help`, executes correctly |
| **Agents** | Check `/agents`, trigger scenarios | Listed, auto-delegates when expected |
| **Hooks** | Trigger events, check `--debug` | Executes on events, output correct |
| **MCP** | Check `/mcp`, use tools | Server listed, tools work |

## Plugin-Level Testing

### Quick Validation

```bash
# Validate plugin structure
claude plugin validate .

# Check with debug output
claude --debug "plugins"

# Run plugin doctor
claude doctor
```

### Installation Test

```bash
# 1. Add local marketplace
/plugin marketplace add ./path/to/dev-marketplace

# 2. Install plugin
/plugin install my-plugin@dev-marketplace

# 3. Verify loading (no errors)
claude --debug "plugins"
```

---

## Testing Commands

### Checklist

- [ ] Appears in `/help` output
- [ ] Description is clear and complete
- [ ] Arguments work (`$1`, `$2`, `$ARGUMENTS`)
- [ ] Tool restrictions enforced (`allowed-tools`)
- [ ] Bash execution works (`!command`)
- [ ] File references work (`@file.md`)

### Test Process

```bash
# 1. Check command appears
/help

# 2. Run with no arguments
/my-command

# 3. Run with arguments
/my-command arg1 arg2

# 4. Test tool restrictions (should fail if restricted)
# (run command that would use disallowed tool)
```

---

## Testing Agents

### Checklist

- [ ] Appears in `/agents` output
- [ ] Description triggers auto-delegation
- [ ] Tool permissions correct
- [ ] Handles expected scenarios
- [ ] Returns useful results

### Test Process

```bash
# 1. Check agent appears
/agents

# 2. Test auto-delegation
# Ask question matching agent description
# Example: "Review this code for security issues"

# 3. Test manual invocation
# Use Task tool with agent name

# 4. Verify tool restrictions
# Check agent doesn't use tools outside its list
```

### Common Issues

**Agent not triggering:**
- Description too vague
- Missing "proactively" or action triggers
- Competing with similar agent

**Fix:** Make description more specific with examples.

---

## Testing Hooks

### Checklist

- [ ] Scripts are executable (`chmod +x`)
- [ ] Correct event type used
- [ ] Matcher patterns correct
- [ ] Timeouts appropriate
- [ ] Errors handled gracefully

### Test Process

```bash
# 1. Make scripts executable
chmod +x scripts/*.sh

# 2. Test scripts directly
./scripts/my-hook.sh

# 3. Run Claude with debug
claude --debug "hooks"

# 4. Trigger the event
# PostToolUse: Edit a file
# SessionStart: Start new session
# UserPromptSubmit: Enter a prompt
```

### Debug Hooks

```bash
# See all hook activity
claude --debug "hooks"

# View hook configurations
/hooks
```

### Common Issues

**Hook not firing:**
- Script not executable
- Wrong event type
- Matcher doesn't match tool name

**Hook fails:**
- Script has errors (test manually first)
- Timeout too short
- Missing environment variables

---

## Testing MCP Servers

### Checklist

- [ ] Server binary/command exists
- [ ] Config paths use `${CLAUDE_PLUGIN_ROOT}`
- [ ] Environment variables set
- [ ] Server starts without errors
- [ ] Tools appear in listing

### Test Process

```bash
# 1. Check server appears
/mcp

# 2. Test server manually
${CLAUDE_PLUGIN_ROOT}/servers/my-server --help

# 3. Debug connection
claude --debug "mcp"

# 4. Use tools
# Ask Claude to use the MCP-provided tools
```

### Common Issues

**Server not starting:**
- Binary not found (check path)
- Missing `${CLAUDE_PLUGIN_ROOT}` variable
- Config file errors

**Tools not working:**
- Server crashes (run manually to debug)
- Environment variables missing
- Authentication required

---

## TDD for Skills

### RED Phase
1. Run pressure scenario WITHOUT skill
2. Document exact behavior verbatim
3. Identify failure patterns and rationalizations

### GREEN Phase
4. Write minimal skill addressing failures
5. Test again - verify improvement

### REFACTOR Phase
6. Identify new rationalizations
7. Add explicit counters
8. Re-test until bulletproof

## Testing by Skill Type

### Discipline-Enforcing Skills
- Test with academic understanding questions
- Test under pressure (time, sunk cost, authority)
- Test with combined pressures
- **Success**: Agent follows rule under maximum pressure

### Technique Skills
- Test application scenarios
- Test edge cases and variations
- Test with missing information
- **Success**: Agent applies technique correctly

### Reference Skills
- Test information retrieval
- Test application of information
- Test for coverage gaps
- **Success**: Agent finds and uses information correctly

## Validation Checklist

### Frontmatter
- [ ] Only `name` and `description` fields (plus optional: license, allowed-tools, metadata)
- [ ] Name: lowercase letters, numbers, hyphens only
- [ ] Name: max 64 characters
- [ ] Name: matches directory name
- [ ] Description: starts with "Use when..."
- [ ] Description: includes specific triggers
- [ ] Description: written in third person
- [ ] Description: under 1024 characters

### Content
- [ ] SKILL.md body under 500 lines
- [ ] No duplicate information
- [ ] All referenced files exist
- [ ] Scripts tested and working
- [ ] Examples are complete and runnable

### Discovery
- [ ] Description triggers correctly for intended tasks
- [ ] Doesn't trigger for unrelated tasks
- [ ] Keywords match likely searches

## Quick Validation Commands

```bash
# Check frontmatter format
head -20 SKILL.md

# Count lines (target: <500)
wc -l SKILL.md

# Find broken references
grep -o 'references/[^)]*' SKILL.md | while read f; do
  [ -f "$f" ] || echo "Missing: $f"
done

# Find broken script references
grep -o 'scripts/[^)]*' SKILL.md | while read f; do
  [ -f "$f" ] || echo "Missing: $f"
done

# Test scripts run
python scripts/*.py --help 2>/dev/null || echo "Check script syntax"

# Run validator
python scripts/validate_skill.py .
```

## Size Guidelines

| Component | Target | Maximum |
|-----------|--------|---------|
| Description | 200-500 chars | 1024 chars |
| SKILL.md body | <500 lines | 5000 words |
| Individual reference | <1000 lines | 10k words |
| Total skill files | <50 files | No limit |

## Success Criteria

A skill is ready when:

1. **Triggers correctly** - Loads for intended tasks, not unrelated ones
2. **Workflow works** - Claude follows the process correctly
3. **Output matches** - Results meet expectations
4. **No rationalization** - Claude doesn't skip or shortcut the skill
5. **Scripts execute** - All bundled scripts run without errors
6. **References exist** - All referenced files are present

## Example Test Scenarios

Per Anthropic guidelines, create 3+ evaluation scenarios before deployment.

### Scenario 1: New Skill Creation
**Input:** "I want to create a skill for generating API documentation"
**Expected:**
- Skill triggers and loads
- Six-step workflow is followed
- Scripts are used for init/validate/package
- Progressive disclosure applied (SKILL.md hub, details in references/)

### Scenario 2: Skill Not Discovered
**Input:** "My skill isn't showing up when I ask Claude to use it"
**Expected:**
- Skill triggers on discovery issues
- Description field guidance provided
- Checklist for triggers/keywords reviewed

### Scenario 3: Choosing Creation Approach
**Input:** "Should I scrape docs or write a skill manually?"
**Expected:**
- Decision framework referenced
- Tool comparison provided
- Recommendation based on source material

## Cross-Model Testing

Anthropic recommends testing skills across models:

| Model | Focus |
|-------|-------|
| Haiku | Speed, basic compliance |
| Sonnet | Balance, typical usage |
| Opus | Complex reasoning, edge cases |

Run each scenario on all three models before deployment.
