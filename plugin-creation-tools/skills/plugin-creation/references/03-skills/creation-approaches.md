# Skill Creation Approaches

Choosing the right tool for creating skills based on source material and requirements.

## The 6-Step Creation Process

> **Attribution**: This process is adapted from Anthropic's `skill-creator` skill (document-skills@anthropic-agent-skills). We've enhanced it with our scripts and templates while preserving the core workflow.

When creating skills manually (recommended for custom workflows and domain expertise), follow this structured process:

### Step 1: Understand the Skill with Concrete Examples

**Goal**: Clearly understand how the skill will be used.

Skip this step only when usage patterns are already crystal clear.

**Actions**:
- Gather concrete examples from users or create validated examples
- Ask clarifying questions:
  - "What functionality should this skill support?"
  - "Can you give examples of how this would be used?"
  - "What would trigger this skill?"
- Document 3-5 real usage scenarios

**Example questions for an image-editor skill**:
- "What functionality: editing, rotating, resizing, filters?"
- "Example uses: 'Remove red-eye', 'Rotate 90 degrees', 'Resize to 800x600'?"
- "What triggers it: 'edit image', 'process photo', 'fix picture'?"

**Completion criteria**: Clear sense of functionality the skill should support.

### Step 2: Plan Reusable Skill Contents

**Goal**: Identify what bundled resources (scripts, references, assets) would be helpful.

For each concrete example, analyze:
1. How to execute from scratch
2. What would make repeated execution easier

**Decision matrix**:

| If task requires... | Include... |
|---------------------|------------|
| Same code rewritten each time | `scripts/` - Executable code |
| Re-discovering schemas/APIs each time | `references/` - Documentation |
| Same boilerplate HTML/templates each time | `assets/` - Template files |

**Examples**:

**PDF rotation** → Requires rewriting code each time → `scripts/rotate_pdf.py`

**BigQuery queries** → Requires re-discovering schemas → `references/schema.md`

**Frontend apps** → Requires same boilerplate → `assets/hello-world/` template

**Output**: List of bundled resources needed (scripts, references, assets).

### Step 3: Initialize the Skill

**Goal**: Create skill directory structure.

Skip this step only if the skill already exists and needs iteration.

**Always use the init script**:
```bash
scripts/init_skill.py <skill-name> --path <output-directory>
```

The script automatically:
- Creates skill directory structure
- Generates SKILL.md template with frontmatter
- Creates example `scripts/`, `references/`, `assets/` directories
- Adds example files you can customize or delete

**After initialization**: Customize or remove generated example files as needed.

### Step 4: Edit the Skill

**Goal**: Implement bundled resources and write SKILL.md instructions.

#### 4a. Implement Bundled Resources

Start with the reusable resources identified in Step 2:

**For scripts/**:
- Write and test by actually running them
- Ensure no bugs, output matches expectations
- Test representative samples if many similar scripts

**For references/**:
- Gather documentation, schemas, API docs
- May require user input (brand assets, templates, documentation)
- Organize by domain or framework for large skills

**For assets/**:
- Collect templates, images, boilerplate code
- Store files that will be used in output

**Delete** any example files not needed for the skill.

#### 4b. Write SKILL.md

**Remember**: SKILL.md is INSTRUCTIONS for Claude, not documentation.

**Frontmatter**:
```yaml
---
name: skill-name
description: Use when [triggers] - [what it does]. Include specific contexts: (1) scenario, (2) scenario, (3) scenario
---
```

**Body**:
- Use imperative/infinitive form
- Tell Claude what to DO, not what things ARE
- Keep under 500 lines (split to references/ if larger)
- Link to bundled resources: "See references/file.md for..."
- One excellent example per pattern

**See also**: `writing-skillmd.md` for complete guidance.

### Step 5: Package the Skill

**Goal**: Validate and create distributable .skill file.

**Always use the package script**:
```bash
scripts/package_skill.py <path/to/skill-folder>
```

Optional output directory:
```bash
scripts/package_skill.py <path/to/skill-folder> ./dist
```

The script automatically:
1. **Validates** the skill:
   - YAML frontmatter format
   - Required fields present
   - Naming conventions
   - File organization
   - Description quality
2. **Packages** if validation passes:
   - Creates .skill file (zip with .skill extension)
   - Includes all files with proper structure

**If validation fails**: Fix errors and rerun.

**Output**: Distributable `skill-name.skill` file.

### Step 6: Iterate Based on Real Usage

**Goal**: Improve skill based on actual performance.

After testing the skill on real tasks:

1. **Notice** struggles or inefficiencies
2. **Identify** how SKILL.md or bundled resources should change
3. **Implement** changes
4. **Test** again

**Common iteration patterns**:

| Observation | Solution |
|-------------|----------|
| Claude asks same question repeatedly | Add to SKILL.md or references/ |
| Rewriting similar code each time | Extract to scripts/ |
| Missing edge cases | Add to references/troubleshooting.md |
| Confusing instructions | Simplify SKILL.md, add examples |
| Too verbose, loads slowly | Move details to references/, use progressive disclosure |

### See Also: Anthropic's skill-creator

For an alternative approach to skill creation, see Anthropic's official `skill-creator` skill:

```bash
# Install Anthropic's example-skills plugin
/plugin marketplace add anthropics/skills
/plugin install example-skills@anthropic-agent-skills
```

**When to use Anthropic's skill-creator vs this skill:**

| Use Anthropic's skill-creator | Use plugin-creation (this skill) |
|------------------------------|----------------------------------|
| Creating standalone skills only | Creating plugins with multiple components |
| Prefer Anthropic's official approach | Need commands, agents, hooks, or MCP servers |
| Want minimal, focused guidance | Want comprehensive templates and scripts |
| - | Need cross-platform hooks or output management |

**Both approaches are valid** - Anthropic's is more focused, ours is more comprehensive. Choose based on your needs.

---

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
