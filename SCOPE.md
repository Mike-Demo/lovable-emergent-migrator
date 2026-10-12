# Lovable → Emergent migration scope

Goal: move a working Lovable app into Emergent with minimal rebuild, starting from the
app's Lovable-synced GitHub repository.

**Key platform facts (verified 2026-10-12):**
- Lovable exports via **Git sync** (Project settings → Git → Connect GitHub, works on the
  free plan, two-way sync). The repo contains: React source, `package.json`, and `supabase/`
  (SQL `migrations/`, edge `functions/`, `config.toml` with the project ref). It contains
  **zero data rows, no Storage files**, and no `.env` values.
- Emergent has **no import API and no deep link** — import is UI-only: profile icon →
  Connect GitHub → new task → GitHub button in chat → Pull from GitHub → select repo +
  branch. (Source: EMERGENT.md guide verified against Emergent's docs 2026-08-19.)
- Emergent's native stack is FastAPI + MongoDB; Lovable apps are Vite + React + Supabase.
  The migration therefore needs an explicit **backend decision** (see Phase 2).

**Alexandria evidence (Firecrawl Developer category, retrieved 2026-10-12):**
- `firecrawl-developer-index/search` (2 credits, 10 records, upstream 200, no per-result
  errors): confirms **Emergent supports importing an existing GitHub repository**
  ([mastra.ai vibe-coding-platforms](https://mastra.ai/articles/vibe-coding-platforms):
  "Need to import an existing repository? Emergent, Bolt, Replit, and v0 support that
  workflow"); confirms the Lovable→repo→import pattern is the standard cross-builder path
  ([Replit import docs](https://docs.replit.com/replit-app/import-to-replit.md):
  "Export your Lovable project to GitHub... Connect your GitHub account... Select your
  new Lovable project repo for import"; imports code, design, assets, backend, DB schema;
  does **not** import Supabase data or secrets). [Zeabur's Lovable import guide](https://zeabur.com/docs/en-US/get-started/migration/lovable)
  follows the same shape: Sync Lovable to GitHub → set up local dev → verify
  dependencies and environment → deploy.
- `github-com/repositories/search_repos` (3 calls × 5 credits; upstream 200 each): **no
  dedicated Lovable→Emergent migration tooling exists on GitHub** — "emergent import
  lovable migration guide" and "emergent.sh pull from github import" returned 0 repos;
  "lovable emergent" (22 total) matched only clones of the builders themselves
  (micracode, supergent, forge, VibeEngine-Local, etc.), none of which is a migration
  tool. Gap confirmed: the script in this folder is the tooling for this job.
- Providers `hub-docker-com`, `nvd-nist-gov`, `osv-dev`, `package-registry-metadata-download-stats`
  surfaced in the Developer category but offer **no migration-relevant capability**
  (container registry, CVE database, vulnerability data, package metadata) — none were
  invoked; Alexandria discovery across 4 free queries never matched them to this task.
- Total Alexandria spend for this research: **17 credits** (all discovery free).

## Phase 0 — Export from Lovable (manual, ~5 min)
1. In the Lovable project: Settings → Git → Connect GitHub. Lovable creates a fresh repo
   (it cannot point at an existing one) and starts two-way sync.
2. Verify the repo has the latest code and `supabase/` is present.

## Phase 1 — Prepare the repo (script, automated)
Run `migrate-to-emergent.sh --repo <git-url> [--push]`:
1. Clones the repo and inventories it: framework/deps, Supabase migrations + functions,
   env vars referenced in code (names only), `.lovable/` artifacts, committed-secret scan.
2. Sanitizes: removes `.lovable/`, tightens `.gitignore` (`.env*`, `node_modules`, `dist`),
   generates `.env.example` from vars actually used in code — **no values, no secrets**.
3. Generates `EMERGENT.md`: a paste-ready prompt describing the app, the backend wiring,
   and guardrails for Emergent's agent.
4. Commits to an `emergent-import` branch (optionally pushes it).

## Phase 2 — Backend decision (the one real judgment call)
- **Option A — Keep Supabase (recommended for most Lovable apps):** Supabase stays the
  database/auth/backend. In Emergent, supply `SUPABASE_URL` + anon key (service-role only
  if edge functions need it). The frontend code barely changes.
- **Option B — Rebuild on Emergent's native stack:** full port of schema, RLS, and edge
  functions to FastAPI + MongoDB. Only worth it if you want to leave Supabase entirely.
- **Data & Storage:** Lovable exports carry no rows and no uploaded files. Decide before
  import: point at the **existing** Supabase project (fastest), or spin up a fresh one,
  apply the migrations, and migrate data (`supabase db dump` / Storage bucket copy).

## Phase 3 — Pull into Emergent (manual UI, ~5 min)
1. Emergent → profile icon → Connect GitHub → authorize, grant the repo.
2. New task → GitHub button in chat → Pull from GitHub → repo + `emergent-import` branch.
3. Paste the contents of `EMERGENT.md` as the first prompt to the agent.
4. Hand it the Supabase URL + anon key when asked; answer existing-vs-fresh project.

## Phase 4 — Verify in Emergent (acceptance checklist)
- [ ] `npm install` + `npm run build` succeed with no behavior changes
- [ ] App boots against the chosen Supabase project
- [ ] Auth flow works (sign in / sign out)
- [ ] At least one real data query round-trips (list + write)
- [ ] Edge functions called by the UI respond (or are explicitly flagged if unportable)
- [ ] No secret values committed; Emergent's secret store holds the keys
- [ ] Preview link shared; Lovable project kept alive until Emergent is the source of truth

## Risks & limits
- **No API-driven import:** the Pull is manual; the script automates everything up to it.
- **Secret hygiene:** review the script's secret-scan hits before pushing the branch.
- **Lovable Cloud apps:** if the app used Lovable Cloud rather than a connected Supabase
  project, the backend ref lives in Lovable's infra — inventory will show no `supabase/`
  dir; treat as a custom-backend case and plan data export separately.
- **Divergence:** after import, two-way sync back to Lovable is possible (the repo is the
  shared source), but Emergent-side adaptations should be reviewed before re-syncing.
- **Emergent credits:** importing and adapting a medium app consumes meaningful agent
  credits; confirm your plan's allowance before starting Phase 3.

## Deliverables
- `migrate-to-emergent.sh` — the preparation script (stress-tested 2026-10-12: 6 bugs found
  and fixed across 5 fixture repos — pipefail kills on missing `supabase/`/`index.html`,
  `.env.example` clobbering, untracked `.env` not flagged, hardcoded Supabase claim for
  frontend-only apps, non-idempotent re-runs, unclear push-conflict errors)
- `EMERGENT.md` — generated per-app import prompt (created by the script)
- `<name>-inventory.txt` — per-app inventory report (created by the script)
- **Web app (live): https://lovable-emergent-migrator.space.fast/** — single-file,
  client-side-only migration helper. Paste a public Lovable-synced repo URL → it
  inventories the repo via GitHub's API (package.json, file tree, up to 40 source files
  scanned for env vars + secret patterns, Supabase detection) and generates the migration
  pack in-browser: EMERGENT.md prompt (copy/download), .env.example (copy/download),
  interactive acceptance checklist (localStorage per repo), and the Emergent UI steps.
  Private repos fall back to the downloadable CLI script. Source: `web/index.html`.
  Interview-ready demo.
- **MCP server: `mcp/server.js`** (stdio, `@modelcontextprotocol/sdk`) — tools
  `analyze_repo` and `generate_migration_pack`, same analysis semantics as the web app
  and CLI. Tested over real JSON-RPC against vitejs/vite-plugin-react. Install:
  `npm install` in `mcp/`, run `node server.js`; token via per-call `github_token` or
  `GITHUB_TOKEN`. Claude Code / Codex config snippets in `mcp/README.md`. The web app
  has an "For AI agents: MCP server" section with copy-paste config + file downloads.
- **Local skill: `~/workspace/skills/lovable-emergent-migrator/SKILL.md`** — agent
  playbook covering all three routes, the backend decision, guardrails, and the
  verified platform facts.
