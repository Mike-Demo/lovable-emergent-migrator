#!/usr/bin/env bash
#
# install.sh — install the lovable-emergent-migrator skill pack.
#
# Usage:
#   ./install.sh                  # auto-detect a skills dir
#   ./install.sh --target DIR     # install into DIR/lovable-emergent-migrator
#   ./install.sh --list           # show detected skills dirs without installing
#
# Detected locations (first existing wins for auto mode):
#   ~/.claude/skills              (Claude Code)
#   ~/workspace/skills            (this workspace)
#   ./.claude/skills              (project-local, from current dir)
#
set -euo pipefail

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="lovable-emergent-migrator"
TARGET=""

CANDIDATES=(
  "$HOME/.claude/skills"
  "$HOME/workspace/skills"
  "$PWD/.claude/skills"
)

usage() { sed -n '2,14p' "$0"; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --list) printf '%s\n' "${CANDIDATES[@]}"; exit 0 ;;
    -h|--help) usage ;;
    *) echo "Unknown flag: $1" >&2; usage ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  for c in "${CANDIDATES[@]}"; do
    if [[ -d "$c" ]]; then TARGET="$c"; break; fi
  done
fi
if [[ -z "$TARGET" ]]; then
  echo "No skills directory found. Pass --target DIR, e.g.:"
  echo "  $0 --target ~/.claude/skills"
  exit 1
fi

DEST="$TARGET/$SKILL_NAME"
mkdir -p "$TARGET"
rm -rf "$DEST"
cp -r "$PACK_DIR" "$DEST"
chmod +x "$DEST/scripts/migrate-to-emergent.sh" "$DEST/install.sh"

echo "Installed $SKILL_NAME → $DEST"
echo ""
echo "Contents:"
echo "  SKILL.md                  agent playbook (this is what the agent reads)"
echo "  scripts/migrate-to-emergent.sh   CLI prep script"
echo "  mcp/                      MCP server (analyze_repo, generate_migration_pack)"
echo "  web/                      self-contained web analyzer"
echo ""
echo "Optional — MCP server setup (for agent tool use):"
echo "  cd \"$DEST/mcp\" && npm install"
echo ""
echo "Then add to your MCP client config, e.g. Claude Code .mcp.json:"
echo "  { \"mcpServers\": { \"$SKILL_NAME\": {"
echo "      \"command\": \"node\","
echo "      \"args\": [\"$DEST/mcp/server.js\"],"
echo "      \"env\": { \"GITHUB_TOKEN\": \"ghp_…\" } } } }"
echo "(Omit env for public-repos-only use.)"
