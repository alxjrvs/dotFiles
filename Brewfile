# Brewfile — casks + mise bootstrap only.
#
# Policy (Lean A): every dev CLI lives in mise.toml — single update path
# via `mise upgrade`. The only formula here is `mise` itself, which would
# otherwise be a chicken-and-egg bootstrap problem. Casks (GUI apps,
# fonts) stay because mise doesn't manage them.
#
# Rule: if you're about to add a `brew "..."` line here, stop. Put it in
# mise.toml. The exceptions are mise itself and casks.

brew "mise"

# ── 1Password CLI + desktop ───────────────────────────────────────────
cask "1password-cli"
cask "1password"

# ── Apps ──────────────────────────────────────────────────────────────
cask "claude"
cask "devutils"
cask "discord"

# OrbStack provides the docker CLI; faster + lighter than Docker Desktop.
# Migration: export needed images/volumes from Docker Desktop before switching.
cask "orbstack"

# ── Fonts ─────────────────────────────────────────────────────────────
cask "font-fira-code-nerd-font"

# ── Terminal ──────────────────────────────────────────────────────────
cask "ghostty"

cask "google-chrome"

# Caps Lock → Escape via Karabiner.
cask "karabiner-elements"

cask "ngrok"
cask "notunes"

# Window mgmt + launcher + clipboard (replaces Rectangle + Spotlight).
cask "raycast"

cask "slack"
cask "tuple"
