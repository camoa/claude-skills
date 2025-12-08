# Debugging Plugins

Troubleshoot plugin loading, component discovery, and execution issues.

## Debug Mode

Run Claude Code with debug output:

```bash
claude --debug
```

This shows detailed information about:
- Plugin discovery and loading
- Component registration
- Hook execution
- MCP server startup

## Common Issues

### Plugin Not Loading

**Symptoms**: Plugin doesn't appear, components unavailable

**Checks**:
1. Verify plugin.json exists and is valid JSON
   ```bash
   cat .claude-plugin/plugin.json | jq .
   ```

2. Verify plugin is enabled
   ```bash
   # Check settings
   cat ~/.claude/settings.json | jq '.enabledPlugins'
   ```

3. Check marketplace is registered
   ```bash
   /plugin marketplace list
   ```

**Solutions**:
- Fix JSON syntax errors
- Enable plugin: `/plugin enable plugin-name@marketplace`
- Add marketplace: `/plugin marketplace add source`

### Commands Not Appearing

**Symptoms**: `/command` not in autocomplete or `/help`

**Checks**:
1. Verify file location
   ```bash
   ls -la plugin-name/commands/
   ```

2. Check frontmatter syntax
   ```bash
   head -10 commands/my-command.md
   ```

3. Look for YAML errors in frontmatter

**Solutions**:
- Ensure `.md` extension
- Fix frontmatter YAML syntax
- Check file permissions

### Agents Not Delegating

**Symptoms**: Agent exists but never triggers

**Checks**:
1. Verify agent appears in `/agents`
2. Check description includes triggers
3. Test with explicit domain keywords

**Solutions**:
- Add "Use proactively when..." to description
- Include specific trigger keywords
- Make description more explicit

### Skills Not Triggering

**Symptoms**: Skill exists but Claude doesn't use it

**Checks**:
1. Verify SKILL.md exists in skill directory
2. Check description includes trigger phrases
3. Test with explicit matching queries

**Solutions**:
- Improve description with specific triggers
- Add keywords users would say
- Check frontmatter syntax

### Hooks Not Running

**Symptoms**: Hooks configured but don't execute

**Checks**:
1. Validate hooks.json syntax
   ```bash
   cat hooks/hooks.json | jq .
   ```

2. Verify hook script exists and is executable
   ```bash
   ls -la scripts/
   chmod +x scripts/*.sh
   ```

3. Test script manually
   ```bash
   ./scripts/format.sh
   ```

**Solutions**:
- Fix JSON syntax
- Make scripts executable
- Check script shebang line
- Verify environment variables

### MCP Server Not Starting

**Symptoms**: MCP tools unavailable

**Checks**:
1. Verify .mcp.json syntax
2. Check command path exists
3. Test server manually
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/servers/my-server --help
   ```

**Solutions**:
- Fix JSON syntax
- Ensure binary is executable
- Check environment variables
- Verify dependencies installed

## Debug Categories

When using `--debug`, look for these log categories:

| Category | Shows |
|----------|-------|
| plugin | Plugin discovery/loading |
| commands | Command registration |
| agents | Agent registration |
| skills | Skill discovery |
| hooks | Hook execution |
| mcp | MCP server status |

## Testing Individual Components

### Test Commands

```bash
# Run command directly
/my-command test-args

# Check help listing
/help
```

### Test Agents

```bash
# List agents
/agents

# Ask triggering question
"Review this code for security issues"
```

### Test Skills

Ask questions matching the skill description:

```
# If skill description mentions "PDF processing"
"Can you extract text from this PDF?"
```

### Test Hooks

Trigger the event manually:

```bash
# For PostToolUse on Write
# Create a file to trigger the hook
```

Use debug mode to see hook execution:
```bash
claude --debug
```

## Validation Checklist

Before distributing, validate:

- [ ] `plugin.json` parses without errors
- [ ] All command files have valid frontmatter
- [ ] All agent files have required fields
- [ ] All skill directories have SKILL.md
- [ ] Hook scripts are executable
- [ ] MCP servers start successfully
- [ ] Commands appear in `/help`
- [ ] Agents appear in `/agents`
- [ ] Skills trigger on relevant queries

## Getting Help

If issues persist:
1. Check debug output carefully
2. Simplify to minimal reproduction
3. Test with fresh Claude session
4. Check Claude Code documentation

## See Also

- `testing.md` - testing strategies
- `../08-configuration/plugin-json.md` - manifest reference
