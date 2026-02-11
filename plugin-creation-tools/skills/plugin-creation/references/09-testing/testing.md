# Testing Plugins

How to validate plugins and their components work correctly before deployment.

## Workflow Checklist Pattern

For complex multi-step testing, provide a checklist Claude can track:

```markdown
Copy this checklist and track progress:

Testing Progress:
- [ ] Step 1: Validate plugin structure
- [ ] Step 2: Test skill triggering
- [ ] Step 3: Test command execution
- [ ] Step 4: Verify agent delegation
- [ ] Step 5: Confirm hook firing
```

This pattern is recommended for any multi-step workflow in your skills.

## Test with Multiple Models

Skills behave differently across models:

| Model | What to Check |
|-------|---------------|
| **Claude Haiku** | Does the skill provide enough guidance? |
| **Claude Sonnet** | Is the skill clear and efficient? |
| **Claude Opus** | Does the skill avoid over-explaining? |

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

## CLI Automation for Testing

Use Claude's CLI flags for non-interactive, automated plugin testing.

### Non-Interactive Testing with `-p`

The `-p` (print) flag runs Claude in non-interactive mode, useful for scripted tests:

```bash
# Basic non-interactive test
claude -p "test query" --output-format json

# Test that a skill triggers correctly
claude -p "I need to create a new plugin" --output-format json

# Test a command
claude -p "/my-command arg1 arg2" --output-format json
```

### Structured Output

```bash
# JSON output with session_id for resumption
claude -p "test query" --output-format json

# Validated structured output (print mode only)
claude -p "analyze this code" --json-schema '{"type":"object","properties":{"issues":{"type":"array"}}}'
```

### Session Resumption

Capture the session_id from JSON output to resume and continue testing:

```bash
# Run initial test, capture session_id
RESULT=$(claude -p "start a code review" --output-format json)
SESSION_ID=$(echo "$RESULT" | jq -r '.session_id')

# Resume the session with follow-up
claude -p "now check for security issues" --resume "$SESSION_ID" --output-format json
```

### Bounded Testing

Control resource usage during automated testing:

```bash
# Limit conversation turns
claude -p "run full audit" --max-turns 5

# Limit budget
claude -p "analyze codebase" --max-budget-usd 0.50

# Combine limits
claude -p "comprehensive review" --max-turns 10 --max-budget-usd 1.00
```

### Tool Approval

Auto-approve specific tools without prompting during tests:

```bash
# Allow specific tools
claude -p "edit the config file" --allowedTools "Edit,Write,Bash"

# Allow MCP tools
claude -p "fetch data" --allowedTools "mcp__my-server__query"
```

### Custom Instructions for Testing

```bash
# Add custom instructions while preserving defaults (recommended)
claude -p "test query" --append-system-prompt "You are testing plugin X. Report any errors."

# Note: --append-system-prompt is preferred over --system-prompt
# because it preserves Claude's default system instructions
```

### Debug Output

```bash
# Verbose turn-by-turn output for debugging
claude -p "test query" --verbose

# Combine with debug flags
claude -p "test query" --verbose --debug "plugins,hooks"
```

### Example: Automated Test Script

```bash
#!/bin/bash
# test-plugin.sh - Automated plugin test suite

PASS=0
FAIL=0

run_test() {
  local description="$1"
  local query="$2"
  local expected="$3"

  RESULT=$(claude -p "$query" --output-format json --max-turns 3 --max-budget-usd 0.25)

  if echo "$RESULT" | grep -q "$expected"; then
    echo "PASS: $description"
    ((PASS++))
  else
    echo "FAIL: $description"
    echo "  Expected: $expected"
    ((FAIL++))
  fi
}

run_test "Skill triggers" "I need to create a plugin" "plugin-creation"
run_test "Command works" "/my-command test" "expected output"
run_test "Error handling" "invalid input scenario" "error message"

echo ""
echo "Results: $PASS passed, $FAIL failed"
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

## Triggering Test Methodology

Per Anthropic's official guide, triggering tests verify your skill loads at the right times. Create a test suite with three categories:

### Should Trigger (obvious tasks)
```
- "[Direct request matching skill purpose]"
- "[Paraphrased version of the same request]"
- "[Request using alternative terminology]"
```

### Should Trigger (paraphrased/indirect)
```
- "[Indirect request that implies skill purpose]"
- "[Request using synonyms or related terms]"
- "[Request that mentions relevant file types or tools]"
```

### Should NOT Trigger
```
- "[Unrelated request in different domain]"
- "[Similar-sounding but different purpose]"
- "[Request that a different skill should handle]"
```

**Target**: Skill triggers on 90% of relevant queries from the first two categories, and 0% from the third.

**Debugging approach**: Ask Claude: "When would you use the [skill name] skill?" Claude will quote the description back. Adjust based on what's missing.

### Example Triggering Test Suite

For a `pdf-processing` skill:

**Should trigger:**
- "Extract text from this PDF"
- "I need to pull data from a PDF file"
- "Help me fill out this PDF form"

**Should NOT trigger:**
- "What's the weather today?"
- "Help me write Python code"
- "Create a spreadsheet" (unless skill handles this)

## Success Criteria

A skill is ready when:

### Qualitative
1. **Triggers correctly** - Loads for intended tasks, not unrelated ones
2. **Workflow works** - Claude follows the process correctly
3. **Output matches** - Results meet expectations
4. **No rationalization** - Claude doesn't skip or shortcut the skill
5. **Scripts execute** - All bundled scripts run without errors
6. **References exist** - All referenced files are present

### Quantitative Benchmarks (Anthropic recommended)
- Skill triggers on **90%** of relevant queries
- Completes workflow in **X tool calls** (measure and set target)
- **0 failed API calls** per workflow run
- Users don't need to prompt Claude about next steps
- Workflows complete without user correction
- Consistent results across sessions (run same request 3-5 times)

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
