---
name: sliplane
description: "Manage the Sliplane platform for deploying Docker containers on Hetzner. Activate this skill when the user mentions Sliplane, wants to deploy a container on Hetzner, configure the Sliplane MCP server, get a Sliplane API token, manage services/servers via Sliplane, view logs or deployment status on Sliplane, restart a service on Sliplane, or work with deploy hooks. Also activate if the user asks about connecting Sliplane to Claude Code or an IDE."
user-invocable: true
argument-hint: "[command or question about Sliplane]"
---

# Sliplane — Container Deployment Management

Sliplane is a platform for simple and cost-effective deployment of Docker containers on Hetzner servers. It supports continuous deployment, automatic healthchecks, environment variable management, and SSH access.

## Step 1: Check MCP Server Connection

Before starting, verify that the Sliplane MCP server is connected. Check available tools — if tools with the `mcp__sliplane__` prefix are present, the server is already connected. Proceed to Step 3.

If Sliplane tools are not found — help the user set up the connection (Step 2).

## Step 2: Setup Connection

### Connecting the MCP Server

Run the command with placeholders instead of actual keys:

```bash
claude mcp add sliplane https://mcp.sliplane.io \
    -t http \
    -H "Authorization: Bearer YOUR_API_KEY_HERE" \
    -H "X-Team-Id: YOUR_TEAM_ID_HERE"
```

This will create the MCP server configuration. Never ask the user to send the API key in chat — this is insecure.

### Where to Insert the Real API Key

After running the command:

1. Get the key: Sliplane dashboard at **https://sliplane.io** (login via GitHub) → **Team Settings** → **API Keys** section (more details: https://docs.sliplane.io/mcp/getting-started)
2. On the same **Team Settings** page, find the **Team ID** (format `org_xxxxxxxxxxxx`) — displayed at the top of the page
3. Open the config file for editing:
   - **For user (all projects)**: `code ~/.claude.json`
   - **For current project**: `code .mcp.json`
4. Find the `mcpServers` → `sliplane` → `headers` section:
   - Replace `YOUR_API_KEY_HERE` with the real key
   - Replace `YOUR_TEAM_ID_HERE` with the real Team ID

**⚠️ Important: Authorization header format**

The value must be exactly `"Bearer <your-key>"` — with the `Bearer` prefix and a space before the key. Without this prefix the API will return a 401 error.

Example final configuration (`mcpServers` section):
```json
{
  "sliplane": {
    "type": "http",
    "url": "https://mcp.sliplane.io",
    "headers": {
      "Authorization": "Bearer api_rw_org_xxxxx_xxxxxxxxxxxxxx",
      "X-Team-Id": "org_xxxxx"
    }
  }
}
```

### Verifying the Connection

After replacing the key:

1. Ask the user to run `/clear` or restart the Claude Code session
2. Call `mcp__sliplane__listProjects` to verify the connection
3. If a 401 error is received — ask the user to check:
   - Is the `Bearer ` prefix (with a space) present before the key
   - Is the `X-Team-Id` header present with the correct Team ID
   - Does the value contain extra quotes or spaces
   - Is the key still valid (not revoked in the dashboard)

## MCP Error Handling

If one call returned 401 — do NOT touch the config files. First try another call to the same server (e.g. `listServers` or `listProjects`). Only if several different calls return 401 — then check the token configuration.

## Step 3: Working with Sliplane via MCP

After connecting the MCP server, use the available Sliplane tools to complete the user's tasks. The MCP server mirrors the capabilities of the Sliplane public API.

### Common Tasks

**Viewing information:**
- List projects and services
- Service and server status
- Server information (resources, region)

**Deployment and management:**
- Trigger a new deploy / redeploy of a service
- Manage environment variables
- Configure deploy rules (autodeploy, include/ignore paths)

**Monitoring:**
- View logs (runtime and build)
- Service events (deployments, healthchecks, domains, volumes)

### Alternative Management Methods

If MCP is unavailable or additional functionality is needed:

**Deploy Hook** — for triggering deploys programmatically:
```bash
curl "https://api.sliplane.io/deploy/<service-id>/<deploy-secret>?tag=<tag>"
```
Service ID and deploy secret can be found in the service settings in the Sliplane dashboard.

**SSH Access** — for direct server access:
```bash
ssh root@<your-subdomain>.sliplane.app -p 2222
```

**Port Forwarding** — for accessing private services:
```bash
ssh -L 8080:<your-app.internal>:<port> root@<your-subdomain>.sliplane.app -p 2222
```

**GitHub Actions** — for CI/CD:
```yaml
- name: Deploy to Sliplane
  run: |
    curl "https://api.sliplane.io/deploy/your-service-id/${{ secrets.DEPLOY_SECRET }}?tag=${{ github.sha }}"
```

## Important Notes

- Sliplane uses Docker containers — make sure the service has a Dockerfile or an image in a registry
- Each service can have one public port, defined via the `PORT` environment variable
- On a failed deployment, Sliplane automatically rolls back to the previous working version
- Private services (without expose) are accessible to other services on the same server via internal hostname
- Changing service settings automatically triggers a redeploy
