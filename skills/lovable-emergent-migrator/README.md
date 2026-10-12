# lovable-emergent-migrator — skill pack

A fully self-contained skill pack. Everything an agent (or human) needs to migrate a
Lovable-built app into Emergent ships in this directory — no other installs required
beyond the standard `bash`/`git` (CLI) or `node` (MCP server).

## Install

```bash
./install.sh                  # auto-detects ~/.claude/skills or ~/workspace/skills
./install.sh --target DIR     # install into DIR/lovable-emergent-migrator
```

Then optionally set up the MCP server:

```bash
cd <installed>/mcp && npm install
```

## Layout

```
lovable-emergent-migrator/
  SKILL.md                  agent playbook (read by the agent)
  install.sh                one-command installer
  scripts/migrate-to-emergent.sh   CLI prep script (bash + git)
  mcp/server.js, analyze.js MCP server — tools: analyze_repo, generate_migration_pack
  mcp/package.json, README.md
  web/index.html            self-contained web analyzer (no build step)
```

## Verify the install

```bash
bash -n <installed>/scripts/migrate-to-emergent.sh && echo "CLI OK"
node --check <installed>/mcp/server.js && echo "MCP OK"
```

## Source

Built from https://github.com/Mike-Demo/lovable-emergent-migrator — the repo carries
the full project (live web demo, scope docs, research notes).
