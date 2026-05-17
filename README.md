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
| `atuin/config.toml` | Atuin (shell history) config |
| `lazygit/config.yml` | Lazygit config (Nord theme) |
| `bat/config` | Bat config |
| `ssh/config` | SSH client config (1Password agent, ControlMaster, Augment include) |
| `dot-claude/` | Claude Code: `CLAUDE.md`, `settings.json`, `hooks/`, `agents/`, `commands/`, `statusline-command.sh` |
| `scripts/theme.sh` | Nova color palette (Nord-derived); hex is canonical, decimals auto-derived |
| `scripts/git-data.sh` | Git-state cache feeding the prompt and statusline |
| `Brewfile` | Homebrew packages (casks + system libs only) |
| `mise.toml` | Language toolchains + CLI tools that lack Tier 3 bottles (uses mise's `cargo:`/`aqua:` backends) |
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

## lefthook (this repo only)

`lefthook.yml` adds a pre-commit gate on staged shell files (`shellcheck` + `shfmt -d`) for the dotfiles repo itself. `sync.sh` runs `lefthook install` automatically, which writes a repo-local `.git/hooks/pre-commit` — the global gitleaks hook (above) chain-calls it, so both run on commit here.

## difftastic

Wired as a git difftool. Run with `git dft` (alias for `git difftool`) — uses [difft](https://difftastic.wilfred.me.uk/) for syntax-aware diffs.

## Secrets

1Password CLI (`op`) is the source of truth — there is no on-disk `.secrets` file. Patterns:

- **`op-run <cmd>`** (`zsh/80-functions.zsh`) — one-shot CLI injection. `op-run npm publish` resolves `op://` refs at exec time and never writes them anywhere.
- **`op://` references in config files** — pair with `op-run`. The wrapper resolves them just for the child process.
- **`gh auth token` keychain fallback** — `zsh/00-exports.zsh` derives `GITHUB_PERSONAL_ACCESS_TOKEN` from the gh keychain at shell start, so subprocesses (Claude MCP, scripts) inherit it without plaintext on disk.
- **`direnv` + `op read` in `.envrc`** — for project-local env that must inherit at fork time. `direnv` is already hooked in `zsh/30-plugins.zsh`.

## Completions

`carapace` provides multi-shell completions for ~600 CLIs (gh, mise, op, kubectl, …). Loaded via `_zsh_cached_load` in `zsh/40-completions.zsh`, integrated with `fzf-tab` for preview windows. First shell after install regenerates the cache automatically.

## Tier 3 tools via mise

Apple Silicon Tahoe is a Tier 3 Homebrew configuration — several CLIs have no pre-built bottles. These live in `mise.toml` instead, resolved through mise's registry (short names) or via explicit `aqua:` paths where the registry doesn't have an alias:

| Tool | Entry in `mise.toml` |
|------|----------------------|
| supabase | `supabase = "latest"` |
| carapace | `carapace = "latest"` |
| watchexec | `watchexec = "latest"` |
| bottom (binary: `btm`) | `bottom = "latest"` |
| pueue | `"aqua:Nukesor/pueue/pueue" = "latest"` |
| git-absorb | `"aqua:tummychow/git-absorb" = "latest"` |

The `alias btop="btm"` (`zsh/70-aliases.zsh`) covers the muscle-memory for top/htop. Run `mise install` to materialize everything.

## Caps Lock → Escape

Via Karabiner-Elements (Brewfile cask). On first launch grant Input Monitoring + Accessibility, then enable "caps_lock → escape" in Simple Modifications. Survives sleep cycles and external keyboards.

## 1Password SSH agent

`ssh/config` points `IdentityAgent` at the 1Password 8 agent socket. Enable the agent in 1Password → Settings → Developer → "Use the SSH agent" before pushing this config — otherwise SSH breaks. Keys stored in your 1Password vault are then offered to every SSH host (with touch-to-approve if configured).

Commit signing piggybacks on the same SSH key via `gpg.format = ssh` in `.gitconfig`.

## Migration notes

- **Docker Desktop → OrbStack**: Docker Desktop is removed from Brewfile in favor of `orbstack`. Containers and volumes do NOT migrate automatically — export anything you need from Docker Desktop before uninstalling. OrbStack ships its own `docker` CLI, so existing scripts keep working.
- **Rectangle → Raycast**: `rectangle` is removed in favor of `raycast`. Hotkeys do not transfer; rebind window-snap commands in Raycast preferences.
- **`bun` → mise**: `bun` is removed from Brewfile and pinned in `mise.toml` instead. Run `mise install` after pulling.
- **`supabase` → mise**: `supabase/tap/supabase` is removed from Brewfile (the tap's formula breaks on Tier 3 — missing top-level URL). Now installed via mise's aqua backend (`aqua:supabase/cli`); pinned in `mise.toml`. Run `mise install` after pulling.
- **Tier 3 cargo/curl dance → mise**: `carapace` / `watchexec` / `pueue` / `bottom` / `git-absorb` moved to `mise.toml` (mise's `cargo:`/`aqua:` backends). The old `install/00-brew.sh` Tier 3 fallback section (cargo install loop + `curl | jq` for carapace) is deleted. `btop` brew formula dropped — `alias btop="btm"` covers the slot.

## Notes

- `scripts/*.sh` reference `"$DOTFILES_DIR/..."` (exported from `.zshenv`); the default points to `$HOME/dotFiles`. Override via `DOTFILES_DIR=...` if your clone lives elsewhere.
- Files containing PUA powerline glyphs (`zsh/50-prompt.zsh`) use `$'\uXXXX'` escape syntax — ASCII source, evaluated at runtime. Safe to edit with the Claude Edit tool.
