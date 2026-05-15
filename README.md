# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs).

## Setup

```bash
./sync.sh             # Config + symlinks only (fast, idempotent)
./sync.sh --upgrade   # Also runs brew update / upgrade / cleanup (slow)
./sync.sh --help      # All flags and sections
```

`sync.sh` is idempotent — symlinks, Brewfile bundle, mise tools, macOS defaults. Safe to re-run.

## What's here

| Path | Purpose |
|------|---------|
| `.zshrc` | Thin loader — sources fragments from `~/.config/zsh/*.zsh` |
| `zsh/` | Numbered zsh fragments (exports, options, vi, plugins, completions, prompt, tools, aliases, functions) |
| `.zprofile`, `.zshenv` | Login env, including `DOTFILES_DIR` export |
| `.gitconfig`, `.gitmessage` | Git identity, commit template, signing (gpgSign overrides live in `~/.gitconfig.local`) |
| `git-hooks/pre-commit` | Global pre-commit hook (gitleaks; referenced by `core.hooksPath`) |
| `nvim/` | AstroNvim v5 config |
| `ghostty/config` | Ghostty terminal config |
| `gnar-term/gnar-term.json` | gnar-term config |
| `atuin/config.toml` | Atuin (shell history) config |
| `lazygit/config.yml` | Lazygit config (Nord theme) |
| `bat/config` | Bat config |
| `tmux/tmux.conf` | tmux config (prefix C-a, vi mode, true color, no plugins) |
| `ssh/config` | SSH client config (1Password agent, ControlMaster, Augment include) |
| `macos/LaunchAgents/` | macOS LaunchAgents (Caps→Esc via hidutil, fallback to Karabiner) |
| `dot-claude/` | Claude Code: `CLAUDE.md`, `settings.json`, `hooks/`, `agents/`, `commands/`, `statusline-command.sh` |
| `scripts/theme.sh` | Nova color palette (Nord-derived); hex is canonical, decimals auto-derived |
| `scripts/git-data.sh` | Git-state cache feeding the prompt and statusline |
| `Brewfile` | Homebrew packages |
| `mise.toml` | Language version pinning (node, python, deno, rust, bun) |
| `sheldon/plugins.toml` | Zsh plugin config |
| `Makefile` | `make sync` / `upgrade` / `doctor` / `lint` / `fmt` |

## Claude Code integration

`dot-claude/` is individually symlinked into `~/.claude/`. Contents:

- `CLAUDE.md` — user-level global instructions
- `settings.json` — permissions and env
- `hooks/` — event hooks (formatting, lock-file guard, statusline data, etc.)
- `agents/` — custom subagent definitions
- `commands/` — custom slash commands
- `statusline-command.sh` — context bar + Pro/Max rate-limit windows from native `rate_limits` JSON

## Git signing

`.gitconfig` configures SSH commit/tag signing but **does not** set `gpgSign = true` directly. The actual toggle lives in machine-local `~/.gitconfig.local` (bootstrapped by `sync.sh`). This keeps fresh boxes from failing commits before SSH keys are present.

`sync.sh` also bootstraps `~/.ssh/allowed_signers` from `~/.ssh/id_ed25519.pub` so `git log --show-signature` verifies your own commits.

To disable signing on a given machine, edit `~/.gitconfig.local`.

## gitleaks pre-commit

`core.hooksPath = ~/.config/git/hooks` (set in `.gitconfig`) points every repo at `git-hooks/pre-commit`, which runs `gitleaks protect --staged`. The hook also chain-runs any repo-local `pre-commit` if present. Emergency bypass: `git commit --no-verify`.

## difftastic

Wired as a git difftool. Run with `git dft` (alias for `git difftool`) — uses [difft](https://difftastic.wilfred.me.uk/) for syntax-aware diffs.

## Secrets

`.secrets` is gitignored and sourced by `zsh/00-exports.zsh` in interactive shells. Convention: only put values in there when subprocesses need them inherited at fork time (e.g., `GITHUB_PERSONAL_ACCESS_TOKEN` for Claude MCP servers). Everything else goes through 1Password CLI via the `op-run` wrapper (`zsh/80-functions.zsh`) — e.g., `op-run npm publish`. See `.secrets.example` for the pattern.

## Completions

`carapace` provides multi-shell completions for ~600 CLIs (gh, mise, op, kubectl, …). Loaded via `_zsh_cached_load` in `zsh/40-completions.zsh`, integrated with `fzf-tab` for preview windows. First shell after install regenerates the cache automatically.

## Tier 3 fallback installs

Apple Silicon Tahoe is a Tier 3 Homebrew configuration — several formulas have no pre-built bottles. `sync.sh` handles this automatically: after `brew bundle`, it installs `watchexec` / `pueue` / `bottom` via `cargo install` (rust toolchain comes from mise) and pulls `carapace` from its GitHub releases into `~/.local/bin/`. Each step is idempotent and short-circuits when the binary is already present. The Brewfile entries stay in place so the canonical install lights up automatically when upstream bottles arrive.

Note: `bottom` (binary `btm`) is used in place of `btop` since `btop` is C++ and lacks a Tier 3 build path via cargo.

## Caps Lock → Escape

Two-layer setup, belt-and-suspenders:

1. **hidutil** (primary) — `macos/LaunchAgents/com.alxjrvs.capsescape.plist` is symlinked into `~/Library/LaunchAgents/` and remaps Caps Lock to Escape at every login. Revert with `launchctl unload ~/Library/LaunchAgents/com.alxjrvs.capsescape.plist` + reboot, or `hidutil property --set '{"UserKeyMapping":[]}'` for the current session.
2. **Karabiner-Elements** (fallback) — installed via Brewfile cask. On first launch grant Input Monitoring + Accessibility, then toggle "caps_lock → escape" in Simple Modifications. Survives sleep cycles and external keyboards better than hidutil; left running alongside hidutil so Caps→Esc is never broken if one layer fails.

## 1Password SSH agent

`ssh/config` points `IdentityAgent` at the 1Password 8 agent socket. Enable the agent in 1Password → Settings → Developer → "Use the SSH agent" before pushing this config — otherwise SSH breaks. Keys stored in your 1Password vault are then offered to every SSH host (with touch-to-approve if configured).

Commit signing piggybacks on the same SSH key via `gpg.format = ssh` in `.gitconfig`.

## Migration notes

- **Docker Desktop → OrbStack**: Docker Desktop is removed from Brewfile in favor of `orbstack`. Containers and volumes do NOT migrate automatically — export anything you need from Docker Desktop before uninstalling. OrbStack ships its own `docker` CLI, so existing scripts keep working.
- **Rectangle → Raycast**: `rectangle` is removed in favor of `raycast`. Hotkeys do not transfer; rebind window-snap commands in Raycast preferences.
- **`bun` → mise**: `bun` is removed from Brewfile and pinned in `mise.toml` instead. Run `mise install` after pulling.

## Notes

- `scripts/*.sh` reference `"$DOTFILES_DIR/..."` (exported from `.zshenv`); the default points to `$HOME/dotFiles`. Override via `DOTFILES_DIR=...` if your clone lives elsewhere.
- Files containing PUA powerline glyphs (`zsh/50-prompt.zsh`) use `$'\uXXXX'` escape syntax — ASCII source, evaluated at runtime. Safe to edit with the Claude Edit tool.
- `code-review-graph` MCP is installed-on-demand via `uvx code-review-graph serve` — no persistent Python install required.
