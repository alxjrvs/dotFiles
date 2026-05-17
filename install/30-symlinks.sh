# shellcheck shell=bash
# Cross-OS symlinks. Tags inside should_run() determine which subsections
# run under --only=. The umbrella `symlinks` tag selects everything below.

if should_run symlinks git shell mise sheldon ghostty bat atuin lazygit zsh git-hooks nvim gh claude ssh; then
  echo ""
  echo "==> Symlinks"
fi

# Git config
if should_run symlinks git; then
  link "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig" ".gitconfig"
  link "$DOTFILES_DIR/.gitmessage" "$HOME/.gitmessage" ".gitmessage"
  link "$DOTFILES_DIR/.gitignore" "$HOME/.gitignore" ".gitignore"
  link "$DOTFILES_DIR/.editorconfig" "$HOME/.editorconfig" ".editorconfig"
  link "$DOTFILES_DIR/.ripgreprc" "$HOME/.ripgreprc" ".ripgreprc"
  link "$DOTFILES_DIR/.fdignore" "$HOME/.fdignore" ".fdignore"

  # Global git pre-commit hook (referenced by core.hooksPath in .gitconfig)
  mkdir -p "$HOME/.config/git/hooks"
  link "$DOTFILES_DIR/git-hooks/pre-commit" "$HOME/.config/git/hooks/pre-commit" "git-hooks/pre-commit"

  # Bootstrap ~/.gitconfig.local with gpgSign overrides (only if missing).
  # gpgSign was moved out of dotfiles so fresh boxes don't fail commits before
  # SSH keys are present. Edit ~/.gitconfig.local to toggle signing locally.
  if [ ! -f "$HOME/.gitconfig.local" ]; then
    cat > "$HOME/.gitconfig.local" << 'GITLOCAL'
# Machine-local git overrides — NOT in dotfiles.
# Enable SSH commit/tag signing on this machine.
[commit]
	gpgSign = true
[tag]
	gpgSign = true
GITLOCAL
    warn ".gitconfig.local bootstrapped (gpgSign enabled)"
  else
    dim ".gitconfig.local already exists"
  fi

  # Bootstrap ~/.ssh/allowed_signers (required for `git log --show-signature` to
  # verify your own commits). Generated from ~/.ssh/id_ed25519.pub.
  _email=$(git config --file "$DOTFILES_DIR/.gitconfig" user.email 2> /dev/null)
  if [ ! -f "$HOME/.ssh/allowed_signers" ] && [ -f "$HOME/.ssh/id_ed25519.pub" ] && [ -n "$_email" ]; then
    mkdir -p "$HOME/.ssh"
    printf '%s %s\n' "$_email" "$(cat "$HOME/.ssh/id_ed25519.pub")" > "$HOME/.ssh/allowed_signers"
    chmod 600 "$HOME/.ssh/allowed_signers"
    # shellcheck disable=SC2088 # display string, not path
    warn "~/.ssh/allowed_signers bootstrapped"
  fi
fi

# SSH config
if should_run symlinks ssh; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  link "$DOTFILES_DIR/ssh/config" "$HOME/.ssh/config" "ssh/config"
  chmod 600 "$HOME/.ssh/config" 2> /dev/null || true
fi

# Shell config
if should_run symlinks shell; then
  link "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc" ".zshrc"
  link "$DOTFILES_DIR/.zprofile" "$HOME/.zprofile" ".zprofile"
  link "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv" ".zshenv"
  link "$DOTFILES_DIR/.hushlogin" "$HOME/.hushlogin" ".hushlogin"
fi

# mise config (Darwin only)
if [ "$OS" = "Darwin" ]; then
  if should_run symlinks mise; then
    mkdir -p "$HOME/.config/mise"
    link "$DOTFILES_DIR/mise.toml" "$HOME/.config/mise/config.toml" "mise/config.toml"
  fi
fi # Darwin

# Sheldon config
if should_run symlinks sheldon; then
  mkdir -p "$HOME/.config/sheldon"
  link "$DOTFILES_DIR/sheldon/plugins.toml" "$HOME/.config/sheldon/plugins.toml" "sheldon/plugins.toml"
fi

if [ "$OS" = "Darwin" ]; then
  # Ghostty config
  if should_run symlinks ghostty; then
    mkdir -p "$HOME/.config/ghostty"
    link "$DOTFILES_DIR/ghostty/config" "$HOME/.config/ghostty/config" "ghostty/config"
  fi

  # Bat config
  if should_run symlinks bat; then
    mkdir -p "$HOME/.config/bat"
    link "$DOTFILES_DIR/bat/config" "$HOME/.config/bat/config" "bat/config"
  fi

  # atuin config
  if should_run symlinks atuin; then
    mkdir -p "$HOME/.config/atuin"
    link "$DOTFILES_DIR/atuin/config.toml" "$HOME/.config/atuin/config.toml" "atuin/config.toml"
  fi

  # lazygit config
  if should_run symlinks lazygit; then
    mkdir -p "$HOME/.config/lazygit"
    link "$DOTFILES_DIR/lazygit/config.yml" "$HOME/.config/lazygit/config.yml" "lazygit/config.yml"
  fi

  # zsh fragments (sourced by ~/.zshrc — see zsh/README.md)
  if should_run symlinks zsh; then
    mkdir -p "$HOME/.config/zsh"
    for _zf in "$DOTFILES_DIR"/zsh/[0-9]*.zsh; do
      [ -f "$_zf" ] || continue
      _name=$(basename "$_zf")
      link "$_zf" "$HOME/.config/zsh/$_name" "zsh/$_name"
    done
  fi
fi # Darwin

# Neovim config (AstroNvim — symlink entire directory)
if should_run symlinks nvim; then
  # Migration: remove old single-file symlink if present
  if [ -L "$HOME/.config/nvim/init.lua" ] && [ ! -L "$HOME/.config/nvim" ]; then
    warn "Removing old nvim/init.lua symlink (migrating to AstroNvim)"
    rm "$HOME/.config/nvim/init.lua"
    rmdir "$HOME/.config/nvim" 2> /dev/null || true
  fi
  link "$DOTFILES_DIR/nvim" "$HOME/.config/nvim" "nvim (AstroNvim)"
fi

# GitHub CLI config
if should_run symlinks gh; then
  mkdir -p "$HOME/.config/gh"
  link "$DOTFILES_DIR/gh/config.yml" "$HOME/.config/gh/config.yml" "gh/config.yml"
fi

# Claude Code config
if should_run symlinks claude; then
  mkdir -p "$HOME/.claude"
  link "$DOTFILES_DIR/dot-claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "claude/CLAUDE.md"
  link "$DOTFILES_DIR/dot-claude/settings.json" "$HOME/.claude/settings.json" "claude/settings.json"
  link "$DOTFILES_DIR/dot-claude/hooks" "$HOME/.claude/hooks" "claude/hooks"
  link "$DOTFILES_DIR/dot-claude/agents" "$HOME/.claude/agents" "claude/agents"
  link "$DOTFILES_DIR/dot-claude/commands" "$HOME/.claude/commands" "claude/commands"
  link "$DOTFILES_DIR/dot-claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh" "claude/statusline-command.sh"
  # settings.local.json is gitignored (contains secrets) — only link if present
  if [ -f "$DOTFILES_DIR/dot-claude/settings.local.json" ]; then
    link "$DOTFILES_DIR/dot-claude/settings.local.json" "$HOME/.claude/settings.local.json" "claude/settings.local.json"
  else
    dim "claude/settings.local.json not present — skipping"
  fi
fi
