#!/usr/bin/env bash
#
# migrate-to-emergent.sh — prepare a Lovable-exported GitHub repo for import into Emergent (emergent.sh)
#
# What it does:
#   1. Clones your Lovable GitHub repo (the one Lovable's Git sync created).
#   2. Inventories the app: framework, deps, Supabase backend pieces, env vars, secrets risk.
#   3. Sanitizes it for import: drops .lovable/, tightens .gitignore, generates .env.example (no values).
#   4. Writes EMERGENT.md — a paste-ready prompt for Emergent's agent that tells it exactly
#      what the app is, how to build it, and how to re-wire the backend.
#   5. Optionally pushes a dedicated `emergent-import` branch you then Pull in Emergent's UI.
#
# Emergent has NO import API or deep link (verified 2026-10-12) — the actual pull is a few
# clicks in the Emergent UI. This script does everything automatable before that.
#
# Usage:
#   ./migrate-to-emergent.sh --repo git@github.com:you/your-lovable-app.git [--branch emergent-import] [--push] [--workdir PATH]
#
# Requires: git, bash 4+. Optional: gh CLI (used for repo metadata if present).

set -euo pipefail

REPO=""
BRANCH="emergent-import"
PUSH=false
WORKDIR="${HOME}/workspace/lovable-to-emergent/work"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO="$2"; shift 2 ;;
    --branch)  BRANCH="$2"; shift 2 ;;
    --push)    PUSH=true; shift ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *) err "Unknown flag: $1 (see --help)" ;;
  esac
done

[[ -n "$REPO" ]] || err "Pass --repo <git-url of the Lovable-synced GitHub repo>."
command -v git >/dev/null || err "git is required."

NAME="$(basename "$REPO" .git)"
DIR="${WORKDIR}/${NAME}"
mkdir -p "$WORKDIR"

echo ""
echo "=== 1/5 Cloning ${NAME} ==="
if [[ -d "$DIR/.git" ]]; then
  warn "Workdir exists — resetting it to a clean state."
  (cd "$DIR" && git fetch origin --quiet || true)
else
  git clone --quiet "$REPO" "$DIR" || err "Clone failed — check the URL and your git credentials."
fi
cd "$DIR"
DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||' || echo main)"
# Make re-runs deterministic: drop script-generated leftovers, force-checkout the
# default branch, and hard-reset it to origin (workdir is script-owned scratch).
git clean -fdq -- EMERGENT.md 2>/dev/null || true
git checkout -qf "$DEFAULT_BRANCH" 2>/dev/null \
  || git checkout -qf -b "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" 2>/dev/null || true
if git rev-parse -q --verify "origin/${DEFAULT_BRANCH}" >/dev/null 2>&1; then
  git reset -q --hard "origin/${DEFAULT_BRANCH}"
fi
ok "Cloned/updated at ${DIR} (branch: ${DEFAULT_BRANCH}, head: $(git rev-parse --short HEAD))"

echo ""
echo "=== 2/5 Inventory ==="
INV="${WORKDIR}/${NAME}-inventory.txt"
{
  echo "INVENTORY — ${NAME} — $(date -u +%F)"
  echo "repo: ${REPO}"
  echo "default branch: ${DEFAULT_BRANCH}, head: $(git rev-parse HEAD)"
  echo ""
  echo "--- package.json ---"
  if [[ -f package.json ]] && command -v python3 >/dev/null; then
    python3 - <<'PYEOF' 2>/dev/null || echo "(package.json unreadable)"
import json
p = json.load(open('package.json'))
print("name:", p.get('name'), "| version:", p.get('version'))
print("scripts:", ", ".join(f"{k}=`{v}`" for k, v in p.get('scripts', {}).items()))
deps = {**p.get('dependencies', {}), **p.get('devDependencies', {})}
keep = ['react', 'vite', 'next', 'typescript', 'tailwindcss', '@supabase/supabase-js',
        '@tanstack/react-query', '@vitejs/plugin-react']
print("key deps:", ", ".join(f"{k}@{deps[k]}" for k in keep if k in deps) or "(none of the usual suspects)")
PYEOF
  elif [[ -f package.json ]]; then
    grep -m1 '"name"' package.json
  else
    echo "MISSING — not a JS app at root?"
  fi
  echo ""
  echo "--- backend pieces ---"
  if [[ -d supabase ]]; then
    echo "supabase/ present"
    echo "  migrations: $({ find supabase/migrations -name '*.sql' 2>/dev/null || true; } | wc -l) files"
    echo "  functions:  $({ ls supabase/functions 2>/dev/null || true; } | wc -l) dirs: $({ ls supabase/functions 2>/dev/null || true; } | tr '\n' ' ')"
    [[ -f supabase/config.toml ]] && grep -E 'project_ref|project_id' supabase/config.toml | head -2 || true
  else
    echo "no supabase/ dir — app may be frontend-only or use another backend"
  fi
  echo ""
  echo "--- tracked env files (values NOT shown; review for committed secrets) ---"
  if git ls-files | grep -E '(^|/)\.env($|\.[^.]*$)' | grep -v '\.env\.example$' | head -10; then
    echo "(files above are tracked in git — clear before pushing)"
  else
    echo "none tracked (good)"
  fi
  echo ""
  echo "--- env vars referenced in code (names only) ---"
  SCAN_PATHS=()
  [[ -d src ]] && SCAN_PATHS+=(src)
  [[ -f index.html ]] && SCAN_PATHS+=(index.html)
  if ((${#SCAN_PATHS[@]})); then
    VARS="$({ grep -rhoE 'import\.meta\.env\.VITE_[A-Z0-9_]+|process\.env\.[A-Z_][A-Z0-9_]+' "${SCAN_PATHS[@]}" 2>/dev/null || true; } \
      | sed 's/import\.meta\.env\.//; s/process\.env\.//' | sort -u)"
    [[ -n "$VARS" ]] && echo "$VARS" || echo "(none found)"
  else
    echo "(no src/ or index.html to scan)"
  fi
  echo ""
  echo "--- lovable artifacts ---"
  [[ -d .lovable ]] && echo ".lovable/ present (will be removed)" || echo "no .lovable/"
  echo ""
  echo "--- potential committed secrets (review manually) ---"
  if git grep -nEi 'sb_secret_|sk-(live|test)-|ghp_[A-Za-z0-9]{20,}|gsk_[A-Za-z0-9]{20,}|xox[bap]-|BEGIN [A-Z ]*PRIVATE KEY|aws_secret_access_key|api[_-]?key["'"'"'=: ]+[A-Za-z0-9_\-]{16,}' -- . ':!package-lock.json' ':!pnpm-lock.yaml' ':!bun.lockb' 2>/dev/null | head -10; then
    echo "(matches above need manual review — do not push until cleared)"
  else
    echo "no obvious secret patterns matched"
  fi
} > "$INV"
cat "$INV"
ok "Inventory saved to ${INV}"

echo ""
echo "=== 3/5 Sanitize ==="
CHANGED=false
if [[ -d .lovable ]]; then
  git rm -rq --cached .lovable >/dev/null 2>&1 || true
  rm -rf .lovable
  CHANGED=true; ok "Removed .lovable/"
fi
# Tighten .gitignore (never commit .env with values)
for pat in '.env' '.env.*' '!.env.example' 'node_modules' 'dist' 'build' '.DS_Store'; do
  if ! grep -qxF "$pat" .gitignore 2>/dev/null; then
    echo "$pat" >> .gitignore; CHANGED=true
  fi
done
ok ".gitignore covers .env*, node_modules, dist"

# Merge referenced env vars into .env.example (names only, empty values).
# Never clobbers entries that are already there — appends only what's missing.
ENV_EXAMPLE=".env.example"
SCAN_PATHS=()
[[ -d src ]] && SCAN_PATHS+=(src)
[[ -f index.html ]] && SCAN_PATHS+=(index.html)
ADDED=0
if ((${#SCAN_PATHS[@]})); then
  touch "$ENV_EXAMPLE"
  while read -r v; do
    [[ -z "$v" ]] && continue
    if ! grep -qE "^${v}=" "$ENV_EXAMPLE" 2>/dev/null; then
      echo "${v}=" >> "$ENV_EXAMPLE"
      ADDED=$((ADDED + 1))
    fi
  done < <({ grep -rhoE 'import\.meta\.env\.(VITE_[A-Z0-9_]+)|process\.env\.([A-Z_][A-Z0-9_]+)' "${SCAN_PATHS[@]}" 2>/dev/null || true; } \
    | sed -E 's/import\.meta\.env\.//; s/process\.env\.//' | sort -u)
fi
if ((ADDED > 0)); then
  ok "Added ${ADDED} var name(s) to .env.example (existing entries kept)"
elif [[ -s "$ENV_EXAMPLE" ]]; then
  ok ".env.example already covers all referenced vars"
else
  warn "No env vars found in code — .env.example is empty; add backend keys manually if needed."
fi
CHANGED=true

echo ""
echo "=== 4/5 Writing EMERGENT.md (paste-ready import prompt) ==="
APP_NAME=""; DEPS_LINE=""
if [[ -f package.json ]] && command -v python3 >/dev/null; then
  APP_NAME="$(python3 -c "import json; print(json.load(open('package.json')).get('name','${NAME}'))" 2>/dev/null || echo "$NAME")"
  DEPS_LINE="$(python3 -c "
import json
p = json.load(open('package.json'))
deps = {**p.get('dependencies',{}), **p.get('devDependencies',{})}
keep = ['react','vite','next','typescript','tailwindcss','@supabase/supabase-js','@tanstack/react-query']
print(', '.join(f'{k}@{deps[k]}' for k in keep if k in deps))" 2>/dev/null)"
fi
[[ -n "$APP_NAME" ]] || APP_NAME="$NAME"
[[ -n "$DEPS_LINE" ]] || DEPS_LINE="(see package.json)"
MIG_COUNT="$({ find supabase/migrations -name '*.sql' 2>/dev/null || true; } | wc -l | tr -d ' ')"
FN_LIST="$({ ls supabase/functions 2>/dev/null || true; } | tr '\n' ', ' | sed 's/, $//')"
HAS_SUPABASE=false; [[ -d supabase ]] && HAS_SUPABASE=true
# Framework detection for an honest "entry" line
FRAMEWORK="unknown"
if [[ -f package.json ]] && command -v python3 >/dev/null; then
  FRAMEWORK="$(python3 -c "
import json
p = json.load(open('package.json'))
deps = {**p.get('dependencies', {}), **p.get('devDependencies', {})}
print('vite' if 'vite' in deps else 'next' if 'next' in deps else 'react' if 'react' in deps else 'unknown')" 2>/dev/null || echo unknown)"
fi
ENTRY_LINE="Entry: see package.json / README for the start command."
[[ "$FRAMEWORK" == "vite" ]] && ENTRY_LINE='Entry: `src/main.tsx` → `index.html` (Vite + React; Tailwind/shadcn if present).'
[[ "$FRAMEWORK" == "next" ]] && ENTRY_LINE='Entry: Next.js app router (`app/`); `npm run dev` to start.'

if [[ "$HAS_SUPABASE" == true ]]; then
BACKEND_SECTION="## Backend decision (IMPORTANT)
This app's backend is **Supabase** (migrations + edge functions live in \`supabase/\`).
Keep Supabase as the backend — do not port it to Emergent's native stack unless I ask.

1. Supabase schema: \`${MIG_COUNT}\` migration file(s) in \`supabase/migrations/\`. These define the
   tables and RLS policies — treat them as the source of truth for the data model.
2. Edge functions: ${FN_LIST:-none} in \`supabase/functions/\`.
3. Ask me for: SUPABASE_URL and the anon key (and service-role key only if an edge
   function needs it). Set them as environment variables in Emergent; the frontend reads
   them from \`.env.example\`.
4. Data does NOT travel with the repo (Lovable exports contain zero rows and no Storage
   files). Ask me whether to point at the existing Supabase project or a fresh one; if
   fresh, apply the migrations there first."
else
BACKEND_SECTION="## Backend decision (IMPORTANT)
No \`supabase/\` directory was found in this repo, so the app is either frontend-only
or its backend lives elsewhere (API calls, Lovable Cloud, or a third-party service).

1. Scan the code for fetch/API clients and tell me what backend this app talks to.
2. Do NOT invent a backend — ask me for the base URL and any required keys, and store
   them in Emergent's env/secret store (never commit values).
3. If the app truly needs a database and none exists, propose the smallest option
   (e.g. keep the existing external backend) before building anything new."
fi

cat > EMERGENT.md <<EOF
# Import prompt for Emergent (paste this into the Emergent agent after Pulling the repo)

You are importing an existing app that was built in Lovable. Do NOT rebuild it from
scratch — adapt this codebase to run in Emergent.

## What this app is
- Name: ${APP_NAME}
- Stack: ${DEPS_LINE}
- Repo branch pulled: ${BRANCH} (head commit $(git rev-parse --short HEAD))
- ${ENTRY_LINE}

${BACKEND_SECTION}

## Steps
1. \`npm install\` (or the repo's own install command) and confirm the build succeeds.
   Fix dependency or toolchain issues caused by environment differences; do not change
   app behavior to fix them.
2. Wire the backend env vars (from above) and verify the app boots and its main data
   flow works end to end.
3. Then summarize: what runs, what env vars are required, and anything you could not
   honor in Emergent's runtime.

## Guardrails
- Keep git history intact; commit your adaptations on a new branch.
- Never commit real secret values — use Emergent's env/secret store.
EOF
ok "Wrote EMERGENT.md — review it, then paste into Emergent's agent after the Pull."

echo ""
echo "=== 5/5 Branch & push ==="
git clean -fdq -- EMERGENT.md 2>/dev/null || true  # re-run safety: untracked EMERGENT.md would block checkout
git checkout -qb "$BRANCH" 2>/dev/null || git checkout -qf "$BRANCH"
git add -A
if git diff --cached --quiet; then
  warn "No changes to commit on ${BRANCH}."
else
  git commit -q -m "Prepare Lovable app for Emergent import

- Removed .lovable/ builder artifacts
- Tightened .gitignore (.env*, node_modules, dist)
- Added .env.example (env var names only, no values)
- Added EMERGENT.md import prompt for the Emergent agent" \
  && ok "Committed to ${BRANCH}"
fi

if [[ "$PUSH" == true ]]; then
  if git push -q -u origin "$BRANCH" 2>/tmp/emig-push-err.txt; then
    ok "Pushed ${BRANCH} to origin."
  else
    warn "Push failed — the branch is ready locally; push manually when ready:"
    warn "  git push -u origin ${BRANCH}"
    grep -E 'rejected|behind|error' /tmp/emig-push-err.txt 2>/dev/null | head -3 | sed 's/^/  /'
    warn "If origin's ${BRANCH} diverged from a previous run and it is script-managed,"
    warn "delete it first: git push origin --delete ${BRANCH} (then re-run with --push)"
  fi
else
  warn "Not pushed. Run with --push, or: git push -u origin ${BRANCH}"
fi

echo ""
echo "=== Next steps (in Emergent's UI — no API exists, verified 2026-10-12) ==="
echo "  1. Emergent → profile icon → Connect GitHub → authorize (grant this repo)."
echo "  2. Start a new task → GitHub button in chat → Pull from GitHub."
echo "  3. Select repo '${NAME}', branch '${BRANCH}'."
echo "  4. Paste the contents of EMERGENT.md as your first prompt to the agent."
echo "  5. Provide your Supabase URL + anon key when it asks (existing vs fresh project)."
echo ""
echo "Inventory: ${INV}"
echo "Workdir:   ${DIR}"
