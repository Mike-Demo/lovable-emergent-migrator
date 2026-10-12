# lovable-emergent-migrator — MCP server

MCP (stdio) wrapper around the Lovable → Emergent migration analyzer.
Same inventory logic as the web app and CLI script, exposed as agent tools.

## Tools

| Tool | What it returns |
|---|---|
| `analyze_repo` | JSON inventory: name, framework, key deps, scripts, Supabase (migrations, edge functions), env vars referenced in code, tracked `.env` files, secret-pattern hits, `.lovable` artifacts, files scanned |
| `generate_migration_pack` | Everything above plus: `EMERGENT.md` (paste-ready prompt for Emergent's agent — keeps Supabase as backend when detected), `.env.example`, the 12-item acceptance checklist, warnings, and the Emergent UI next-steps |

Both take:

```json
{
  "repo_url": "https://github.com/owner/repo",
  "github_token": "ghp_… (optional)",
  "ref": "main (optional — branch, tag, or SHA)"
}
```

Auth: pass `github_token` per call, or set the `GITHUB_TOKEN` env var. Required for
private repos; also raises the GitHub rate limit above the unauthenticated 60 req/hr.
The analyzer scans at most 40 source files in batches of 5.

## Run it

```bash
cd ~/workspace/lovable-to-emergent/mcp
npm install          # once — installs @modelcontextprotocol/sdk
node server.js       # stdio MCP server
```

## Connect it

**Claude Code** (`~/.claude.json` or project `.mcp.json`):

```json
{
  "mcpServers": {
    "lovable-emergent-migrator": {
      "command": "node",
      "args": ["/home/hatch/workspace/lovable-to-emergent/mcp/server.js"],
      "env": { "GITHUB_TOKEN": "ghp_…" }
    }
  }
}
```

**Codex** (`~/.codex/config.toml`):

```toml
[mcp_servers.lovable-emergent-migrator]
command = "node"
args = ["/home/hatch/workspace/lovable-to-emergent/mcp/server.js"]
env = { GITHUB_TOKEN = "ghp_…" }
```

Omit `env` entirely for public-repos-only use.

## Quick stdio smoke test

```bash
printf '%s\n' \
'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
'{"jsonrpc":"2.0","method":"notifications/initialized"}' \
'{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"analyze_repo","arguments":{"repo_url":"https://github.com/vitejs/vite-plugin-react"}}}' \
| node server.js
```

## Notes

- The MCP server, the web app (`../web/index.html`), and the CLI script
  (`../migrate-to-emergent.sh`) share the same analysis semantics; the skill
  (`~/workspace/skills/lovable-emergent-migrator/SKILL.md`) documents the full workflow.
- Only public GitHub data is read, and only via `api.github.com`. Tokens are never
  logged or persisted by the server.
