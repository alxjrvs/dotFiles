# supabase moved to mise (aqua:supabase/cli) — the supabase/tap formula breaks
# on Tier 3 (Tahoe / Apple Silicon) due to missing top-level URL resolution.
brew "mise"
brew "atuin"
brew "fzf"
brew "gh"
brew "git-delta"
brew "lazygit"
brew "bat"
brew "difftastic"
brew "gitleaks"
brew "age"
brew "dust"
brew "eza"
brew "glow"
brew "fd"
brew "jq"
brew "yq"
brew "neovim"
brew "gnupg"
brew "direnv"
brew "ripgrep"
brew "tealdeer"
brew "zoxide"
brew "sheldon"
brew "shfmt"
brew "shellcheck"
brew "lefthook"        # repo-local git hook runner (pre-commit shellcheck/shfmt for this repo; see lefthook.yml)
brew "uv"
brew "luarocks"        # Lua package manager — required by lazy.nvim for plugins that need luarocks deps
brew "tree-sitter-cli" # `tree-sitter` CLI parser-generator — needed by nvim-treesitter for :TSInstallFromGrammar
brew "gdu"             # interactive disk usage analyzer; installs as `gdu-go` to avoid coreutils conflict
# NOTE: Tier 3 systems (macOS Tahoe / Apple Silicon) lack pre-built bottles
# for these. sync.sh's "Tier 3 fallback installs" section auto-installs them
# via cargo (watchexec/pueue/bottom/git-absorb) and GitHub releases (carapace).
# These brew entries are kept so the canonical install lights up when
# upstream bottles eventually arrive.
brew "carapace"      # multi-shell completions for ~600 tools (gh, mise, op, kubectl, ...)
brew "watchexec"     # fast file-change watcher (run cmds on edits, smart restart)
brew "pueue"         # persistent task queue daemon for long-running/background jobs
brew "btop"          # modern resource monitor (top / htop replacement)
brew "git-absorb"    # auto-fixup staged hunks to the right history commit
cask "1password-cli"
cask "1password"
cask "claude"
cask "devutils"
cask "discord"
# OrbStack provides docker CLI; faster + lighter than Docker Desktop.
# Migration: export needed images/volumes from Docker Desktop before switching.
cask "orbstack"
cask "font-fira-code-nerd-font"
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
