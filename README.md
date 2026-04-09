# etopro-plugins

Community plugins for [Claude Code](https://code.claude.com) - development workflow utilities, formatters, and productivity tools.

## About

This marketplace distributes plugins for Claude Code, an agentic coding tool that lives in your terminal. Plugins include code formatters, git workflow automation, and deployment tools.

## Installation

Add this marketplace to Claude Code:

```bash
/plugin marketplace add etopro/plugin-marketplace
```

Or use with the CLI:

```bash
claude plugin marketplace add etopro/plugin-marketplace
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
/plugin install code-formatter@plugin-marketplace
```

### git-workflow

Git workflow automation for commits, branches, and project management.

**Features:**
- Conventional commit message generation
- Branch naming conventions
- PR/workflow management guidance

**Install:**
```bash
/plugin install git-workflow@plugin-marketplace
```

### dokku-manage

Dokku deployment automation skill for managing apps and deployments on Linux VMs.

**Install:**
```bash
/plugin install dokku-manage@plugin-marketplace
```

### skill-email-otp

Python CLI tool and skill for creating temporary email addresses and automatically extracting OTP codes and validation links from incoming emails.

**Install:**
```bash
/plugin install skill-email-otp@plugin-marketplace
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
- [Report Issues](https://github.com/etopro/plugin-marketplace/issues)
