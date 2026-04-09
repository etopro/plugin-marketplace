# Contributing to etopro-plugins

Thank you for your interest in contributing! This guide covers how to contribute plugins to the etopro-plugins marketplace.

## Plugin Requirements

### Naming Conventions

- Plugin names must be **kebab-case** (lowercase letters, digits, hyphens only)
- Use descriptive, concise names
- Avoid generic names like "helper" or "utils"

**Good examples:**
- `code-formatter`
- `git-workflow`
- `docker-deploy`

**Bad examples:**
- `CodeFormatter` (not kebab-case)
- `helper` (too generic)
- `my_plugin` (underscore not allowed)

### Required Files

Each plugin must include:

1. **`.claude-plugin/plugin.json`** - Plugin manifest with:
   - `name` - Plugin identifier (kebab-case)
   - `description` - Brief description
   - `version` - Semver version string
   - `author` - Author information with `name` field

2. **Component files** - At least one of:
   - `commands/` - Directory containing `.md` command files
   - `skills/` - Directory containing `.md` skill files
   - `agents/` - Directory containing `.md` agent files
   - `hooks/hooks.json` - Hooks configuration

### Plugin Structure

```
plugins/your-plugin/
├── .claude-plugin/
│   └── plugin.json          # Required: plugin manifest
├── commands/                # Optional: command files
│   └── your-command.md
├── skills/                  # Optional: skill files
│   └── your-skill.md
└── scripts/                 # Optional: helper scripts
    └── helper.sh
```

### Metadata Requirements

Include these optional but recommended fields in your plugin:

```json
{
  "name": "your-plugin",
  "description": "Clear description of what the plugin does",
  "version": "1.0.0",
  "author": {
    "name": "Your Name"
  },
  "license": "CC-BY-NC-4.0",
  "homepage": "https://github.com/etopro/your-plugin",
  "repository": "https://github.com/etopro/your-plugin",
  "keywords": ["keyword1", "keyword2"],
  "category": "category-name",
  "tags": ["tag1", "tag2"]
}
```

## Testing Requirements

Before submitting, test your plugin locally:

1. **Add the marketplace locally:**
   ```bash
   /plugin marketplace add /path/to/plugin-marketplace
   ```

2. **Install your plugin:**
   ```bash
   /plugin install your-plugin@plugin-marketplace
   ```

3. **Test each command/skill:**
   ```
   Use your-plugin command
   ```

4. **Validate the plugin:**
   ```bash
   claude plugin validate plugins/your-plugin
   ```

## Pull Request Process

1. Fork the repository
2. Create a branch: `git checkout -b feature/your-plugin`
3. Add your plugin to `plugins/`
4. Update `.claude-plugin/marketplace.json` with your plugin entry
5. Test locally
6. Submit a pull request

### PR Checklist

- [ ] Plugin name is kebab-case
- [ ] `plugin.json` exists with required fields
- [ ] At least one component (command/skill/agent) is included
- [ ] Plugin tested locally
- [ ] `marketplace.json` updated with plugin entry
- [ ] No placeholder content or TODO comments

## Marketplace Entry

Add your plugin to `.claude-plugin/marketplace.json`:

```json
{
  "name": "your-plugin",
  "source": "your-plugin",
  "description": "Brief description",
  "version": "1.0.0",
  "author": {
    "name": "Your Name"
  },
  "category": "category-name",
  "tags": ["tag1", "tag2"],
  "keywords": ["keyword1", "keyword2"]
}
```

## Code Style

- Write clear, concise documentation
- Use examples in command/skill descriptions
- Follow existing formatting conventions
- Include helpful error messages

## Getting Help

- Open an issue for questions
- Check existing plugins for examples
- Review [plugin development guide](plugin-development.md)
