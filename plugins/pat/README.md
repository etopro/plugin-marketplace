# pat

A Claude Code plugin that **kills the worst GitHub chore**: creating a Personal Access Token by hand on github.com/settings/tokens every time a new project needs cross-repo access from Actions.

`pat` mints a short-lived GitHub App **installation access token** (1 hour, fresh on every run) from a private key stored in **Bitwarden**, and optionally stores it as a repository Actions secret.

```
pat grant --secret APP_TOKEN --repo axisrow/profile
```

Because the GitHub App is installed on your whole account, **every new repo is covered with zero extra steps** — no more opening the token page, no more expiring PATs.

## How it works

```
Bitwarden (PEM) → RS256 JWT (openssl) → POST /app/installations/<id>/access_tokens → token (1h) → gh secret set
```

The private key lives only in Bitwarden, never on disk.

## One-time setup (~3 min)

1. **Create a GitHub App** at github.com/settings/apps/new:
   - Name: anything (e.g. `my-ci`)
   - Homepage URL: `https://github.com/<you>` (required, placeholder ok)
   - Webhook: **uncheck Active** (not needed — `pat` uses the REST API only)
   - Repository permissions: **Contents = Read & write**, **Workflows = Read & write**
   - Install on your account → **All repositories**
2. On the App page, note the **App ID** and **Generate a private key** (downloads a `.pem`).
3. **Bitwarden**: create a secure note (e.g. `github-app-my-ci`) with a custom text field named `private-key` holding the PEM body.
4. Write `~/.config/pat/config` (mode 0600):
   ```
   PAT_APP_ID=1234567
   PAT_BW_ITEM=github-app-my-ci
   ```
5. `pat install` → all ✓.

After that, `pat grant --secret X --repo owner/any` works for any repo the App is installed on.

## Subcommands

| Command | What it does |
|---|---|
| `pat install` | Verify config, App reachability, Bitwarden item, and `gh`. |
| `pat token` | Print a fresh installation token to stdout (for piping / debugging). |
| `pat grant --secret NAME --repo OWNER/REPO [--note TEXT]` | Store a fresh token as a repo Actions secret. `--repo` defaults to the current git origin. |

If Bitwarden is locked, `pat` prompts for the master password on the TTY.

## Install

```
/plugin marketplace add etopro/plugin-marketplace
/plugin install pat@etopro-plugins
/pat:pat            # slash command, or invoke scripts/pat.sh directly
```

## License

[CC BY-NC 4.0](../../LICENSE).
