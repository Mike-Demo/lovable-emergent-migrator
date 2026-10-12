# Lovable → Emergent Migrator

Move a working [Lovable](https://lovable.dev) app into [Emergent](https://emergent.sh)
with minimal rebuild — starting from the GitHub repo Lovable synced your project to.

**Live demo:** https://lovable-emergent-migrator.space.fast/

## The 60-second version

1. In Lovable: **Settings → Git → Connect GitHub** (Lovable creates a fresh repo, two-way sync).
2. Paste that repo URL into the [web app](https://lovable-emergent-migrator.space.fast/) — or run
   `./migrate-to-emergent.sh --repo <url> --push`.
3. You get a full inventory, a paste-ready **`EMERGENT.md` prompt**, a `.env.example`, and a checklist.
4. In Emergent: Connect GitHub → new task → **Pull from GitHub** → paste the prompt as your
   first message. (Emergent has no import API — the pull is UI-only.)

## Four ways to use it

| Route | Path | Best for |
|---|---|---|
| 🌐 Web app | `web/index.html` · [live](https://lovable-emergent-migrator.space.fast/) | Public repos. 100% client-side: paste a URL, get the migration pack in-browser. |
| 🛠 CLI script | `migrate-to-emergent.sh` | Private repos / full local runs. Clones, inventories, sanitizes (drops `.lovable/`, merges `.env.example`, scans for secrets), writes `EMERGENT.md`, pushes an `emergent-import` branch. |
| 🤖 MCP server | `mcp/` | Agents. Tools `analyze_repo` + `generate_migration_pack` over stdio. See `mcp/README.md` for Claude Code / Codex config. |
| 🧠 Skill | `skills/lovable-emergent-migrator/` | Agent playbook: the whole workflow, the backend decision, guardrails. Installable via `npx skills add Mike-Demo/lovable-emergent-migrator`. |

## Key facts (verified 2026-10-12)

- A Lovable export contains your React source, `package.json`, and `supabase/` (migrations,
  edge functions, `config.toml`) — but **zero data rows, no Storage files, no secrets**.
- Emergent's native stack is FastAPI + MongoDB, but your Lovable app speaks Supabase.
  The generated prompt **keeps Supabase as the backend** — the lowest-risk path — and tells
  Emergent's agent exactly how to re-wire it.
- Import is UI-only: there is no Emergent import API or deep link, so the script automates
  everything up to the click.

## Install the skill

```bash
npx skills add Mike-Demo/lovable-emergent-migrator
```

Or clone and run the bundled installer:

```bash
git clone https://github.com/Mike-Demo/lovable-emergent-migrator.git
cd lovable-emergent-migrator/skills/lovable-emergent-migrator
./install.sh
```

## Quickstart (CLI)

```bash
./migrate-to-emergent.sh --repo git@github.com:you/your-lovable-app.git --push
# → inventory report, EMERGENT.md, .env.example, emergent-import branch
```

## Quickstart (MCP)

```bash
cd mcp && npm install && node server.js   # stdio
```

```json
// .mcp.json (Claude Code)
{ "mcpServers": { "lovable-emergent-migrator": {
  "command": "node", "args": ["/path/to/mcp/server.js"],
  "env": { "GITHUB_TOKEN": "ghp_…" } } } }
```

## Scope & research notes

See [`SCOPE.md`](SCOPE.md) for the full migration scope: phases, the backend decision,
acceptance checklist, risks, and the research trail (including the Firecrawl Alexandria
developer-index findings and the GitHub search confirming no prior migration tooling exists).

## License

MIT
