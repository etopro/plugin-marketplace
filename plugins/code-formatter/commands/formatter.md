---
name: formatter
description: Auto-detect and run appropriate code formatter (ruff, black, prettier, eslint)
---

# Code Formatter

Automatically detects and runs the appropriate code formatter for your project.

## Supported Formatters

- **ruff** - Python formatter and linter
- **black** - Python code formatter
- **prettier** - JavaScript/TypeScript/HTML/CSS/JSON formatter
- **eslint** --fix - JavaScript/TypeScript linter with auto-fix

## Usage

The formatter automatically detects which formatter to use based on your project configuration:

- `pyproject.toml` with `[tool.ruff]` → uses ruff
- `pyproject.toml` with `[tool.black]` → uses black
- `.prettierrc*` or `prettier.config.*` → uses prettier
- `.eslintrc*` or `eslint.config.*` → uses eslint --fix

## Examples

Format all files in the current directory:
```
Use the formatter to format all Python files in src/
```

Format specific files:
```
Format src/main.py and src/utils.py
```

## Detection Script

The formatter uses the `detect.sh` script to identify available formatters.
