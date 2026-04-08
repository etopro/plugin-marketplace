#!/usr/bin/env bash
# Auto-detect available code formatters based on project configuration

detect_python_formatter() {
    if [ -f "pyproject.toml" ]; then
        if grep -q "\[tool\.ruff\]" pyproject.toml 2>/dev/null; then
            echo "ruff"
            return 0
        fi
        if grep -q "\[tool\.black\]" pyproject.toml 2>/dev/null; then
            echo "black"
            return 0
        fi
    fi

    if [ -f ".ruff.toml" ] || [ -f "ruff.toml" ]; then
        echo "ruff"
        return 0
    fi

    # Check if commands are available
    if command -v ruff &> /dev/null; then
        echo "ruff"
        return 0
    fi

    if command -v black &> /dev/null; then
        echo "black"
        return 0
    fi

    return 1
}

detect_js_formatter() {
    if [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ] || \
       [ -f ".prettierrc.js" ] || [ -f ".prettierrc.cjs" ] || \
       [ -f "prettier.config.js" ] || [ -f "prettier.config.cjs" ]; then
        echo "prettier"
        return 0
    fi

    if [ -f ".eslintrc" ] || [ -f ".eslintrc.json" ] || \
       [ -f ".eslintrc.js" ] || [ -f ".eslintrc.cjs" ] || \
       [ -f "eslint.config.js" ] || [ -f "eslint.config.mjs" ]; then
        echo "eslint"
        return 0
    fi

    if command -v prettier &> /dev/null; then
        echo "prettier"
        return 0
    fi

    if command -v eslint &> /dev/null; then
        echo "eslint"
        return 0
    fi

    return 1
}

# Main detection logic
detect_python_formatter || detect_js_formatter || echo "none"
