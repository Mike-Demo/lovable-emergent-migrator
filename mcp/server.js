#!/usr/bin/env node
/**
 * Lovable → Emergent Migrator — MCP server (stdio).
 *
 * Tools:
 *   analyze_repo            Inventory a Lovable-synced GitHub repo (framework, deps,
 *                           Supabase pieces, env vars, secret/tracked-.env warnings).
 *   generate_migration_pack Full migration pack: EMERGENT.md prompt, .env.example,
 *                           and the acceptance checklist.
 *
 * Run:  node server.js   (or npx lovable-emergent-migrator)
 * Auth: pass github_token per call, or set GITHUB_TOKEN (needed for private repos
 *       and to raise the rate limit above 60 req/hr).
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { analyzeRepo, buildPrompt, buildEnvExample, CHECKLIST } from "./analyze.js";

const server = new McpServer({
  name: "lovable-emergent-migrator",
  version: "1.0.0",
});

const RepoInput = {
  repo_url: z.string().describe("GitHub repo URL, e.g. https://github.com/owner/repo (the repo Lovable synced to)"),
  github_token: z.string().optional().describe("GitHub personal access token. Required for private repos; raises rate limit otherwise. Falls back to GITHUB_TOKEN env."),
  ref: z.string().optional().describe("Branch, tag, or commit SHA to analyze. Defaults to the repo's default branch."),
};

server.registerTool("analyze_repo",
  {
    title: "Analyze Lovable repo",
    description: "Inventory a Lovable-exported GitHub repo for Emergent migration: framework, dependencies, Supabase migrations/edge functions, env vars referenced in code, tracked .env files, secret-pattern hits, and .lovable artifacts.",
    inputSchema: RepoInput,
  },
  async ({ repo_url, github_token, ref }) => {
    try {
      const inv = await analyzeRepo({ repo_url, github_token, ref });
      return { content: [{ type: "text", text: JSON.stringify(inv, null, 2) }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.registerTool("generate_migration_pack",
  {
    title: "Generate Emergent migration pack",
    description: "Analyze the repo and generate the full migration pack: (1) EMERGENT.md — a paste-ready prompt telling Emergent's agent how to import and re-wire the app (keeps Supabase as backend when detected); (2) .env.example with every env var name found in code; (3) the acceptance checklist. After this, the user pulls the repo in Emergent's UI (Pull from GitHub — no API exists) and pastes the prompt.",
    inputSchema: RepoInput,
  },
  async ({ repo_url, github_token, ref }) => {
    try {
      const inv = await analyzeRepo({ repo_url, github_token, ref });
      const pack = {
        repo: inv.repo,
        branch: inv.branch,
        "EMERGENT.md": buildPrompt(inv),
        ".env.example": buildEnvExample(inv),
        checklist: CHECKLIST,
        warnings: [
          ...inv.tracked_env_files.map((f) => `Tracked .env file may contain secrets: ${f}`),
          ...inv.secret_pattern_hits.map((f) => `Possible secret pattern in: ${f}`),
          ...(inv.has_lovable_artifacts ? ["Drop .lovable/ builder artifacts before import"] : []),
          ...(!inv.supabase.present ? ["No supabase/ dir — confirm where the backend lives"] : []),
        ],
        next_steps: [
          "Emergent → profile icon → Connect GitHub → authorize",
          "New task → GitHub button in chat → Pull from GitHub → select repo + branch",
          "Paste EMERGENT.md as the first message to Emergent's agent",
          "Provide Supabase URL + anon key in Emergent's secret store when asked",
        ],
      };
      return { content: [{ type: "text", text: JSON.stringify(pack, null, 2) }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
