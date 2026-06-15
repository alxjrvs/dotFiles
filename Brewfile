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

# ── 1Password CLI + desktop ───────────────────────────────────────────
cask "1password-cli"
cask "1password"

# ── Apps ──────────────────────────────────────────────────────────────
cask "claude"
cask "discord"

# ── Fonts ─────────────────────────────────────────────────────────────
cask "font-fira-code-nerd-font"

# ── Terminal ──────────────────────────────────────────────────────────
# cmux is the canonical terminal (TERMINAL=cmux, set in zsh/00-exports.zsh):
# a libghostty-based agent multiplexer for parallel Claude Code sessions with
# vertical tabs and git-worktree isolation. App config is portable in
# cmux/cmux.json; terminal rendering comes from ghostty/config, which cmux
# reads via embedded libghostty (both symlinked by dot sync).
cask "cmux"

# Ghostty is the rendering engine cmux embeds — kept installed for libghostty,
# not a separate daily driver. Reads the same ghostty/config if launched.
cask "ghostty"

cask "google-chrome"

# Caps Lock → Control via Karabiner (rule lives in karabiner/karabiner.json,
# symlinked by dot sync).
cask "karabiner-elements"

cask "notunes"

# Window mgmt + launcher + clipboard (replaces Rectangle + Spotlight).
cask "raycast"

cask "slack"
cask "tuple"
