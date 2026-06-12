#!/usr/bin/env bash
# install/40-symlinks.sh — full symlink mapping table.
# Tags: symlinks git shell mise sheldon ghostty bat atuin zsh
#       git-template gh claude ssh nvim karabiner
# Sourced by sync; not standalone — helpers (os_kind, host_id, link) come from
# sync, which exports them before sourcing this module.

_symlinks_tags() {
  printf 'symlinks\ngit\nshell\nmise\nsheldon\nghostty\nbat\natuin\nzsh\ngit-template\ngh\nclaude\nssh\nnvim\nkarabiner\n'
}

_symlinks_run() {
  local df="${DOTFILES_DIR}"
  local os
  os=$(os_kind)

  printf '\n==> Symlinks\n'

  # ── Git config ────────────────────────────────────────────────────────
  if should_run symlinks git; then
    for name in .gitconfig .gitmessage .gitignore .editorconfig .ripgreprc .fdignore; do
      link "${df}/${name}" "${HOME}/${name}"
    done

    # Template hooks for init.templateDir.
    mkdir -p "${HOME}/.config/git/template/hooks"
    link "${df}/git-template/hooks/pre-commit" \
      "${HOME}/.config/git/template/hooks/pre-commit"

    # Clean up the stale core.hooksPath-era symlink if it still exists.
    local dead_hook="${HOME}/.config/git/hooks/pre-commit"
    if [[ -e "$dead_hook" || -L "$dead_hook" ]]; then
      rm -f "$dead_hook"
      rmdir "${HOME}/.config/git/hooks" 2> /dev/null || true
    fi

  fi

  # ── dot dispatcher ────────────────────────────────────────────────────
  if should_run symlinks shell; then
    mkdir -p "${HOME}/.local/bin"
    link "${df}/dot" "${HOME}/.local/bin/dot"
  fi

  # ── SSH config ────────────────────────────────────────────────────────
  if should_run symlinks ssh; then
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    link "${df}/ssh/config" "${HOME}/.ssh/config"
    chmod 600 "${HOME}/.ssh/config" 2> /dev/null || true
    # 1Password SSH agent key-offer config (auth keys live in 1Password).
    mkdir -p "${HOME}/.config/1Password/ssh"
    link "${df}/ssh/1password-agent.toml" "${HOME}/.config/1Password/ssh/agent.toml"
    # gpg.ssh.program wrapper — env-independent commit signing.
    mkdir -p "${HOME}/.local/bin"
    link "${df}/ssh/git-ssh-sign" "${HOME}/.local/bin/git-ssh-sign"
  fi

  # ── Shell config ──────────────────────────────────────────────────────
  if should_run symlinks shell; then
    for f in .zshrc .zprofile .zshenv .hushlogin; do
      link "${df}/${f}" "${HOME}/${f}"
    done
  fi

  # Darwin-only symlinks.
  if [[ "$os" == "darwin" ]]; then
    if should_run symlinks mise; then
      mkdir -p "${HOME}/.config/mise"
      link "${df}/mise.toml" "${HOME}/.config/mise/config.toml"
    fi
  fi

  if should_run symlinks sheldon; then
    mkdir -p "${HOME}/.config/sheldon"
    link "${df}/sheldon/plugins.toml" "${HOME}/.config/sheldon/plugins.toml"
  fi

  if [[ "$os" == "darwin" ]]; then
    if should_run symlinks ghostty; then
      mkdir -p "${HOME}/.config/ghostty"
      link "${df}/ghostty/config" "${HOME}/.config/ghostty/config"
    fi

    if should_run symlinks bat; then
      mkdir -p "${HOME}/.config/bat"
      link "${df}/bat/config" "${HOME}/.config/bat/config"
    fi

    if should_run symlinks atuin; then
      mkdir -p "${HOME}/.config/atuin"
      link "${df}/atuin/config.toml" "${HOME}/.config/atuin/config.toml"
    fi

    if should_run symlinks nvim; then
      mkdir -p "${HOME}/.config/nvim"
      link "${df}/nvim/init.lua" "${HOME}/.config/nvim/init.lua"
    fi

    if should_run symlinks karabiner; then
      mkdir -p "${HOME}/.config/karabiner"
      link "${df}/karabiner/karabiner.json" "${HOME}/.config/karabiner/karabiner.json"
    fi

    # zsh fragments — numeric-prefixed *.zsh only.
    if should_run symlinks zsh; then
      mkdir -p "${HOME}/.config/zsh"
      local f
      for f in "${df}/zsh"/[0-9]*.zsh; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f")
        link "$f" "${HOME}/.config/zsh/${name}"
      done
    fi
  fi

  # ── GitHub CLI ────────────────────────────────────────────────────────
  if should_run symlinks gh; then
    mkdir -p "${HOME}/.config/gh"
    link "${df}/gh/config.yml" "${HOME}/.config/gh/config.yml"
    # headersHelper for the user-scope github MCP server (registered by
    # install/60-claude.sh) — resolves the bearer token from the gh keychain
    # on demand, so no PAT is exported into the shell env.
    mkdir -p "${HOME}/.local/bin"
    link "${df}/gh/gh-mcp-auth-header" "${HOME}/.local/bin/gh-mcp-auth-header"
  fi

  # ── Claude Code ───────────────────────────────────────────────────────
  if should_run symlinks claude; then
    mkdir -p "${HOME}/.claude"
    link "${df}/dot-claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
    link "${df}/dot-claude/settings.json" "${HOME}/.claude/settings.json"

    # Clean up stale symlinks from the pre-rebuild layout: dot-claude/agents
    # and dot-claude/commands were deleted, so the old links dangle (and a
    # later `mkdir -p ~/.claude/agents` would follow the dangling link and
    # resurrect the directory inside the repo). Only remove symlinks — a
    # real directory here is machine-local content we don't own.
    local stale
    for stale in "${HOME}/.claude/agents" "${HOME}/.claude/commands"; do
      if [[ -L "$stale" ]]; then
        rm -f "$stale"
      fi
    done

    # settings.local.json is deliberately unsupported: this repo carries no
    # local-settings overlay. Remove a stale symlink if an old sync made one.
    if [[ -L "${HOME}/.claude/settings.local.json" ]]; then
      rm -f "${HOME}/.claude/settings.local.json"
    fi

    # The compiled dotctl binary predates the shell rewrite; nothing
    # references it anymore. Remove the leftover (plain file only — never
    # follow a symlink someone re-pointed). If the rm fails, warn instead
    # of false-reporting removal.
    if [[ -f "${HOME}/.local/bin/dotctl" && ! -L "${HOME}/.local/bin/dotctl" ]]; then
      if rm -f "${HOME}/.local/bin/dotctl" 2> /dev/null; then
        printf '\033[2m  - removed legacy dotctl binary\033[0m\n'
      else
        printf '\033[0;33m  \xe2\x86\x92 legacy ~/.local/bin/dotctl not removable here — rm it from a regular terminal\033[0m\n'
      fi
    fi
  fi
}
