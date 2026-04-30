---
name: uninstall
description: Remove claude-tools controller and scheduled ping cron jobs
allowed-tools: Bash
---

# Uninstall claude-tools cron

Remove the crontab entries installed by `/claude-tools:install`.

## How to handle the user's request

Run the uninstaller and report the result:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall.sh"
```

The script:
- removes everything between `# claude-tools-marketplace BEGIN` and `# claude-tools-marketplace END` markers,
- removes controller and scheduled ping marker blocks,
- if the crontab is empty afterwards, runs `crontab -r`,
- prints a short confirmation.

Show the stdout to the user. The log file at `~/.claude/claude-tools/ping.log` is intentionally **not** deleted, so the user can inspect history. Mention that they can `rm` it manually if they want.
