#!/usr/bin/env bash
# install/40-symlinks.sh — full symlink mapping table.
# Tags: symlinks git shell mise sheldon ghostty bat atuin lazygit zsh
#       git-template gh claude ssh helix karabiner
# Sourced by sync; not standalone — helpers (os_kind, host_id, link) come from
# sync, which exports them before sourcing this module.

_symlinks_tags() {
  printf 'symlinks\ngit\nshell\nmise\nsheldon\nghostty\nbat\natuin\nlazygit\nzsh\ngit-template\ngh\nclaude\nssh\nhelix\nkarabiner\n'
}

_symlinks_run() {
  local df="${DOTFILES_DIR}"
  local os
  os=$(os_kind)

  printf '\n==> Symlinks\n'

  # ── Git config ────────────────────────────────────────────────────────
  if _should_run_tags "symlinks git"; then
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
  if _should_run_tags "symlinks shell"; then
    mkdir -p "${HOME}/.local/bin"
    link "${df}/dot" "${HOME}/.local/bin/dot"
  fi

  # ── SSH config ────────────────────────────────────────────────────────
  if _should_run_tags "symlinks ssh"; then
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    link "${df}/ssh/config" "${HOME}/.ssh/config"
    chmod 600 "${HOME}/.ssh/config" 2> /dev/null || true
    # 1Password SSH agent key-offer config (auth keys live in 1Password).
    mkdir -p "${HOME}/.config/1Password/ssh"
    link "${df}/ssh/1password-agent.toml" "${HOME}/.config/1Password/ssh/agent.toml"
  fi

  # ── Shell config ──────────────────────────────────────────────────────
  if _should_run_tags "symlinks shell"; then
    for f in .zshrc .zprofile .zshenv .hushlogin; do
      link "${df}/${f}" "${HOME}/${f}"
    done
  fi

  # Darwin-only symlinks.
  if [[ "$os" == "darwin" ]]; then
    if _should_run_tags "symlinks mise"; then
      mkdir -p "${HOME}/.config/mise"
      link "${df}/mise.toml" "${HOME}/.config/mise/config.toml"
    fi
  fi

  if _should_run_tags "symlinks sheldon"; then
    mkdir -p "${HOME}/.config/sheldon"
    link "${df}/sheldon/plugins.toml" "${HOME}/.config/sheldon/plugins.toml"
  fi

  if [[ "$os" == "darwin" ]]; then
    if _should_run_tags "symlinks ghostty"; then
      mkdir -p "${HOME}/.config/ghostty"
      link "${df}/ghostty/config" "${HOME}/.config/ghostty/config"
    fi

    if _should_run_tags "symlinks bat"; then
      mkdir -p "${HOME}/.config/bat"
      link "${df}/bat/config" "${HOME}/.config/bat/config"
    fi

    if _should_run_tags "symlinks atuin"; then
      mkdir -p "${HOME}/.config/atuin"
      link "${df}/atuin/config.toml" "${HOME}/.config/atuin/config.toml"
    fi

    if _should_run_tags "symlinks lazygit"; then
      mkdir -p "${HOME}/.config/lazygit"
      link "${df}/lazygit/config.yml" "${HOME}/.config/lazygit/config.yml"
    fi

    if _should_run_tags "symlinks helix"; then
      mkdir -p "${HOME}/.config/helix"
      link "${df}/helix/languages.toml" "${HOME}/.config/helix/languages.toml"
    fi

    if _should_run_tags "symlinks karabiner"; then
      mkdir -p "${HOME}/.config/karabiner"
      link "${df}/karabiner/karabiner.json" "${HOME}/.config/karabiner/karabiner.json"
    fi

    # zsh fragments — numeric-prefixed *.zsh only.
    if _should_run_tags "symlinks zsh"; then
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
  if _should_run_tags "symlinks gh"; then
    mkdir -p "${HOME}/.config/gh"
    link "${df}/gh/config.yml" "${HOME}/.config/gh/config.yml"
  fi

  # ── Claude Code ───────────────────────────────────────────────────────
  if _should_run_tags "symlinks claude"; then
    mkdir -p "${HOME}/.claude"
    link "${df}/dot-claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
    link "${df}/dot-claude/settings.json" "${HOME}/.claude/settings.json"
    link "${df}/dot-claude/agents" "${HOME}/.claude/agents"
    link "${df}/dot-claude/commands" "${HOME}/.claude/commands"

    local local_settings="${df}/dot-claude/settings.local.json"
    if [[ -f "$local_settings" ]]; then
      link "$local_settings" "${HOME}/.claude/settings.local.json"
    else
      printf '\033[2m  - claude/settings.local.json not present — skipping\033[0m\n'
    fi
  fi
}

# Helper: return true if any tag in the space-separated list TAGS_STR is in
# SYNC_ONLY_TAGS (or SYNC_ONLY_TAGS is empty = run everything).
# Called as: _should_run_tags "tag1 tag2 ..."
_should_run_tags() {
  local tags_str="$1"
  # If SYNC_ONLY_TAGS is unset/empty, everything runs.
  if [[ -z "${SYNC_ONLY_TAGS:-}" ]]; then
    return 0
  fi
  local t
  for t in $tags_str; do
    local o
    for o in ${SYNC_ONLY_TAGS}; do
      if [[ "$t" == "$o" ]]; then
        return 0
      fi
    done
  done
  return 1
}
