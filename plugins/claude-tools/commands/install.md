---
name: install
description: Install controller cron that schedules Claude Code pings at window + 20s
allowed-tools: Bash
---

# Install claude-tools cron

Install an hourly controller cron entry. The controller uses the existing
limit-window state logic to create or refresh a separate scheduled ping entry
for the current window time + 20 seconds.

## How to handle the user's request

Run the installer and surface the output:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh"
```

Then briefly explain what was set up:

- One crontab entry, schedule `0 * * * *`.
- A second scheduled ping entry is created when the controller knows the current window.
- Scheduled ping uses cron minute precision plus `sleep` to hit the target second.
- State file at `~/.claude/claude-tools/state.json`, log at `~/.claude/claude-tools/ping.log`.
- Re-running `/claude-tools:install` is idempotent.
- `/claude-tools:status` shows controller, scheduled ping, current state, and recent log.
- `/claude-tools:uninstall` removes both cron entries.
