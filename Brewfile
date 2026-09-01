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

# boom itself, from the repo that doubles as its own tap. This machine used to run the
# copy `install.sh` drops at ~/.local/bin/boom, and .zprofile puts ~/.local/bin AHEAD of
# brew's prefix — so a brew-installed boom would have been shadowed by the bootstrap copy
# rather than replacing it. The `run` step in boomfile.toml removes that copy once this
# formula has landed, and a verify step asserts which boom actually resolves. Same
# double-install shape as the eight entries listed below; declared and closed instead.
#
# curl-pipe install.sh stays the FRESH-MACHINE bootstrap (you need a boom to run this
# file at all) — it is a bootstrap, not a second delivery path, and it hands over here.
tap "alxjrvs/boom", "https://github.com/alxjrvs/boom"
brew "boom"

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
# Nothing currently qualifies. `bash`, `coreutils`, `moreutils`, `mysql` and `cocoapods`
# were declared here after drift detection found them installed-but-undeclared; the owner
# confirmed on 2026-09-01 that none is used, so declaring drift was never the same as
# justifying it. `brew bundle` never uninstalls, so they stay on this machine until
# `brew uninstall` runs by hand — `brew bundle cleanup` now lists them.

# NOT here, deliberately. Enforced by scripts/brew-drift.sh, which fails if any of these
# is installed AND undeclared AND unlisted — the three-way state that let this block
# describe removals that had never happened. Every name below is still installed today and
# wants `brew uninstall` by hand; `brew bundle` never removes what a Brewfile omits.
#   gh          — declared in mise.toml. The brew copy is a genuine policy violation: both
#                 are installed, and brew's wins on PATH in some shells, so mise's pin is
#                 inert there. (mise's does win in an interactive login shell — measured.)
#   actionlint  — declared in mise.toml, same shape as gh.
#   osv-scanner — declared in mise.toml, same shape as gh.
#   node        — arrived only as a dependency of netlify-cli. A second node is exactly the
#                 hazard the mise pin exists to prevent (see .zprofile's PATH comment).
#   shellcheck  — same shape, arrived as a dependency of actionlint; mise declares it.
#   netlify-cli — redundant: deploys invoke a version-pinned `bunx netlify-cli@<ver>`, so
#                 nothing needs it globally, and installing it globally is what pulled node in.
#   usage       — a mise internal dependency, not a tool this repo chose.
#   heroku      — declared in mise.toml as `npm:heroku`, and it CANNOT come from here: there
#                 is no homebrew-core formula, only the third-party `heroku/brew` tap, which
#                 brew reports Untrusted and refuses to load until someone runs `brew trust`
#                 by hand. A Brewfile line that needs an interactive step is a fresh machine
#                 that stops halfway. The brew copy also self-updated past its own Cellar
#                 version (11.3.0 on disk, 11.9.0 running), so its pin was already fiction.

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
# `karabiner-elements` is still installed on this machine and deliberately NOT declared — the
# hidutil agent is the supported path. It is named in scripts/brew-drift.sh's exclusion list,
# which is what stops "deliberately excluded" from decaying into "nobody noticed". It still
# wants removing by hand (`brew uninstall --cask karabiner-elements`); `brew bundle` does not
# uninstall what a Brewfile omits.

cask "notunes"

# ── Declared after scripts/brew-drift.sh found them installed-but-undeclared ──
# A fresh machine reproduced none of these. Each was installed by hand at some
# point and never written down, which is precisely the drift the check now
# fails on.
cask "devutils"      # offline developer toolbox (JSON/JWT/regex/diff)
cask "gcloud-cli"    # Google Cloud SDK
cask "ngrok"         # public tunnel to a local port
cask "obs"           # screen recording
cask "orbstack"      # Docker/Linux VMs, the lighter Docker Desktop

# Window mgmt + launcher + clipboard (replaces Rectangle + Spotlight).
cask "raycast"

cask "slack"
cask "tuple"
