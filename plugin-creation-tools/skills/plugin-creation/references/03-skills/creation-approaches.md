# Skill Creation Approaches

Choosing the right tool for creating skills based on source material and requirements.

## Approach Comparison

| Approach | Best For | Speed | Quality |
|----------|----------|-------|---------|
| **Manual (Skill Creator)** | Custom workflows, domain expertise | Slow | Highest |
| **Automated (Skill Seeker)** | Large documentation, reference skills | Fast | Medium |
| **Hybrid** | Production skills from external docs | Medium | High |
| **Meta-skill (agent-skill-creator)** | Autonomous agent creation | Medium | High |

## Decision Tree

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

## When to Use Each

### Manual Creation (This Skill)
**Use when:**
- Building workflow/process skills
- Encoding personal or team expertise
- Quality is critical
- Skill requires careful progressive disclosure
- Custom scripts needed

**Tools:**
- This skill: `skill-creation`
- Anthropic's: `skill-creator@example-skills`
- Superpowers: `superpowers:writing-skills`

### Automated Scraping (Skill Seeker MCP)
**Use when:**
- Creating reference skills from large docs
- Time-constrained
- Source documentation is well-structured
- Will refine output manually afterward

**Tool:** Skill Seeker MCP server
- Scrapes documentation sites
- Generates SKILL.md automatically
- Supports llms.txt for faster processing

**Limitations:**
- Output may need manual refinement
- Less control over structure
- May miss nuance in workflows

### Hybrid Approach
**Use when:**
- Need speed AND quality
- Building from external documentation
- Want automated gathering + manual refinement

**Process:**
1. Use Skill Seeker to scrape docs
2. Review and restructure SKILL.md
3. Add workflow guidance manually
4. Apply progressive disclosure
5. Test and iterate

### Meta-skill (agent-skill-creator)
**Use when:**
- Creating skills for autonomous agents
- Need agent-to-agent skill creation
- Building skill pipelines

## Available Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| **skill-creation** | Guided manual creation with scripts | This skill |
| **skill-creator** | Anthropic's official creator | `@example-skills` |
| **Skill Seeker MCP** | Automated doc scraping | MCP server |
| **superpowers:writing-skills** | TDD skill development | `/plugin install superpowers` |
| **agent-skill-creator** | Autonomous agent creation | GitHub |

## Installation Instructions

### This Skill (skill-creation)
Already installed if you're reading this. Part of the `skill-creation-tools` plugin.

### Anthropic's skill-creator
```bash
# Add Anthropic's skills marketplace
/plugin marketplace add anthropics/skills

# Install example-skills plugin (includes skill-creator)
/plugin install example-skills@anthropic-agent-skills
```

### Superpowers Framework
```bash
# Add superpowers marketplace
/plugin marketplace add obra/superpowers-marketplace

# Install superpowers plugin
/plugin install superpowers@superpowers-marketplace

# Use the writing-skills skill
# Triggers automatically when creating/editing skills
```

### Skill Seeker MCP
Skill Seeker is an MCP server for automated documentation scraping.

```bash
# Clone the repository
git clone https://github.com/your-org/skill-seeker.git

# Install dependencies
cd skill-seeker
pip install -r requirements.txt

# Add to Claude Code MCP configuration
# In your project or global .mcp.json:
{
  "mcpServers": {
    "skill-seeker": {
      "command": "python",
      "args": ["/path/to/skill-seeker/server.py"]
    }
  }
}
```

**Usage:**
```bash
# Generate config for a documentation site
mcp__skill-seeker__generate_config --url https://docs.example.com --name my-skill

# Scrape and build skill
mcp__skill-seeker__scrape_docs --config configs/my-skill.json
```

### Agent Skill Creator
For autonomous agent-to-agent skill creation:

```bash
# Clone repository
git clone https://github.com/example/agent-skill-creator.git

# Follow repository README for setup
```

## Tool Comparison Matrix

| Feature | This Skill | Anthropic skill-creator | Skill Seeker | Superpowers |
|---------|------------|------------------------|--------------|-------------|
| Manual creation | Yes | Yes | No | Yes |
| Automated scraping | No | No | Yes | No |
| Scripts included | Yes | Yes | Yes | No |
| TDD approach | No | No | No | Yes |
| Progressive disclosure | Guided | Guided | Basic | Guided |
| Best for | Custom skills | Custom skills | Large docs | Discipline skills |

## Skills vs Other Claude Features

Before creating a skill, consider if another feature fits better:

| Feature | Invocation | Best For |
|---------|------------|----------|
| **Skills** | Automatic (model-invoked) | Specialized capabilities, workflows |
| **Slash Commands** | Manual (`/command`) | Quick shortcuts, explicit actions |
| **MCP Servers** | Tool calls | External service integrations |
| **Projects** | Always loaded | Project context, instructions |
| **Agents** | Task tool | Complex multi-step autonomous work |

### When NOT to Create a Skill

- **One-time task**: Just do it directly
- **External API needed**: Use/create MCP server instead
- **User must trigger explicitly**: Use slash command
- **Project-specific context**: Use CLAUDE.md or project instructions
- **Complex autonomous workflow**: Create an agent definition

### The 5-10 Rule

```
Have you done this task 5+ times?
├─ NO → Don't create skill yet
└─ YES → Will you do it 10+ more times?
    ├─ NO → Consider slash command instead
    └─ YES → Create a skill
```
