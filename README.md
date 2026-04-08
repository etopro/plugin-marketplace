# etopro-plugins

Community plugins for [Claude Code](https://code.claude.com) - development workflow utilities, formatters, and productivity tools.

## About

This marketplace distributes plugins for Claude Code, an agentic coding tool that lives in your terminal. Plugins include code formatters, git workflow automation, and deployment tools.

## Installation

Add this marketplace to Claude Code:

```bash
/plugin marketplace add etopro/etopro-plugins
```

Or use with the CLI:

```bash
claude plugin marketplace add etopro/etopro-plugins
```

## Available Plugins

### code-formatter

Universal code formatter and linter with support for ruff, black, prettier, eslint, and more.

**Commands:**
- `/formatter` - Auto-detect and run appropriate formatter
- `/lint` - Run linter checks
- `/check-format` - Verify formatting without making changes

**Install:**
```bash
/plugin install code-formatter@etopro-plugins
```

### git-workflow

Git workflow automation for commits, branches, and project management.

**Features:**
- Conventional commit message generation
- Branch naming conventions
- PR/workflow management guidance

**Install:**
```bash
/plugin install git-workflow@etopro-plugins
```

### dokku

Dokku deployment automation skill for managing apps and deployments.

**Install:**
```bash
/plugin install dokku@etopro-plugins
```

## Usage

After installing plugins, use them directly in Claude Code:

```
Use the formatter to format all Python files in src/
```

```
Help me write a conventional commit message for my changes
```

## Contributing

See [CONTRIBUTING.md](docs/contributing.md) for guidelines on contributing new plugins.

## License

This marketplace is licensed under [CC BY-NC 4.0](LICENSE) - Creative Commons Attribution-NonCommercial 4.0.

## Links

- [Plugin Development Guide](docs/plugin-development.md)
- [Claude Code Documentation](https://code.claude.com)
- [Report Issues](https://github.com/etopro/etopro-plugins/issues)
