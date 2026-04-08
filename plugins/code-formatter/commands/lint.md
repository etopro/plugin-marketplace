---
name: lint
description: Run linter checks to identify code quality issues
---

# Lint

Run linter checks to identify code quality issues without making changes.

## Supported Linters

- **ruff check** - Python linter
- **flake8** - Python linter
- **eslint** - JavaScript/TypeScript linter
- **pylint** - Python linter

## Usage

Run linter on the current project:
```
Lint all Python files in src/
```

Run linter with specific rules:
```
Run ruff check with select=E,W,F rules
```

## Examples

Lint specific directory:
```
Lint the src/ directory for Python issues
```

Check for specific error types:
```
Check for syntax errors and undefined names
```
