# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs). Owned end-to-end by [`dotctl`](dotctl/), a single Rust binary that installs base dependencies, creates symlinks, applies macOS defaults, and powers the prompt + statusline + Claude Code hooks.

## Setup (fresh machine)

```bash
git clone https://github.com/alxjrvs/dotFiles ~/dotFiles
~/dotFiles/bootstrap.sh
```

`bootstrap.sh` is ~10 lines of shell: installs rust (rustup), builds + installs `dotctl` to `~/.local/bin/`, then `exec`s `dotctl sync`. After that everything is `dotctl <subcommand>`.

## Day-to-day

| Command | Job |
|---------|-----|
| `dotctl sync` | Idempotent re-sync. Installs missing tools, recreates broken symlinks. Fast on no-op. |
| `dotctl sync --upgrade` | Same + brew update/upgrade/cleanup. |
| `dotctl sync --only=brew,mise` | Only the listed sections (tags: `brew mise sheldon symlinks claude fzf gh dotctl git shell ssh ghostty bat atuin lazygit zsh git-hooks lefthook macos linux`). |
| `dotctl update` | Bump everything to current — equivalent to `dotctl sync --upgrade`. |
| `dotctl doctor` | Read-only diagnostics: tool presence, symlink integrity, drift. Exits non-zero on failures. |

## What's here

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | Fresh-machine entry point (rust + dotctl install, then exec dotctl sync) |
| `dotctl/` | Rust binary: sync + update + doctor + git-data + hook + statusline + prompt-render |
| `.zshrc` | Thin loader — sources fragments from `~/.config/zsh/*.zsh` |
| `zsh/` | Numbered zsh fragments (exports, options, vi, plugins, completions, prompt, tools, aliases, functions) |
| `.zprofile`, `.zshenv` | Login env, including `DOTFILES_DIR` export |
| `.gitconfig`, `.gitmessage` | Git identity, commit template, signing (gpgSign overrides live in `~/.gitconfig.local`) |
| `git-hooks/pre-commit` | Global pre-commit hook (gitleaks; referenced by `core.hooksPath`) |
| `ghostty/config` | Ghostty terminal config |
| `atuin/config.toml` | Atuin (shell history) config |
| `lazygit/config.yml` | Lazygit config (Nord theme) |
| `bat/config` | Bat config |
| `ssh/config` | SSH client config (1Password agent, ControlMaster, Augment include) |
| `dot-claude/` | Claude Code: `CLAUDE.md`, `settings.json`, `agents/`, `commands/`, `statusline-command.sh` (hooks dispatch via `dotctl hook <event>`) |
| `scripts/theme.sh` | Nova color palette (Nord-derived); hex is canonical, decimals auto-derived. Will be absorbed into `dotctl prompt-render` in Phase 6. |
| `Brewfile` | Homebrew packages (casks + system libs only) |
| `mise.toml` | Language toolchains + CLI tools that lack Tier 3 bottles (uses mise's `github:`/`aqua:` backends) |
| `sheldon/plugins.toml` | Zsh plugin config |
| `lefthook.yml` | Pre-commit gate (shellcheck + shfmt) for this repo |
| `Makefile` | `make sync` / `update` / `doctor` / `lint` / `fmt` (thin shims over `dotctl`) |

## Claude Code integration

`dot-claude/` is symlinked into `~/.claude/` by `dotctl sync`. Contents:

- `CLAUDE.md` — user-level global instructions
- `settings.json` — permissions, env, hook commands (all `dotctl hook <event>`)
- `agents/` — custom subagent definitions
- `commands/` — custom slash commands
- `statusline-command.sh` — context bar + Pro/Max rate-limit windows from native `rate_limits` JSON

All 9 Claude Code hook events route through `dotctl hook <event>`:

| Event | Subcommand |
|-------|-----------|
| PreToolUse (Edit\|Write) | `dotctl hook lock-file-guard` |
| PreToolUse (Bash) | `dotctl hook policy-guard` |
| PostToolUse (Edit\|Write) | `dotctl hook format-on-save` |
| PostToolUse (Bash) | `dotctl hook trim-bash-output` |
| SessionStart | `dotctl hook session-start` |
| UserPromptSubmit | `dotctl hook user-prompt-submit` |
| CwdChanged | `dotctl hook cwd-changed` |
| PreCompact | `dotctl hook pre-compact` |
| PermissionDenied | `dotctl hook permission-denied` |

## Git signing

`.gitconfig` configures SSH commit/tag signing but **does not** set `gpgSign = true` directly. The actual toggle lives in machine-local `~/.gitconfig.local` (bootstrapped by `dotctl sync`). This keeps fresh boxes from failing commits before SSH keys are present.

`dotctl sync` also bootstraps `~/.ssh/allowed_signers` from `~/.ssh/id_ed25519.pub` so `git log --show-signature` verifies your own commits.

To disable signing on a given machine, edit `~/.gitconfig.local`.

## gitleaks pre-commit

`core.hooksPath = ~/.config/git/hooks` (set in `.gitconfig`) points every repo at `git-hooks/pre-commit`, which runs `gitleaks protect --staged`. The hook also chain-runs any repo-local `pre-commit` if present. Emergency bypass: `git commit --no-verify` (blocked by `dotctl hook policy-guard` when invoked through Claude).

## lefthook (this repo only)

`lefthook.yml` adds a pre-commit gate on staged shell files (`shellcheck` + `shfmt -d`) for the dotfiles repo itself. `dotctl sync` runs `lefthook install` automatically, which writes a repo-local `.git/hooks/pre-commit` — the global gitleaks hook (above) chain-calls it, so both run on commit here.

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

Apple Silicon Tahoe is a Tier 3 Homebrew configuration — several CLIs have no pre-built bottles. These live in `mise.toml` instead, resolved through mise's registry (short names), `github:` backend (release tarballs), or explicit `aqua:` paths:

| Tool | Entry in `mise.toml` |
|------|----------------------|
| supabase | `supabase = "latest"` |
| carapace | `carapace = "latest"` |
| watchexec | `watchexec = "latest"` |
| bottom (binary: `btm`) | `bottom = "latest"` |
| pueue | `"aqua:Nukesor/pueue/pueue" = "latest"` |
| git-absorb | `"aqua:tummychow/git-absorb" = "latest"` |
| helix (binary: `hx`) | `"github:helix-editor/helix" = { version = "latest", exe = "hx" }` |

The `alias btop="btm"` (`zsh/70-aliases.zsh`) covers the muscle-memory for top/htop. Run `dotctl sync --only=mise` to materialize.

## Editor: helix

Replaced AstroNvim viewer-mode. `alias v=hx`, `alias vim=hx`, `alias nvim=hx`. Zero plugins to maintain; one binary install via mise.

## Caps Lock → Escape

Via Karabiner-Elements (Brewfile cask). On first launch grant Input Monitoring + Accessibility, then enable "caps_lock → escape" in Simple Modifications. Survives sleep cycles and external keyboards.

## 1Password SSH agent

`ssh/config` points `IdentityAgent` at the 1Password 8 agent socket. Enable the agent in 1Password → Settings → Developer → "Use the SSH agent" before pushing this config — otherwise SSH breaks. Keys stored in your 1Password vault are then offered to every SSH host (with touch-to-approve if configured).

Commit signing piggybacks on the same SSH key via `gpg.format = ssh` in `.gitconfig`.

## Notes

- `DOTFILES_DIR` is exported from `.zshenv`; the default points to `$HOME/dotFiles`. Override via `DOTFILES_DIR=...` if your clone lives elsewhere.
- Files containing PUA powerline glyphs (`zsh/50-prompt.zsh`) use `$'\uXXXX'` escape syntax — ASCII source, evaluated at runtime. Safe to edit with the Claude Edit tool.
