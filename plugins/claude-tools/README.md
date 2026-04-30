# claude-tools

A Claude Code plugin that keeps your 5-hour rate-limit window from starting at the worst possible moment. Installs a cron job that sends one token to Anthropic and refreshes the limit window.

> 🇷🇺 [Русская версия](README.ru.md)

---

## Why?

You open Claude Code at 10:00. Start working. By 12:00 the limit is gone — three hours of dead air in the middle of your workday. ENOUGH!!!

If you'd opened the session at 07:00 instead — the limit would have run out at 12:00 and a fresh 5-hour window would have started right away. From 06:00 to 16:00 you'd be working **across two windows back to back**. No downtime.

The window starts on your **first** request. Whoever pings first sets the rhythm.

The obvious fix — drop `claude -p "ping"` into cron every 5 hours and call it a day — but that's a half-measure. And not very vibe-coded:
- Power went out.
- Wi-Fi died.
- Laptop was asleep.
- Run it on your phone? Phones don't have signal everywhere either.
- Anthropic API blinks for 30 seconds — ping fails, next attempt in 5 hours.

Ladies and gentlemen, allow us to present our solution. With love, Claude Code 🩷

---

## What the plugin does

The plugin adds two cron jobs. The first one — the **watchdog** — runs every hour, looks at when you last pinged Claude, and does the math: the window lives 5 hours, so the next ping should land at such-and-such. The watchdog then schedules the second job — the **one-shot ping** — for that exact minute.

When the time comes, the one-shot ping wakes up, sends a single token to Claude, and refreshes the limit window. That's it.

What if **the power's out / network's down / laptop was asleep** at ping time? No worries. An hour later the watchdog wakes up, sees "hey, we missed the target" — and fires a catch-up ping right away. If that one also misses — there's a stubborn chain of 11 retries spread over 4 hours: first after 5 seconds, then 15, then once a minute, then once an hour. One of them will get through.

And one last safety net: if some ping gets stuck for good — its lock expires on its own after 4½ hours and doesn't block the next watchdog.

---

## Installation

```
/plugin marketplace add etopro/plugin-marketplace
/plugin install claude-tools@plugin-marketplace
/claude-tools:install
```

---

## License

[CC BY-NC 4.0](../../LICENSE) — Creative Commons Attribution-NonCommercial 4.0.

## Links

- [Claude Code documentation](https://code.claude.com)
- [Marketplace: etopro/plugin-marketplace](https://github.com/etopro/plugin-marketplace)
