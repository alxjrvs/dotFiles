---
description: Audit dotfiles environment — health, symlinks, brew/mise drift
---

# /sync-check

Verify the dotfiles install on this machine is in a known-good state. Report by category; surface anything actionable.

## Steps

1. **Health module** — Run `~/dotFiles/sync.sh --only=health` and surface the output verbatim.
2. **Symlink audit** — Verify every expected symlink in `$HOME` and `~/.config/` points back to `~/dotFiles/`. Reference list:
   - `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.hushlogin`
   - `~/.gitconfig`, `~/.gitmessage`, `~/.gitignore`, `~/.editorconfig`, `~/.ripgreprc`, `~/.fdignore`
   - `~/.config/{bat,ghostty,atuin,lazygit,gh,mise,sheldon,zsh}/`
   - `~/.config/git/hooks/pre-commit`
   - `~/.claude/{CLAUDE.md,settings.json,hooks,agents,commands,statusline-command.sh}`
   - `~/.config/nvim` (symlinks to `nvim/` directory)
   - `~/.ssh/config`
   For each: confirm symlink exists, points to the right `~/dotFiles/` source. Report any broken / missing / wrong-target links.
3. **Brewfile drift** — `brew bundle check --file=~/dotFiles/Brewfile`. List missing formulae/casks.
4. **mise drift** — `mise current` vs `mise.toml`. Report tools not installed at expected version.
5. **Stale local files** — Flag any `~/.gitconfig.local`, `~/.claude/settings.local.json` that exist but don't match expected shape (the latter is fine if user has machine-local overrides).
6. **lefthook** — Confirm `.git/hooks/pre-commit` exists in `~/dotFiles/.git/hooks/` and was written by lefthook. If not, run `lefthook install` from `~/dotFiles/`.

## Report format

One section per category. If all clean, a single line: "✓ All categories pass." Otherwise, group findings under headers (Health / Symlinks / Brewfile / mise / Local / lefthook) with a one-line fix suggestion per item.

Do not modify anything without asking first — this is a read-only audit by default.
