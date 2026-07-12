---
name: pat
description: Issue a short-lived GitHub App installation token (replaces manual PATs) and optionally store it as a repo Actions secret
allowed-tools: Bash
---

# pat — GitHub App token, no manual PAT

`pat` mints a short-lived GitHub App **installation access token** (1 hour,
auto-rotated on each run) from a private key stored in Bitwarden, and optionally
stores it as a repository Actions secret. It replaces manually created PATs.

## How to handle the user's request

Run the subcommand the user asked for via the plugin script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pat.sh" <subcommand> [flags]
```

Subcommands:

- `install` — verify config, App reachability, Bitwarden item, and `gh`. Run this
  first after setup.
- `token` — print a fresh installation token to stdout (for piping / debugging).
- `grant --secret NAME --repo OWNER/REPO [--note TEXT]` — store a fresh token as a
  repo Actions secret. `--repo` defaults to the current git origin.

If Bitwarden is locked, `pat` prompts for the master password on the TTY.

### One-time setup (tell the user once, if they ask)

1. Create a GitHub App at github.com/settings/apps/new — repository permissions:
   **Contents = Read & write**, **Workflows = Read & write**; install on the account.
2. Download the private key `.pem`.
3. In Bitwarden, create a **secure note** (e.g. `github-app-axisrow`) with a custom
   text field named `private-key` holding the PEM body.
4. Write `~/.config/pat/config` (mode 0600):
   ```
   PAT_APP_ID=1234567
   PAT_BW_ITEM=github-app-axisrow
   ```
5. Run `pat install` — all checks should pass.

After setup, `pat grant --secret APP_TOKEN --repo axisrow/<any>` works for any repo
the App is installed on — no manual PAT ever again.
