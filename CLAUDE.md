# plugin-marketplace — working notes

Claude Code plugin marketplace. The manifest is `.claude-plugin/marketplace.json`.

## Version bumps for `url`-sourced plugins — read this first

Entries come in two kinds:

- **local** — `"source": "./plugins/foo"`. The manifest ships in the same commit,
  so the version cannot drift.
- **external** — `"source": {"source": "url", "url": "https://github.com/..."}`.
  The version is resolved from **this marketplace.json**, NOT from the upstream repo.

**Bumping the upstream repository is not enough.** If `marketplace.json` still
declares the old version, Claude Code resolves it to the version users already
have installed, so `claude plugin install` reports *"already installed"* and
silently skips. No error is printed. The install record then claims a version
that the cached code does not contain, and users keep running stale code.

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
