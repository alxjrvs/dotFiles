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

# ── System utilities + services ───────────────────────────────────────
# The second exception: things that are not "dev CLIs with a mise home". These were all
# installed by hand and declared nowhere — `brew leaves` reported ten entries against two
# declared, so a fresh machine reproduced none of them. Declaring them is the point of this
# file; leaving them undeclared is the drift.
#
# Each is here for a reason that mise does not serve:
brew "bash"        # modern bash for scripts that need >3.2 (macOS ships 3.2 for licensing)
brew "coreutils"   # GNU coreutils (g-prefixed) — not a versioned toolchain
brew "moreutils"   # sponge/ts/vipe — same
brew "mysql"       # a database + brew service, not a CLI toolchain
brew "cocoapods"   # iOS dependency manager, tied to the system Ruby/Xcode toolchain

# NOT here, deliberately, though brew had installed them:
#   gh          — declared in mise.toml. The brew copy was a genuine policy violation: both
#                 were installed, and brew's won on PATH, so mise's pin was inert.
#   node        — arrived only as a dependency of netlify-cli. A second node is exactly the
#                 hazard the mise pin exists to prevent (see .zprofile's PATH comment).
#   shellcheck  — same shape, arrived as a dependency of actionlint; mise declares it.
#   netlify-cli — redundant: deploys invoke a version-pinned `bunx netlify-cli@<ver>`, so
#                 nothing needs it globally, and installing it globally is what pulled node in.

# ── 1Password CLI + desktop ───────────────────────────────────────────
cask "1password-cli"
cask "1password"

# ── Apps ──────────────────────────────────────────────────────────────
# cask "claude" is the Claude desktop GUI app, NOT the CLI (it ships no
# `claude` binary on PATH, so it coexists with the native CLI). The Claude
# Code CLI is installed via the native curl installer (run step in the boomfile
# "Claude" section) which self-updates — never install the CLI via brew
# (cask "claude-code") or npm.
cask "claude"
cask "discord"

# ── Fonts ─────────────────────────────────────────────────────────────
cask "font-fira-code-nerd-font"

# ── Terminal ──────────────────────────────────────────────────────────
# Ghostty is the canonical daily-driver terminal (TERMINAL=ghostty, set in
# zsh/00-exports.zsh): a fast Metal-GPU emulator, configured by ghostty/config
# (symlinked by `boom source` — there is no `boom apply` verb).
cask "ghostty"

cask "google-chrome"

# Caps Lock → Control is done natively via hidutil (a RunAtLoad LaunchAgent,
# launchd/com.alxjrvs.capslock-control.plist) — no Karabiner kernel extension
# for a single modifier remap.
#
# This comment described a removal that never actually happened: `karabiner-elements` is still
# installed as a cask on this machine, undeclared. It is deliberately NOT declared here — the
# hidutil agent is the supported path — but the cask needs removing by hand
# (`brew uninstall --cask karabiner-elements`), since `brew bundle` does not uninstall what a
# Brewfile omits.

cask "notunes"

# Window mgmt + launcher + clipboard (replaces Rectangle + Spotlight).
cask "raycast"

cask "slack"
cask "tuple"
