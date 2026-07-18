# Contributing to plugin-marketplace

Thank you for your interest in contributing! This guide covers how to contribute plugins to the plugin-marketplace.

## Language Requirement

**All content must be in English.** This includes:
- Plugin descriptions and documentation
- Code comments and commit messages
- Skill/command content
- Pull request titles and descriptions
- Issue reports and discussions

This ensures the marketplace remains accessible to the global community.

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

### Valid Categories

Choose one of the following categories for your plugin:
- `code-quality` - formatters, linters, code analysis
- `deployment` - deployment tools, CI/CD, DevOps
- `utilities` - helper tools, utilities
- `workflow` - automation, git, project management

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
  "description": "Clear description (under 100 characters)",
  "version": "1.0.0",
  "author": {
    "name": "Your Name"
  },
  "homepage": "https://github.com/yourusername/your-plugin",
  "repository": "https://github.com/yourusername/your-plugin",
  "keywords": ["keyword1", "keyword2"],
  "category": "category-name",
  "tags": ["tag1", "tag2"]
}
```

**Note:** `description` must be **under 100 characters** for marketplace display. All contributions are licensed under the same license as the plugin-marketplace project.

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

## Security Guidelines

- **No hardcoded secrets** - API keys, tokens, or credentials
- **No telemetry or tracking** - respect user privacy
- **Declare external dependencies** - list any CLI tools or services required
- **Safe command execution** - validate user input, avoid shell injection

## Pull Request Process

1. Fork the repository
2. Create a branch: `git checkout -b plugin/your-plugin` or `feature/your-feature`
3. Add your plugin to `plugins/`
4. Update `.claude-plugin/marketplace.json` with your plugin entry
5. Test locally
6. Submit a pull request with title format: `plugin/your-plugin: Brief description`

### PR Checklist

- [ ] Plugin name is kebab-case
- [ ] `plugin.json` exists with required fields
- [ ] At least one component (command/skill/agent) is included
- [ ] Plugin tested locally
- [ ] `marketplace.json` updated with plugin entry
- [ ] No placeholder content or TODO comments
- [ ] All content is in English
- [ ] Description is under 100 characters
- [ ] No hardcoded secrets or credentials
- [ ] External dependencies declared

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

### External plugins (`url` source)

A plugin hosted in its own repository is registered with a `url` source instead
of a local path:

```json
{
  "name": "your-plugin",
  "source": {
    "source": "url",
    "url": "https://github.com/you/your-plugin.git"
  },
  "version": "1.2.3"
}
```

**When you bump the upstream repo, you MUST bump `version` here too.**

Claude Code resolves the version of a `url`-sourced plugin from **this
marketplace.json**, not from the upstream repository. If the two disagree, the
resolved version still matches what users already have installed, so
`claude plugin install` reports *"already installed"* and skips the update.
There is no error message — users simply keep running stale code, and the
install record will claim a version that the cached code does not actually
contain.

Bumping the upstream repo alone is therefore **not enough**. Both must change.

Verify before committing:

```bash
node scripts/check-url-plugin-versions.mjs
```

This compares every `url`-sourced entry against its upstream `plugin.json` and
exits non-zero on a mismatch. It also runs in CI (advisory only, since it
depends on third-party repos being reachable).

Two notes on installing a local marketplace:

- A `directory`-source marketplace is read from the **working tree on disk**, so
  entries must be committed on the branch you actually have checked out —
  otherwise the entry disappears when you switch branches.
- After bumping, `install` alone still skips because the install record already
  exists. Run `claude plugin uninstall <plugin>@<marketplace>` first, then
  `install` — and verify the result in
  `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` rather than
  trusting the "Successfully installed" line.

## Code Style

- Write clear, concise documentation
- Use examples in command/skill descriptions
- Follow existing formatting conventions
- Include helpful error messages

## Getting Help

- Open an issue for questions
- Check existing plugins for examples
- Review [plugin development guide](plugin-development.md)
