# plugin-marketplace — working notes

Claude Code plugin marketplace. The manifest is `.claude-plugin/marketplace.json`.

## Version bumps for `url`-sourced plugins — read this first

Entries come in two kinds:

- **local** — `"source": "./plugins/foo"`. The manifest ships in the same commit,
  so the version cannot drift.
- **external** — `"source": {"source": "url", "url": "https://github.com/..."}`.
  Where the version comes from depends on the upstream repo layout.

**Resolution order (verified empirically 2026-07-19):** a `plugin.json` at the
**root** of the upstream repo wins. Only if there is none does `marketplace.json`
become authoritative.

That split decides whether a stale entry here is harmless or a real bug:

- **Upstream has a root `.claude-plugin/plugin.json`** → it overrides this file.
  A stale `version` here is cosmetic; installs still resolve correctly.
  (`skill-dokku` installed 1.1.3 while this file said 1.1.2.)
- **Upstream has no root manifest** — e.g. a monorepo keeping it at
  `plugins/<name>/.claude-plugin/plugin.json` — → **this file is authoritative.**
  A stale `version` resolves to what users already have, so
  `claude plugin install` reports *"already installed"* and silently skips. No
  error. The install record then claims a version the cached code does not
  contain, and users keep running stale code. This is what happened to
  `codex-fork`.

This has already happened more than once. Do not diagnose it from scratch again.

**When updating an external plugin, change BOTH:**
1. the upstream repo (its own `plugin.json`), and
2. the `version` field of that entry in `.claude-plugin/marketplace.json`.

Then verify:

```bash
node scripts/check-url-plugin-versions.mjs
```

Compares every `url`-sourced entry against its upstream `plugin.json`; exits
non-zero on drift. Also runs in CI as an advisory (non-blocking) step, because
it depends on third-party repos being reachable.

## Installing / reinstalling locally

This marketplace is registered as a `directory` source pointing at this working
copy, which has two consequences worth remembering:

- **It is read from the working tree on disk.** Commit entries on the branch you
  actually keep checked out (normally `main`) — committing to a feature branch
  makes the entry vanish when you switch away, breaking installed plugins.
- **`install` alone skips** when an install record already exists. The working
  sequence is:

  ```bash
  claude plugin marketplace update etopro-plugins
  claude plugin uninstall <plugin>@etopro-plugins
  claude plugin install <plugin>@etopro-plugins
  ```

- **Verify, do not trust the output.** "Successfully installed" is printed even
  when the cached code did not change. Check:
  - `~/.claude/plugins/installed_plugins.json` → expected `version` + `gitCommitSha`
  - `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` → grep for a file
    or symbol that only exists in the new version

## Conventions

- All repository content in English (see `docs/contributing.md`).
- Plugin names are kebab-case; CI enforces this.
- CI (`.github/workflows/validate.yml`) validates JSON, required files, manifests
  for local plugins, and (advisory) upstream version drift.
