# Brewfile — casks + mise bootstrap only.
#
# Policy (Lean A): every dev CLI lives in mise.toml — single update path
# via `mise upgrade`. The only formula here is `mise` itself, which would
# otherwise be a chicken-and-egg bootstrap problem. Casks (GUI apps,
# fonts) stay because mise doesn't manage them.
#
# Rule: if you're about to add a `brew "..."` line here, stop. Put it in
# mise.toml. The exceptions are mise itself, casks, and system libraries
# (no mise equivalent) that pre-built CLIs link against at runtime.

brew "mise"

# openssl@3 is a system library, not a CLI — `aqua:rossmacarthur/sheldon`
# dyld-links against /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib and
# segfaults without it. Cargo-built sheldon also needs openssl-sys
# (transitively via git2). Keeping it explicit guarantees fresh-machine
# installs don't ship a broken sheldon binary.
brew "openssl@3"

# bash 4+: a system layer with no mise equivalent (the shell itself).
# Apple ships 3.2 forever; 95-prune.sh (mapfile) needs 4+, and on a fresh
# machine `env bash` must not resolve to 3.2.
brew "bash"

# ── 1Password CLI + desktop ───────────────────────────────────────────
cask "1password-cli"
cask "1password"

# ── Apps ──────────────────────────────────────────────────────────────
cask "claude"
cask "discord"

# OrbStack provides the docker CLI; faster + lighter than Docker Desktop.
# Migration: export needed images/volumes from Docker Desktop before switching.
cask "orbstack"

# ── Fonts ─────────────────────────────────────────────────────────────
cask "font-fira-code-nerd-font"

# ── Terminal ──────────────────────────────────────────────────────────
cask "ghostty"

cask "google-chrome"

# Caps Lock → Control via Karabiner (rule lives in karabiner/karabiner.json,
# symlinked by dot sync).
cask "karabiner-elements"

cask "ngrok"
cask "notunes"

# Window mgmt + launcher + clipboard (replaces Rectangle + Spotlight).
cask "raycast"

cask "slack"
cask "tuple"
