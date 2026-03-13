# Marketplace Distribution

Distribute your plugins through marketplaces for team and community access.

## Distribution Strategies

### Individual Use

Keep plugin in personal repository:

```bash
# Install from GitHub
/plugin marketplace add username/my-plugins

# Install specific plugin
/plugin install plugin-name@username
```

### Team Distribution

Share through organization repository:

1. Create marketplace repository
2. Add to team settings
3. Team members auto-discover

### Community Distribution

Publish to public marketplace:

1. Create public GitHub repository
2. Add marketplace.json
3. Share repository URL

## Setting Up a Marketplace

### Repository Structure

```
marketplace-repo/
├── .claude-plugin/
│   └── marketplace.json
├── plugins/
│   ├── plugin-one/
│   │   └── .claude-plugin/
│   │       └── plugin.json
│   └── plugin-two/
│       └── .claude-plugin/
│           └── plugin.json
└── README.md
```

### marketplace.json

```json
{
  "name": "team-tools",
  "owner": {
    "name": "Your Team",
    "email": "team@company.com"
  },
  "metadata": {
    "description": "Team productivity tools",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "code-quality",
      "source": "./plugins/code-quality",
      "description": "Code quality tools",
      "version": "1.2.0",
      "keywords": ["quality", "linting"]
    },
    {
      "name": "deployment",
      "source": "./plugins/deployment",
      "description": "Deployment automation",
      "version": "2.0.0"
    }
  ]
}
```

## Team Integration

### Add to Project Settings

In `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "team-tools": {
      "source": {
        "source": "github",
        "repo": "company/claude-plugins"
      }
    }
  }
}
```

Team members are prompted to add marketplace when trusting the folder.

### Pre-Enable Plugins

```json
{
  "extraKnownMarketplaces": {
    "team-tools": {
      "source": {
        "source": "github",
        "repo": "company/claude-plugins"
      }
    }
  },
  "enabledPlugins": {
    "code-quality@team-tools": true,
    "deployment@team-tools": true
  }
}
```

## User Installation Flow

### Add Marketplace

```bash
# From GitHub
/plugin marketplace add company/claude-plugins

# From any git URL
/plugin marketplace add https://gitlab.com/team/plugins.git

# From local path (development)
/plugin marketplace add ./local-marketplace
```

### Browse Available

```bash
/plugin marketplace list
```

### Install Plugin

```bash
/plugin install plugin-name@marketplace-name
```

### Update Plugins

```bash
/plugin update plugin-name@marketplace-name
/plugin update --all
```

### Uninstall

```bash
/plugin uninstall plugin-name@marketplace-name
```

## Documentation Requirements

### README.md for Marketplace

```markdown
# Team Tools Marketplace

Claude Code plugins for our team.

## Adding This Marketplace

```
/plugin marketplace add company/claude-plugins
```

## Available Plugins

### code-quality
Code quality tools for linting and formatting.
```
/plugin install code-quality@team-tools
```

### deployment
Deployment automation tools.
```
/plugin install deployment@team-tools
```

## Contributing

1. Fork this repository
2. Add your plugin to `plugins/`
3. Update marketplace.json
4. Submit pull request
```

### README.md for Each Plugin

```markdown
# Plugin Name

Description of what this plugin does.

## Installation

```
/plugin install plugin-name@marketplace-name
```

## Features

- Feature 1
- Feature 2

## Usage

Instructions...
```

## Version Updates

When updating plugins:

1. Update version in plugin.json
2. Update version in marketplace.json
3. Update CHANGELOG.md
4. Commit and push

Users can then:
```bash
/plugin update plugin-name@marketplace
```

## Official Submission

Submit plugins to the official Anthropic marketplace:

- **Claude.ai**: `claude.ai/settings/plugins/submit`
- **Platform**: `platform.claude.com/plugins/submit`

## Private Repository Authentication

For marketplaces and plugins hosted in private repositories, set the appropriate environment variable:

| Variable | Service |
|----------|---------|
| `GITHUB_TOKEN` or `GH_TOKEN` | GitHub |
| `GITLAB_TOKEN` or `GL_TOKEN` | GitLab |
| `BITBUCKET_TOKEN` | Bitbucket |

## Release Channels

Use separate marketplace files pointing to different refs or SHAs to create release channels:

```
marketplace-repo/
├── .claude-plugin/
│   └── marketplace.json           # stable channel (pinned SHAs)
├── .claude-plugin-latest/
│   └── marketplace.json           # latest channel (branch refs)
```

**Stable channel** — pin to specific SHAs for reproducibility:
```json
{
  "name": "team-tools",
  "plugins": [{
    "name": "code-quality",
    "source": {
      "source": "github",
      "repo": "company/code-quality",
      "sha": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
    }
  }]
}
```

**Latest channel** — track a branch for bleeding-edge updates:
```json
{
  "name": "team-tools-latest",
  "plugins": [{
    "name": "code-quality",
    "source": {
      "source": "github",
      "repo": "company/code-quality",
      "ref": "main"
    }
  }]
}
```

## Restricting Marketplaces

Use the `strictKnownMarketplaces` managed setting to control which marketplaces users can add:

```json
{
  "strictKnownMarketplaces": ["https://github.com/company/*"]
}
```

| Value | Behavior |
|-------|----------|
| Not set | Users can add any marketplace |
| Empty array `[]` | Lock down all marketplace additions |
| Array of URLs/patterns | Allow only matching marketplaces |

This is a managed (organization-level) setting, not a project-level one.

## Best Practices

1. **Clear naming**: Use descriptive plugin names
2. **Good descriptions**: Help users find relevant plugins
3. **Keywords**: Add searchable keywords
4. **Documentation**: Include README with examples
5. **Versioning**: Use semantic versioning
6. **Changelog**: Document changes between versions
7. **Testing**: Verify before publishing updates

## See Also

- `packaging.md` - preparing plugins
- `versioning.md` - version management
- `../08-configuration/marketplace-json.md` - schema reference
