# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs). Owned end-to-end by a set of **shell scripts** fronted by a thin [`dot`](dot) dispatcher — they install base dependencies, create symlinks, and apply macOS defaults. The prompt is [starship](https://starship.rs); the Claude Code statusline lives in its own repo ([claude-statusline](https://github.com/alxjrvs/claude-statusline)). No Rust, no compiled binary; just `bash`, `git`, and `jq`.

## Setup (fresh machine)

```bash
git clone https://github.com/alxjrvs/dotFiles ~/dotFiles
~/dotFiles/bootstrap.sh
```

`bootstrap.sh` is a few lines of shell: it `exec`s `~/dotFiles/dot sync`, which installs everything and symlinks `dot` onto your `PATH` at `~/.local/bin/dot`. After that everything is `dot <subcommand>`.

## Day-to-day

| Command | Job |
|---------|-----|
| `dot sync` | Idempotent re-sync. Installs missing tools, recreates broken symlinks. Fast on no-op. |
| `dot sync --upgrade` | Same + brew update/upgrade/cleanup + mise upgrade. |
| `dot sync --only=brew,mise` | Only the listed sections (tags: `brew mise sheldon symlinks ssh claude gh lefthook macos prune`). |
| `dot update` | Bump everything to current — equivalent to `dot sync --upgrade`. |
| `dot doctor` | Read-only diagnostics: tool presence, symlink integrity, drift. Exits non-zero on failures. |
| `dot prune` | Delete stale `.bak` backups left by `link()` overwrites (guarded). |

## What's here

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | Fresh-machine entry point (exec `dot sync`) |
| `dot` | Thin dispatcher; the single dotfiles command on PATH. Resolves `DOTFILES_DIR`, execs the matching topic script. |
| `sync`, `doctor` | Top-level commands (install/resync, health check) |
| `install/` | Numbered `NN-*.sh` sync modules (brew, mise, symlinks, macos, prune, …), sourced by `sync` in order |
| `lib/common.sh` | Shared helpers (`os_kind`, `resolve_dotfiles_dir`) sourced by `sync`/`doctor`/`95-prune` |
| `starship.toml` | starship prompt config (symlinked to `~/.config/starship.toml`) |
| `tests/` | `bats/` smoke suite — guards `install/95-prune.sh` (the only file-deleting subsystem) |
| `.zshrc` | Thin loader — sources fragments from `~/.config/zsh/*.zsh` |
| `zsh/` | Numbered zsh fragments (exports, options, vi, plugins, completions, prompt, tools, aliases, functions) |
| `.zprofile`, `.zshenv` | Login env, including `DOTFILES_DIR` export |
| `.gitconfig`, `.gitmessage` | Git identity, commit template, signing (gpgSign overrides live in `~/.gitconfig.local`) |
| `git-template/hooks/pre-commit` | Global pre-commit hook (gitleaks; referenced by `core.hooksPath`) |
| `ghostty/config` | Ghostty terminal config |
| `atuin/config.toml` | Atuin (shell history) config |
| `bat/config` | Bat config |
| `ssh/config` | SSH client config (1Password agent, ControlMaster) |
| `karabiner/karabiner.json` | Karabiner-Elements rules (Caps Lock → Control) |
| `dot-claude/` | Claude Code: `CLAUDE.md`, `settings.json` (minimal: agent teams, vim input, statusline) |
| `Brewfile` | `brew "mise"` + casks (GUI apps, fonts). All dev CLIs live in mise.toml. |
| `mise.toml` | Language toolchains + every dev CLI. Single update path via `mise upgrade`. |
| `sheldon/plugins.toml` | Zsh plugin config |
| `lefthook.yml` | Pre-commit lint gate (shellcheck + shfmt + gitleaks) + `bats` pre-push for this repo |

## Claude Code integration

`dot-claude/` is symlinked into `~/.claude/` by `dot sync`. Contents:

- `CLAUDE.md` — user-level global instructions
- `settings.json` — deliberately minimal: agent teams, `editorMode: vim`, `statusLine`/`subagentStatusLine` → `~/.local/bin/claude-statusline`

The statusline is a separate project — [claude-statusline](https://github.com/alxjrvs/claude-statusline). `dot sync` (claude tag) clones it to `~/Code/claude-statusline` (fast-forwards an existing clone) and runs its `install.sh`, which symlinks both scripts into `~/.local/bin`; `settings.json` references the installed path. `dot doctor` checks the symlinks are present.

## Tests

Shell unit tests run under [`bats`](https://github.com/bats-core/bats-core) (a managed mise tool) in `tests/bats/`. The suite is small on purpose: `prune.bats` guards `install/95-prune.sh` — the only file-deleting subsystem (guarded `.bak` cleanup) — so the collect/confirm/apply internals can be refactored safely. `lefthook.yml` runs the lint gate pre-commit and `bats tests/bats/` pre-push. No golden-snapshot harness, no CI: this is a personal repo, so rendering changes are eyeballed rather than byte-diffed.

## Git signing

Commits and tags are signed by **1Password** via `op-ssh-sign` (`gpg.format = ssh` in `.gitconfig`). `install/45-ssh.sh` reads the 1Password "GitHubSSH" key from the SSH agent and writes the machine-local `~/.gitconfig.local`: `gpgSign = true`, `gpg.ssh.program = op-ssh-sign`, and `user.signingkey = key::<that pubkey>`. There is no local signing key and no second ssh-agent. `gpgSign` stays machine-local so a box without 1Password doesn't fail commits before sync runs.

`dot sync` also appends the signing pubkey to `~/.ssh/allowed_signers` so `git log --show-signature` verifies locally. For GitHub to show **Verified**, register the same key under Settings → SSH and GPG keys → *Signing keys*, and verify your commit email.

To disable signing on a given machine, edit `~/.gitconfig.local`.

## gitleaks pre-commit

`core.hooksPath` (set in `.gitconfig`) points every repo at `git-template/hooks/pre-commit`, which runs `gitleaks protect --staged`. The hook also chain-runs any repo-local `pre-commit` if present. Emergency bypass `git commit --no-verify` is deny-listed for Claude in `dot-claude/settings.json` (`permissions.deny`), not by a hook.

## lefthook (this repo only)

`lefthook.yml` adds a pre-commit gate on staged shell files (`shellcheck` + `shfmt -i 2 -ci -sr` + gitleaks + `settings.json` validity) plus a `bats tests/bats/` pre-push gate. `dot sync` runs `lefthook install` automatically.

## Secrets

1Password CLI (`op`) is the source of truth — there is no on-disk `.secrets` file. Patterns:

- **`op-run <cmd>`** (`zsh/80-functions.zsh`) — one-shot CLI injection. `op-run npm publish` resolves `op://` refs at exec time and never writes them anywhere.
- **`op://` references in config files** — pair with `op-run`. The wrapper resolves them just for the child process.
- **`gh` keychain auth** — the GitHub token lives in the macOS keychain (`gh auth login`, secure storage) and is deliberately NOT exported to the environment (a standing export would leak it into every subprocess). Resolve on demand with `gh auth token` when a tool needs it.
- **`direnv` + `op read` in `.envrc`** — for project-local env that must inherit at fork time. `direnv` is already hooked in `zsh/30-plugins.zsh`.

## Packaging: Lean A (brew = casks, mise = dev CLIs)

The Brewfile holds **only** `brew "mise"` + casks (GUI apps, fonts, the 1Password CLI cask, the Claude desktop cask). Every dev CLI worth installing globally — language toolchains (node, bun), git surface (gh, delta, gitleaks, lefthook), file/text tools (bat, fd, ripgrep, jq, eza), linters (shfmt, shellcheck), test tooling (bats), shell-init-time tools (sheldon, atuin, direnv, fzf), the nvim language servers, and neovim — lives in `mise.toml`. Situational toolchains (rust, python, …) are installed per-project with `mise use`, not globally.

The PATH wiring in `.zshenv` puts `~/.local/share/mise/shims` first so every mise-managed tool resolves in every shell context (interactive, non-interactive, git hooks, editor subprocesses) without waiting for `mise activate`. This makes it safe to ship shell-init dependencies (sheldon, atuin, direnv) from mise — they're on PATH before `.zshrc` fragments load.

Update path: `mise upgrade` (or `dot update`).

Rule: if you're about to add `brew "..."` to the Brewfile, stop. Put it in mise.toml unless it's mise itself or it's a cask. CLAUDE.md "Packaging policy" section restates this for tools.

## Editor: neovim

`alias v=nvim`, `alias vi=nvim`, `alias vim=nvim`. Configured by a single plugin-free `nvim/init.lua` (sensible defaults + native LSP via `vim.lsp.config`/`vim.lsp.enable`, requires Neovim 0.11+); LSP/formatter binaries install via mise. No plugin manager, no distro.

## Caps Lock → Control

Via Karabiner-Elements (Brewfile cask). Config is tracked at `karabiner/karabiner.json` and symlinked by `dot sync` to `~/.config/karabiner/karabiner.json`. On first launch grant Input Monitoring + Accessibility; the rebind (`caps_lock → left_control`, both device-scoped and profile-scoped) is then live. Survives sleep cycles and external keyboards.

## 1Password SSH agent

`ssh/config` points `IdentityAgent` at the 1Password 8 agent socket. Enable the agent in 1Password → Settings → Developer → "Use the SSH agent" before pushing this config — otherwise SSH breaks. Keys stored in your 1Password vault are then offered to every SSH host (with touch-to-approve if configured).

Commit signing uses the same 1Password agent via `gpg.format = ssh` + `op-ssh-sign` in `.gitconfig` (see Git signing above).

## Notes

- `DOTFILES_DIR` is exported from `.zshenv`; the default points to `$HOME/dotFiles`. Override via `DOTFILES_DIR=...` if your clone lives elsewhere. `dot` itself re-resolves it (env → dir of its resolved symlink target → `~/dotFiles`), so the repo is relocatable.
- This repo no longer contains files with raw PUA powerline glyphs (the prompt is starship; the statusline moved to its own repo). If you add one, use escape sequences — Write/Edit silently strips raw codepoints.
