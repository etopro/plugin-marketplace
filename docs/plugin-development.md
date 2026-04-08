# Plugin Development Guide

This guide covers how to create plugins for the etopro-plugins marketplace.

## Plugin Types

Claude Code supports several plugin component types:

- **Commands** - User-invocable commands (e.g., `/format`)
- **Skills** - Reusable agentic workflows
- **Agents** - Specialized AI agents
- **Hooks** - Event-driven automation
- **MCP Servers** - Model Context Protocol servers
- **LSP Servers** - Language Server Protocol servers

## Creating a Command

Commands are invoked by users and perform specific actions.

### File Structure

```
plugins/your-plugin/
├── .claude-plugin/
│   └── plugin.json
└── commands/
    └── your-command.md
```

### Command Frontmatter

Each command file starts with YAML frontmatter:

```markdown
---
name: your-command
description: Brief description of what the command does
---

# Command Name

Detailed description of the command...

## Usage

Examples of how to use the command.

## Examples

Concrete usage examples.
```

### Example: Simple Command

```markdown
---
name: greet
description: Greet the user by name
---

# Greet

Greets the user with a personalized message.

## Usage

Tell me your name and I'll greet you.

## Examples

Greet me as "Alice"
```

### plugin.json for Commands

```json
{
  "name": "your-plugin",
  "description": "Description of your plugin",
  "version": "1.0.0",
  "author": {
    "name": "Your Name"
  },
  "commands": [
    "commands/your-command.md",
    "commands/another-command.md"
  ]
}
```

## Creating a Skill

Skills are agentic workflows that help with complex tasks.

### File Structure

```
plugins/your-plugin/
├── .claude-plugin/
│   └── plugin.json
└── skills/
    └── your-skill.md
```

### Skill Frontmatter

```markdown
---
name: your-skill
description: Brief description of the skill
---

# Skill Name

Detailed description of the skill...

## Features

List what the skill can do.

## Usage

How to use the skill.
```

### Example: Git Workflow Skill

```markdown
---
name: git-workflow
description: Git workflow automation
---

# Git Workflow

Help with git commits, branches, and PRs.

## Features

- Conventional commit generation
- Branch naming conventions
- PR description help

## Usage

Ask me to help with git tasks.

## Examples

Help me write a commit message for fixing a bug in the login system.
```

### plugin.json for Skills

```json
{
  "name": "your-plugin",
  "description": "Description of your plugin",
  "version": "1.0.0",
  "author": {
    "name": "Your Name"
  },
  "skills": [
    "skills/your-skill.md"
  ]
}
```

## Testing Locally

### 1. Add the Marketplace

```bash
/plugin marketplace add /path/to/etopro-plugins
```

### 2. Install Your Plugin

```bash
/plugin install your-plugin@etopro-plugins
```

### 3. Test the Plugin

```
Use your-command to do something
```

### 4. Validate

```bash
claude plugin validate plugins/your-plugin
```

## Best Practices

### Descriptions

- Be concise but descriptive
- Explain what the plugin does, not how
- Mention key features

### Examples

- Provide concrete examples
- Show expected usage patterns
- Include edge cases if relevant

### Naming

- Use kebab-case for plugin names
- Use descriptive command names
- Avoid abbreviations unless widely known

### Error Handling

- Provide helpful error messages
- Suggest fixes for common issues
- Document requirements clearly

## Advanced Features

### Hooks

Hooks run automatically in response to events:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh"
          }
        ]
      }
    ]
  }
}
```

### MCP Servers

Integrate external tools via MCP:

```json
{
  "mcpServers": {
    "your-server": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/server.js"]
    }
  }
}
```

### Environment Variables

- `${CLAUDE_PLUGIN_ROOT}` - Plugin installation directory
- `${CLAUDE_PLUGIN_DATA}` - Persistent data directory

## Adding to Marketplace

See [CONTRIBUTING.md](contributing.md) for how to add your plugin to the marketplace.

## Resources

- [Claude Code Plugin Documentation](https://code.claude.com/docs/en/plugins)
- [Marketplace Documentation](https://code.claude.com/docs/en/plugin-marketplaces)
