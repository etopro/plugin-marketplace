---
name: check-format
description: Verify code formatting without making changes (dry-run)
---

# Check Format

Verify that code is properly formatted without making any changes. Useful for CI/CD pipelines.

## Supported Formatters

- **ruff format --check** - Python format checking
- **black --check** - Python format checking
- **prettier --check** - Multi-language format checking
- **eslint** - JS/TS linting without auto-fix

## Usage

Check if files are properly formatted:
```
Check if all Python files in src/ are formatted
```

Check specific files:
```
Check formatting of src/main.py without making changes
```

## Exit Codes

- **0** - All files are properly formatted
- **1** - Some files need formatting

## Examples

CI/CD check:
```
Run format check on all files, fail if any need formatting
```

Specific directory:
```
Check if the tests/ directory is properly formatted
```
