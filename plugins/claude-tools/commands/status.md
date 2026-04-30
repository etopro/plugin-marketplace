---
name: status
description: Show claude-tools controller, scheduled ping, current window, and log
allowed-tools: Bash
---

# claude-tools status

Run the status script and pass its output to the user:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh"
```

The output shows:
- Whether the controller and scheduled ping cron entries are installed.
- Last successful ping timestamp and how long ago.
- Predicted decision if cron fired right now (PING / SKIP with reason).
- Next target ping time, when state is available.
- Current 5h window expiration estimate.
- Tail of `ping.log`.

If the user asks how scheduling works, summarize: the hourly controller uses
the existing window decision/state logic and keeps a scheduled ping at the
window plus 20 seconds; missed targets are retried quickly, then hourly by the controller.
