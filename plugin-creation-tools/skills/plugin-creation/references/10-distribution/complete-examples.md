# Complete Examples

Full working examples of plugin structures.

## Example 1: Enterprise Tools Plugin

A complete plugin with all component types.

### Directory Structure

```
enterprise-plugin/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── deploy.md
│   ├── status.md
│   └── logs.md
├── agents/
│   ├── security-reviewer.md
│   ├── performance-analyzer.md
│   └── compliance-checker.md
├── skills/
│   ├── code-review/
│   │   ├── SKILL.md
│   │   ├── SECURITY.md
│   │   ├── PERFORMANCE.md
│   │   └── scripts/
│   │       └── run-linters.sh
│   └── deployment/
│       ├── SKILL.md
│       └── reference.md
├── hooks/
│   └── hooks.json
├── .mcp.json
├── scripts/
│   ├── format-code.sh
│   ├── validate.py
│   └── security-scan.sh
├── LICENSE
├── CHANGELOG.md
└── README.md
```

### plugin.json

```json
{
  "name": "enterprise-tools",
  "version": "3.0.0",
  "description": "Enterprise automation, security, and deployment tools",
  "author": {
    "name": "Enterprise DevOps",
    "email": "devops@company.com",
    "url": "https://github.com/company"
  },
  "homepage": "https://docs.company.com/plugins/enterprise-tools",
  "repository": "https://github.com/company/enterprise-plugin",
  "license": "MIT",
  "keywords": ["enterprise", "deployment", "security", "automation"],
  "commands": ["./commands/deploy.md", "./commands/status.md"],
  "agents": "./agents/",
  "hooks": "./hooks/hooks.json",
  "mcpServers": "./.mcp.json"
}
```

### commands/deploy.md

```markdown
---
description: Deploy application to production with safety checks. Use when ready to deploy changes.
allowed-tools: Bash(git:*), Bash(docker:*), Read
argument-hint: [environment] [version]
---

# Deploy Application

Deploy to $1 environment version $2.

Steps:
1. Verify deployment checklist
2. Run safety checks
3. Execute deployment
4. Verify health
5. Notify team
```

### agents/security-reviewer.md

```markdown
---
name: security-reviewer
description: Security specialist. Proactively reviews code after changes for vulnerabilities and security issues.
capabilities: ["security review", "vulnerability detection", "compliance check"]
tools: Read, Grep, Glob, Bash
---

# Security Reviewer

Review code for security vulnerabilities.

## Process
1. Check recent changes
2. Scan for common vulnerabilities
3. Review dependencies
4. Check authentication/authorization

## Security Checklist
- No hardcoded credentials
- Input validation present
- SQL injection prevention
- XSS prevention
- CORS properly configured
- Rate limiting implemented
- Secrets management in place
```

### skills/code-review/SKILL.md

```markdown
---
name: code-review
description: Review code for quality, security, and performance. Use when reviewing code, checking PRs, or analyzing code quality.
allowed-tools: Read, Grep, Glob, Bash
---

# Code Review

## Review Process
1. Read code files
2. Search for patterns
3. Identify issues
4. Suggest improvements

## Review Checklist
- Code clarity and readability
- Variable naming
- Function length
- Complexity
- Error handling
- Test coverage
- Security concerns
- Performance issues

## Output Format
Organize feedback by priority:
- Critical (must fix)
- Warnings (should fix)
- Suggestions (consider)
```

### hooks/hooks.json

```json
{
  "description": "Enterprise plugin hooks",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format-code.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/security-scan.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup-env.sh"
          }
        ]
      }
    ]
  }
}
```

### .mcp.json

```json
{
  "enterprise-db": {
    "command": "${CLAUDE_PLUGIN_ROOT}/servers/db-server",
    "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config/db.json"],
    "env": {
      "DB_PATH": "${CLAUDE_PLUGIN_ROOT}/data",
      "LOG_LEVEL": "info"
    }
  },
  "company-api": {
    "type": "http",
    "url": "https://api.company.com/mcp",
    "headers": {
      "Authorization": "Bearer ${COMPANY_API_KEY}"
    }
  }
}
```

---

## Example 2: Marketplace Configuration

### marketplace.json

```json
{
  "name": "company-tools",
  "owner": {
    "name": "DevTools Team",
    "email": "devtools@company.com"
  },
  "metadata": {
    "description": "Company-wide Claude Code plugins and tools",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "enterprise-tools",
      "source": {
        "source": "github",
        "repo": "company/enterprise-plugin"
      },
      "description": "Enterprise automation, security, and deployment tools",
      "version": "3.0.0",
      "keywords": ["enterprise", "deployment", "security"],
      "category": "productivity"
    },
    {
      "name": "code-formatter",
      "source": "./code-formatter",
      "description": "Automatic code formatting",
      "version": "2.0.0"
    }
  ]
}
```

---

## Example 3: Team Settings Configuration

### .claude/settings.json (team-shared)

```json
{
  "extraKnownMarketplaces": {
    "company-tools": {
      "source": {
        "source": "github",
        "repo": "company/claude-plugins"
      }
    }
  },
  "enabledPlugins": {
    "enterprise-tools@company-tools": true,
    "code-formatter@company-tools": true
  },
  "permissions": {
    "allow": [
      "Bash(npm run:*)",
      "Bash(docker:*)",
      "Edit(./output/**)",
      "Edit(./logs/**)"
    ],
    "deny": [
      "Read(.env)",
      "Read(.env.*)",
      "Read(./secrets/**)"
    ]
  },
  "env": {
    "CLAUDE_PLUGIN_OUTPUT_DIR": "${HOME}/claude-outputs",
    "PLUGIN_LOG_LEVEL": "info"
  }
}
```

### .claude/settings.local.json (personal overrides)

```json
{
  "enabledPlugins": {
    "experimental-plugin@personal": true
  },
  "env": {
    "PLUGIN_LOG_LEVEL": "debug"
  }
}
```

---

## Example 4: Minimal Plugin

Simplest possible plugin with one command:

### Directory Structure

```
minimal-plugin/
├── .claude-plugin/
│   └── plugin.json
└── commands/
    └── hello.md
```

### plugin.json

```json
{
  "name": "minimal-plugin",
  "version": "1.0.0",
  "description": "A minimal example plugin"
}
```

### commands/hello.md

```markdown
---
description: Say hello with a friendly greeting
---

# Hello

Greet the user warmly and ask how you can help today.
```

---

## Example 5: Skills-Only Plugin

Plugin focused on skills without commands or agents:

### Directory Structure

```
skills-plugin/
├── .claude-plugin/
│   └── plugin.json
└── skills/
    ├── pdf-processing/
    │   ├── SKILL.md
    │   ├── FORMS.md
    │   └── scripts/
    │       └── extract.py
    └── spreadsheet/
        ├── SKILL.md
        └── REFERENCE.md
```

### plugin.json

```json
{
  "name": "document-skills",
  "version": "1.0.0",
  "description": "Document processing skills for PDF and spreadsheet files",
  "author": {
    "name": "Your Name"
  },
  "license": "MIT"
}
```

---

## Example 6: Hooks-Only Plugin

Plugin that only provides automation hooks:

### Directory Structure

```
formatter-plugin/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   └── hooks.json
└── scripts/
    ├── format.sh
    └── lint.sh
```

### plugin.json

```json
{
  "name": "auto-formatter",
  "version": "1.0.0",
  "description": "Automatic code formatting on file changes",
  "hooks": "./hooks/hooks.json"
}
```

### hooks/hooks.json

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format.sh"
          }
        ]
      }
    ]
  }
}
```

---

## Usage Notes

1. **Start minimal**: Begin with the simplest structure that works
2. **Add components as needed**: Don't create empty directories
3. **Test incrementally**: Test each component before adding more
4. **Version appropriately**: Use semantic versioning from the start
5. **Document well**: README should explain purpose and usage
