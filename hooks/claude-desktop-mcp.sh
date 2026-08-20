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
# WHAT IT REGISTERS (changed 2026-08-20 — see dot-claude/DECISIONS.md):
#
#   command: <op>  args: [run, --env-file=<gh/mcp.env>, --, <server>, stdio]
#
# This is 1Password's own published shape for securing an MCP config, and it
# replaced a bespoke launcher (`gh-mcp-stdio`) whose entire job was to read the
# PAT and export it into the server's environment — exactly what `op run` does
# natively. Deleting it is this repo's "no gratuitous wrappers" rule applied to
# the one script that had stopped earning its place.
#
# Two properties the wrapper had, preserved here:
#   - The token is never in the config file and never in argv (so it cannot leak
#     via `ps`); only an `op://` REFERENCE is, and `op run` resolves it in-process.
#   - A failed resolve does not start an unauthenticated server: `op run` exits
#     non-zero and Desktop surfaces a server that failed to launch, rather than
#     one that connects and then 401s on every call — the silent-failure mode
#     that hid the last GitHub MCP outage.
#
# One property that CHANGED, deliberately: the wrapper resolved via the agent
# SERVICE ACCOUNT (keychain-backed, no biometric), so it worked with Desktop
# launched at login and 1Password locked. `op run` uses the desktop integration
# and will prompt. That is the correct tier — per 1Password's two-tier model
# Claude Desktop is an INTERACTIVE surface (you, at the keyboard), and the
# service account is the hands-off agent tier. Using the SA there was tier
# confusion. The cost is real: with 1Password locked, the server does not start
# until you unlock.
#
# ABSOLUTE PATHS ARE REQUIRED. Claude Desktop launches as a GUI app and does not
# inherit a shell PATH — 1Password documents this exact failure ("If `op` can't
# be found, use its full path as the command value instead"). Both `op` and the
# server binary are therefore resolved here, at sync time, and written out fully
# qualified.
#
# Idempotent: exits 0 unchanged when the entry is already correct, so it is safe
# on every `boom source`.
set -euo pipefail

CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
ENV_FILE="$HOME/.config/gh/mcp.env"

# Claude Desktop isn't installed on every machine this repo converges (a server
# or a fresh box may only get the CLI) — skip rather than fail.
[[ -d "$HOME/Library/Application Support/Claude" ]] || {
  echo "claude-desktop-mcp: Claude Desktop not present — skipping"
  exit 0
}

# Resolve both binaries to absolute paths NOW, because the GUI app cannot.
# Prefer the mise shim over the versioned install path: the shim is stable
# across `mise upgrade`, so a server bump does not silently strand the config.
OP_BIN="$(command -v op || true)"
[[ -n "$OP_BIN" ]] || {
  echo "claude-desktop-mcp: op (1Password CLI) not on PATH — install it, then re-run 'boom source'" >&2
  exit 1
}

SERVER_BIN="$HOME/.local/share/mise/shims/github-mcp-server"
[[ -x "$SERVER_BIN" ]] || SERVER_BIN="$(command -v github-mcp-server || true)"
[[ -n "$SERVER_BIN" && -x "$SERVER_BIN" ]] || {
  echo "claude-desktop-mcp: github-mcp-server not installed — run 'mise install'" >&2
  exit 1
}

# The env file is linked by the same boomfile section; if it is missing, the
# server would launch and fail to resolve. Fail here instead, where the message
# can say why.
[[ -f "$ENV_FILE" ]] || {
  echo "claude-desktop-mcp: $ENV_FILE is missing — run 'boom source' to link it" >&2
  exit 1
}

CONFIG="$CONFIG" OP_BIN="$OP_BIN" SERVER_BIN="$SERVER_BIN" ENV_FILE="$ENV_FILE" python3 << 'PY'
import json, os, shutil, sys

config = os.environ["CONFIG"]

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
# No `env` block and no token: `op run` resolves the op:// reference in the
# env-file at launch and injects it into the server's environment only.
desired = {
    "command": os.environ["OP_BIN"],
    "args": [
        "run",
        "--env-file=" + os.environ["ENV_FILE"],
        "--",
        os.environ["SERVER_BIN"],
        "stdio",
    ],
}

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
print("claude-desktop-mcp: registered github -> op run --env-file (no token in config)")
print("claude-desktop-mcp: restart Claude Desktop to pick it up")
PY
