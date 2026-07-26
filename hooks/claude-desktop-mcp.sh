#!/usr/bin/env bash
# claude-desktop-mcp — register the GitHub MCP server in Claude Desktop.
#
# Claude Desktop's config canNOT be a boom `link`. Every other Claude surface in
# this repo is symlinked from a tracked file, but claude_desktop_config.json is
# live app-owned state: the app itself writes `preferences`, paired-device IDs,
# workspace and session keys into it continuously. Symlinking it would mean the
# app rewriting a tracked file on every launch (permanent repo dirt, and the
# `boom verify` dirty-tree check would never pass again), and a fresh `boom
# source` would clobber real app state. So this merges ONLY our one key and
# leaves the rest of the document byte-identical.
#
# Idempotent: exits 0 unchanged when the entry is already correct, so it is safe
# on every `boom source`.
set -euo pipefail

CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
LAUNCHER="$HOME/.local/bin/gh-mcp-stdio"

# Claude Desktop isn't installed on every machine this repo converges (a server
# or a fresh box may only get the CLI) — skip rather than fail.
[[ -d "$HOME/Library/Application Support/Claude" ]] || {
  echo "claude-desktop-mcp: Claude Desktop not present — skipping"
  exit 0
}

CONFIG="$CONFIG" LAUNCHER="$LAUNCHER" python3 << 'PY'
import json, os, shutil, sys

config = os.environ["CONFIG"]
launcher = os.environ["LAUNCHER"]

try:
    with open(config) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except json.JSONDecodeError as e:
    # Never overwrite a config we failed to parse — that would destroy real app
    # state (preferences, paired devices) to add one key.
    sys.exit(f"claude-desktop-mcp: {config} is not valid JSON ({e}) — refusing to write")

if not isinstance(data, dict):
    sys.exit("claude-desktop-mcp: config root is not an object — refusing to write")

servers = data.setdefault("mcpServers", {})
# The launcher takes no args and reads the PAT from 1Password at startup, so the
# entry carries no token and no `env` block — unlike GitHub's documented config.
desired = {"command": launcher}

if servers.get("github") == desired:
    print("claude-desktop-mcp: already registered")
    sys.exit(0)

servers["github"] = desired

if os.path.exists(config):
    shutil.copy2(config, config + ".boom-backup")

# Write via a temp file in the same directory, then atomically replace, so an
# interrupted write can't truncate the app's live config.
tmp = config + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, config)
print("claude-desktop-mcp: registered github -> " + launcher)
print("claude-desktop-mcp: restart Claude Desktop to pick it up")
PY
