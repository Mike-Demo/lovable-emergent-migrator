/**
 * analyze.js — repo inventory logic for the Lovable → Emergent migrator.
 * Pure Node (no DOM). Shared by the MCP server; mirrors web/index.html behavior.
 */

export function parseRepoUrl(u) {
  u = String(u || "").trim().replace(/\/+$/, "");
  const m = u.match(/github\.com[/:]([^/]+)\/([^/#?]+?)(?:\.git)?(?:\/(?:tree|blob)\/([^/#?]+))?(?:[#?].*)?$/i);
  if (!m) return null;
  return { owner: m[1], repo: m[2], ref: m[3] || null };
}

function headers(token) {
  const h = { Accept: "application/vnd.github+json", "User-Agent": "lovable-emergent-migrator-mcp" };
  if (token) h.Authorization = "Bearer " + token;
  return h;
}

async function gh(path, token) {
  const r = await fetch("https://api.github.com" + path, { headers: headers(token) });
  if (r.status === 404) throw new Error("Repo not found (404). Check the URL; private repos need a token with 'repo' scope.");
  if (r.status === 401) throw new Error("GitHub rejected the token (401).");
  if (r.status === 403 || r.status === 429) {
    const reset = r.headers.get("x-ratelimit-reset");
    throw new Error(`GitHub rate limit hit${reset ? ` (resets ${new Date(reset * 1000).toLocaleTimeString()})` : ""}. Pass a github_token.`);
  }
  if (!r.ok) throw new Error(`GitHub API error ${r.status} on ${path}`);
  return r.json();
}

function b64ToText(b64) {
  return Buffer.from(b64.replace(/\s/g, ""), "base64").toString("utf8");
}

const ENV_RE = /import\.meta\.env\.(VITE_[A-Z0-9_]+)|process\.env\.([A-Z0-9_]+)/g;
const SECRET_RES = [
  /sb_secret_[A-Za-z0-9_-]{8,}/, /sk-(live|test)-[A-Za-z0-9]{8,}/, /ghp_[A-Za-z0-9]{20,}/,
  /BEGIN [A-Z ]*PRIVATE KEY/, /xox[bap]-/, /["']api[_-]?key["']\s*[:=]/i,
];

export async function analyzeRepo({ repo_url, github_token, ref, max_files = 40 }) {
  const parsed = parseRepoUrl(repo_url);
  if (!parsed) throw new Error("Invalid GitHub repo URL. Expected https://github.com/owner/repo");
  const { owner, repo } = parsed;
  const token = github_token || process.env.GITHUB_TOKEN || undefined;

  const meta = await gh(`/repos/${owner}/${repo}`, token);
  const branch = ref || parsed.ref || meta.default_branch;
  if (meta.private && !token) throw new Error("Repo is private — pass github_token (or set GITHUB_TOKEN).");

  const treeRes = await gh(`/repos/${owner}/${repo}/git/trees/${encodeURIComponent(branch)}?recursive=1`, token);
  const files = (treeRes.tree || []).filter((t) => t.type === "blob").map((t) => t.path);
  const has = (p) => files.some((f) => f === p || f.startsWith(p + "/"));

  let pkg = null;
  if (files.includes("package.json")) {
    const c = await gh(`/repos/${owner}/${repo}/contents/package.json?ref=${encodeURIComponent(branch)}`, token);
    try { pkg = JSON.parse(b64ToText(c.content || "")); } catch { /* ignore */ }
  }
  const deps = pkg ? { ...pkg.dependencies, ...pkg.devDependencies } : {};
  const framework = deps.vite ? "Vite" : deps.next ? "Next.js" : deps.react ? "React" : pkg ? "JS/TS" : "unknown";
  const keyDeps = ["react", "vite", "next", "typescript", "tailwindcss", "@supabase/supabase-js", "@tanstack/react-query"]
    .filter((d) => deps[d]).map((d) => `${d}@${deps[d]}`);

  const supaFiles = files.filter((f) => f.startsWith("supabase/"));
  const migrations = supaFiles.filter((f) => f.startsWith("supabase/migrations/") && f.endsWith(".sql")).sort();
  const fnDirs = [...new Set(supaFiles.filter((f) => f.startsWith("supabase/functions/")).map((f) => f.split("/")[2]).filter(Boolean))].sort();
  const envTracked = files.filter((f) => /(^|\/)\.env(\.[A-Za-z0-9_-]+)?$/.test(f) && !f.endsWith(".env.example"));

  const textExt = /\.(tsx?|jsx?|mjs|cjs|html|json|css|vue|svelte)$/i;
  const skip = /(^|\/)(node_modules|dist|build|\.git|\.next|coverage|vendor)\//;
  const cands = files.filter((f) => textExt.test(f) && !skip.test(f) && !/\.min\.js$/.test(f) && !/lock\.json$/.test(f) && !/-lock\.yaml$/.test(f));
  const prio = ["index.html", "src/main.tsx", "src/main.ts", "src/App.tsx", "src/index.tsx", "vite.config.ts", "next.config.mjs"];
  cands.sort((a, b) => prio.indexOf(a) - prio.indexOf(b));
  const scanSet = cands.filter((f) => f !== "package.json").slice(0, max_files);

  const envVars = new Set();
  const secretHits = [];
  for (let i = 0; i < scanSet.length; i += 5) {
    await Promise.all(scanSet.slice(i, i + 5).map(async (f) => {
      try {
        const c = await gh(`/repos/${owner}/${repo}/contents/${f}?ref=${encodeURIComponent(branch)}`, token);
        if (c.size > 300000 || c.type !== "file") return;
        const text = b64ToText(c.content || "");
        let m; ENV_RE.lastIndex = 0;
        while ((m = ENV_RE.exec(text))) envVars.add(m[1] || m[2]);
        if (SECRET_RES.some((rx) => rx.test(text))) secretHits.push(f);
      } catch { /* unreadable: skip */ }
    }));
  }

  return {
    repo: `${owner}/${repo}`,
    branch,
    name: pkg?.name || repo,
    description: meta.description || null,
    private: !!meta.private,
    framework,
    scripts: pkg?.scripts || {},
    key_dependencies: keyDeps,
    supabase: {
      present: supaFiles.length > 0,
      migration_count: migrations.length,
      migrations,
      edge_functions: fnDirs,
    },
    env_vars: [...envVars].sort(),
    tracked_env_files: envTracked,
    has_lovable_artifacts: has(".lovable"),
    secret_pattern_hits: secretHits.sort(),
    files_scanned: scanSet.length,
    tree_truncated: !!treeRes.truncated,
  };
}

export function buildPrompt(inv) {
  const hasSupa = inv.supabase.present;
  const entry = inv.framework === "Vite" ? "Entry: `src/main.tsx` → `index.html` (Vite + React)."
    : inv.framework === "Next.js" ? "Entry: Next.js app router (`app/`); `npm run dev` to start."
    : "Entry: see package.json / README for the start command.";
  const backend = hasSupa
    ? `## Backend decision (IMPORTANT)
This app's backend is **Supabase** (migrations + edge functions live in \`supabase/\`).
Keep Supabase as the backend — do not port it to Emergent's native stack unless I ask.

1. Supabase schema: \`${inv.supabase.migration_count}\` migration file(s) in \`supabase/migrations/\`. These define the
   tables and RLS policies — treat them as the source of truth for the data model.
2. Edge functions: ${inv.supabase.edge_functions.length ? inv.supabase.edge_functions.join(", ") : "none"} in \`supabase/functions/\`.
3. Ask me for: SUPABASE_URL and the anon key (and service-role key only if an edge
   function needs it). Set them as environment variables in Emergent; the frontend reads
   them from \`.env.example\`.
4. Data does NOT travel with the repo (Lovable exports contain zero rows and no Storage
   files). Ask me whether to point at the existing Supabase project or a fresh one; if
   fresh, apply the migrations there first.`
    : `## Backend decision (IMPORTANT)
No \`supabase/\` directory was found in this repo, so the app is either frontend-only
or its backend lives elsewhere (API calls, Lovable Cloud, or a third-party service).

1. Scan the code for fetch/API clients and tell me what backend this app talks to.
2. Do NOT invent a backend — ask me for the base URL and any required keys, and store
   them in Emergent's env/secret store (never commit values).
3. If the app truly needs a database and none exists, propose the smallest option
   before building anything new.`;

  return `# Import prompt for Emergent (paste this into the Emergent agent after pulling the repo)

You are importing an existing app that was built in Lovable. Do NOT rebuild it from
scratch — adapt this codebase to run in Emergent.

## What this app is
- Name: ${inv.name}
- Stack: ${inv.key_dependencies.join(", ") || "see package.json"}
- Repo: ${inv.repo}, branch ${inv.branch}
- ${entry}

${backend}

## Steps
1. Install dependencies and confirm the build succeeds. Fix dependency or toolchain
   issues caused by environment differences; do not change app behavior to fix them.
2. Wire the backend env vars (from above) and verify the app boots and its main data
   flow works end to end.
3. Then summarize: what runs, what env vars are required, and anything you could not
   honor in Emergent's runtime.

## Guardrails
- Keep git history intact; commit your adaptations on a new branch.
- Never commit real secret values — use Emergent's env/secret store.`;
}

export function buildEnvExample(inv) {
  return inv.env_vars.length
    ? inv.env_vars.map((v) => `${v}=`).join("\n") + "\n"
    : "# No env vars were found referenced in the scanned code.\n# Add backend keys here as NAME= (values stay in Emergent's secret store).\n";
}

export const CHECKLIST = [
  "Lovable project synced to GitHub (Settings → Git → Connect GitHub) and repo is up to date",
  "Migration pack generated and report reviewed, warnings cleared",
  "GitHub connected in Emergent (profile icon → Connect GitHub)",
  "Repo pulled into a new Emergent task (Pull from GitHub)",
  "EMERGENT.md prompt pasted as the first message to Emergent's agent",
  "npm install + build succeed in Emergent with no behavior changes",
  "Backend re-wired: Supabase URL + keys in Emergent's secret store (or backend decision made)",
  "Auth flow works end to end (sign in / sign out)",
  "Main data flow verified (list + write at least one record)",
  "Edge functions called by the UI respond (or are flagged as unportable)",
  "No secret values committed anywhere; keys live only in Emergent's secret store",
  "Lovable project kept alive until Emergent is confirmed as the source of truth",
];
