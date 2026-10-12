---
name: lovable-emergent-migrator
description: Migrate a Lovable-built app into Emergent. Use when the user asks to move a Lovable project to Emergent, export a Lovable app off the platform, or prepare a Lovable GitHub repo for import into another AI builder. Covers the CLI prep script, the MCP server tools, and the web analyzer.
metadata:
  trigger: lovable to emergent, migrate lovable app, emergent import, lovable export
---

# Lovable → Emergent Migrator

Move a working Lovable app into Emergent with minimal rebuild, starting from the
app's Lovable-synced GitHub repository.

## Tool locations

| Route | Path | When to use |
|---|---|---|
| CLI script | ``migrate-to-emergent.sh` (repo root)` | Full local run: clones, inventories, sanitizes, writes `EMERGENT.md`, pushes an `emergent-import` branch. Best for private repos and repos you can `git clone`. |
| MCP server | ``mcp/server.js`` | Agent-driven: `analyze_repo` and `generate_migration_pack` tools over stdio. Run with `node server.js`; needs `npm install` in `mcp/` first. |
| Web app | https://lovable-emergent-migrator.space.fast/ (source: `web/index.html`) | Public repos, analyzed 100% client-side via GitHub API. Hand the user the link for self-serve. |

## Platform facts (verified 2026-10-12 — do not re-derive from memory)

- Lovable exports via **Git sync** (project Settings → Git → Connect GitHub; works on the
  free plan; two-way). Lovable creates a **fresh** repo — it cannot point at an existing one.
- The export contains: React source, `package.json`, `supabase/` (`migrations/`, `functions/`,
  `config.toml` with the project ref). It contains **zero data rows, no Storage files, no secrets**.
- **Emergent has no import API and no deep link.** Import is UI-only: profile icon →
  Connect GitHub → new task → GitHub button in chat → Pull from GitHub → pick repo + branch.
  (Corroborated via Firecrawl Alexandria `firecrawl-developer-index/search`, 2026-10-12.)
- Emergent's native stack is FastAPI + MongoDB; Lovable apps are Vite + React + Supabase.

## Workflow

### 1. Export from Lovable (user does this, ~5 min)
Settings → Git → Connect GitHub. Confirm the repo has the latest code and `supabase/` if the
app has a backend. If the user hasn't done this yet, say so and stop — nothing downstream
works without the synced repo.

### 2. Prepare the repo
**CLI route** (preferred when you have git access):
```bash
`migrate-to-emergent.sh` (repo root) --repo <git-url> [--branch emergent-import] [--push]
```
The script clones, inventories (deps, Supabase pieces, env var names, secret scan),
removes `.lovable/`, tightens `.gitignore`, merges `.env.example` (names only, never
clobbers existing entries), flags tracked `.env` files, writes a paste-ready `EMERGENT.md`,
and commits to `emergent-import` (pushes with `--push`). Review its secret-scan hits
before pushing.

**MCP route** (when acting as an agent tool): call `analyze_repo`, then
`generate_migration_pack`. Same inventory logic as the script; returns the prompt,
`.env.example`, checklist, and warnings as JSON.

### 3. Backend decision (the one judgment call — surface it, don't guess)
- **Keep Supabase (default):** Supabase stays the database/auth/backend. The user supplies
  `SUPABASE_URL` + anon key (service-role only if edge functions need it) in Emergent's
  secret store. Frontend barely changes.
- **Rebuild on Emergent's stack:** full port to FastAPI + MongoDB. Only if the user wants
  to leave Supabase entirely.
- **Data & Storage:** rows and bucket files do NOT travel. Decide: point at the **existing**
  Supabase project (fastest) or a fresh one (apply migrations first, then migrate data via
  `supabase db dump` / Storage copy).

### 4. Pull into Emergent (user does this in the UI — no API exists)
1. Emergent → profile icon → Connect GitHub → authorize.
2. New task → GitHub button → Pull from GitHub → repo + `emergent-import` branch.
3. Paste `EMERGENT.md` as the first prompt to the agent.
4. Hand over Supabase URL + keys when asked (in Emergent's secret store, never as committed code).

### 5. Verify (acceptance checklist)
`npm install` + build succeed · app boots against the chosen Supabase project · auth works ·
one real data round-trip (list + write) · edge functions respond or are flagged unportable ·
no secrets committed · Lovable project stays alive until Emergent is the source of truth.

## Guardrails
- Never commit real secret values. `.env.example` carries names only.
- Never invent a backend. If no `supabase/` dir exists, ask where the backend lives.
- Do not "rebuild it in Emergent's native stack" unasked — adapt, don't rewrite.
- The `emergent-import` branch is script-managed; if a push is rejected as non-fast-forward,
  tell the user to delete the remote branch first (`git push origin --delete emergent-import`)
  rather than force-pushing blindly.
- Stress-test history (2026-10-12): the CLI script was hardened against `set -o pipefail`
  kills on repos without `supabase/` or `index.html`, `.env.example` clobbering, and
  non-idempotent re-runs. Re-run the fixture checks in `SCOPE.md` if you change the script.
