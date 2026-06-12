# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs). Owned end-to-end by a set of **shell scripts** fronted by a thin [`dot`](dot) dispatcher — they install base dependencies, create symlinks, and apply macOS defaults. The prompt is [starship](https://starship.rs); the Claude Code statusline lives in its own repo ([claude-statusline](https://github.com/alxjrvs/claude-statusline)). Just `bash`, `git`, and `jq`.

## Setup (fresh machine)

```bash
git clone https://github.com/alxjrvs/dotFiles ~/dotFiles
~/dotFiles/bootstrap.sh
```

`bootstrap.sh` is a few lines of shell: it `exec`s `~/dotFiles/dot sync`, which installs everything and symlinks `dot` onto your `PATH` at `~/.local/bin/dot`. After that everything is `dot <subcommand>`.

## Making it yours

Everything here is policy except a handful of identity values a copier edits:

| What | Where |
|------|-------|
| Git name + email | `.gitconfig` `[user]` |
| 1Password signing-key item name | `install/45-ssh.sh` (`_SIGNING_KEY_NAME`, default `GitHubSSH`) |
| GitHub MCP token reference | `gh/gh-mcp-auth-header` (`OP_REF`, an `op://` path) |
| 1Password vault filter for SSH keys | `ssh/1password-agent.toml` |
| Statusline source repo | `install/60-claude.sh` (`repo`/`dir`) — or delete `_claude_install_statusline` + the `statusLine` keys in `dot-claude/settings.json` to drop it |
| Editor / identity prefs | `dot-claude/CLAUDE.md` |

Everything else is policy, not identity — copy it as-is.

## Day-to-day

| Command | Job |
|---------|-----|
| `dot sync` | Idempotent re-sync. Installs missing tools, recreates broken symlinks. Fast on no-op. |
| `dot sync --upgrade` | Same + brew update/upgrade/cleanup + mise upgrade. |
| `dot sync --only=brew,mise` | Only the listed sections (tags: `brew mise sheldon symlinks ssh claude lefthook macos`). |
| `dot update` | Bump everything to current — equivalent to `dot sync --upgrade`. |
| `dot doctor` | Read-only diagnostics: tool presence, symlink integrity (missing *and* orphaned), drift. Exits non-zero on failures. |
| `dot doctor --fix` | Same diagnostics, plus repair the symlink contract: reap orphaned symlinks *and* relink any entry that's missing, a non-symlink file, or pointing at the wrong target (doctor's only mutation). |

## What's here

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | Fresh-machine entry point (exec `dot sync`) |
| `dot` | Thin dispatcher; the single dotfiles command on PATH. Resolves `DOTFILES_DIR`, execs the matching topic script. |
| `sync`, `doctor` | Top-level commands (install/resync, health check) |
| `install/` | Numbered `NN-*.sh` sync modules (brew, mise, symlinks, macos, …), sourced by `sync` in order |
| `lib/common.sh` | Shared helpers (`os_kind`, `resolve_dotfiles_dir`, `link()`) sourced by `sync`/`doctor` |
| `starship.toml` | starship prompt config (symlinked to `~/.config/starship.toml`) |
| `.zshrc` | Thin loader — sources fragments from `~/.config/zsh/*.zsh` |
| `zsh/` | Numbered zsh fragments (exports, options, vi, plugins, completions, prompt, tools, aliases, functions) |
| `.zprofile`, `.zshenv` | Login env, including `DOTFILES_DIR` export |
| `.gitconfig`, `.gitmessage` | Git identity, commit template, signing (gpgSign overrides live in `~/.gitconfig.local`) |
| `git-template/hooks/pre-commit` | Per-repo gitleaks hook, copied into new repos at `git init` via `init.templateDir` |
| `ghostty/config` | Ghostty terminal config |
| `atuin/config.toml` | Atuin (shell history) config |
| `bat/config` | Bat config |
| `ssh/config` | SSH client config (1Password agent, ControlMaster) |
| `karabiner/karabiner.json` | Karabiner-Elements rules (Caps Lock → Control) |
| `dot-claude/` | Claude Code: `CLAUDE.md` + `settings.json` (symlinked into `~/.claude/`), `REFERENCE.md` (on-demand notes, not symlinked) |
| `Brewfile` | `brew "mise"` + casks (GUI apps, fonts). All dev CLIs live in mise.toml. |
| `mise.toml` | Language toolchains + every dev CLI. Single update path via `mise upgrade`. |
| `sheldon/plugins.toml` | Zsh plugin config |
| `lefthook.yml` | Pre-commit lint gate (shellcheck + shfmt + gitleaks) for this repo |

## Claude Code integration

`dot-claude/` is symlinked into `~/.claude/` by `dot sync`. Contents:

- `CLAUDE.md` — user-level global instructions
- `settings.json` — deliberately minimal (agent teams, vim input, statusline, auto mode); the full list lives in `dot-claude/CLAUDE.md`

The statusline is a separate project — [claude-statusline](https://github.com/alxjrvs/claude-statusline). `dot sync` (claude tag) clones it to `~/Code/claude-statusline` (fast-forwards an existing clone) and runs its `install.sh`, which symlinks both scripts into `~/.local/bin`; `settings.json` references the installed path. `dot doctor` checks the symlinks are present.

## Linting

`lefthook.yml` runs a pre-commit gate on staged shell files: `shellcheck`, `shfmt -i 2 -ci -sr`, `gitleaks protect`, and a `settings.json` validity check. `dot sync` installs the hooks. No test suite and no CI — this is a personal repo; the lint gate is the only automation.

## Git signing

Commits and tags are signed by **1Password** via `op-ssh-sign` (`gpg.format = ssh` in `.gitconfig`). `install/45-ssh.sh` reads the 1Password "GitHubSSH" key from the SSH agent and writes the machine-local `~/.gitconfig.local`: `gpgSign = true`, `gpg.ssh.program = op-ssh-sign`, and `user.signingkey = key::<that pubkey>`. Auth and signing share the single 1Password agent and key. `gpgSign` stays machine-local so a box without 1Password doesn't fail commits before sync runs.

`dot sync` also appends the signing pubkey to `~/.ssh/allowed_signers` so `git log --show-signature` verifies locally. For GitHub to show **Verified**, register the same key under Settings → SSH and GPG keys → *Signing keys*, and verify your commit email.

To disable signing on a given machine, edit `~/.gitconfig.local`.

## gitleaks pre-commit

`init.templateDir` (set in `.gitconfig`) copies `git-template/hooks/pre-commit` into each new repo's `.git/hooks/` at `git init`/`git clone` time; it runs `gitleaks protect --staged`. Lefthook-managed repos overwrite that hook with lefthook's own and run gitleaks through lefthook instead. Repos created before the template was in place need a one-shot copy: `cp ~/.config/git/template/hooks/pre-commit <repo>/.git/hooks/pre-commit`. Emergency bypass: `git commit --no-verify`.

## lefthook (this repo only)

`lefthook.yml` adds a pre-commit gate on staged shell files (`shellcheck` + `shfmt -i 2 -ci -sr` + gitleaks + `settings.json` validity). `dot sync` runs `lefthook install` automatically.

## Secrets

1Password CLI (`op`) is the source of truth for secrets. Patterns:

- **`op run -- <cmd>`** — one-shot CLI injection. `op run -- npm publish` resolves `op://` refs at exec time and never writes them anywhere (masking on by default).
- **`op://` references in config files** — pair with `op run --`, which resolves them just for the child process.
- **`gh` keychain auth** — the GitHub token lives in the macOS keychain (`gh auth login`, secure storage) and is deliberately NOT exported to the environment (a standing export would leak it into every subprocess). Resolve on demand with `gh auth token` when a tool needs it.
- **`mise` `[env]` + `op`** — for project-local env that must inherit at fork time, put it in the project's `mise.toml` `[env]` and resolve secrets via `{{ exec(command='op read …') }}`. mise activates on `cd`.

## Packaging: Lean A (brew = casks, mise = dev CLIs)

The Brewfile holds **only** `brew "mise"`, system libraries that pre-built CLIs link against (currently `openssl@3`, which `sheldon` dyld-links against), and casks (GUI apps, fonts, the 1Password CLI cask, the Claude desktop cask). Every dev CLI worth installing globally — language toolchains (node, bun), git surface (gh, delta, gitleaks, lefthook), file/text tools (bat, fd, ripgrep, jq, eza), linters (shfmt, shellcheck), shell-init-time tools (sheldon, atuin, fzf), the nvim language servers, and neovim — lives in `mise.toml`. Situational toolchains (rust, python, …) are installed per-project with `mise use`, not globally.

The PATH wiring in `.zshenv` puts `~/.local/share/mise/shims` first so every mise-managed tool resolves in every shell context (interactive, non-interactive, git hooks, editor subprocesses) without waiting for `mise activate`. This makes it safe to ship shell-init dependencies (sheldon, atuin, fzf) from mise — they're on PATH before `.zshrc` fragments load.

Update path: `mise upgrade` (or `dot update`).

Rule: if you're about to add `brew "..."` to the Brewfile, stop. Put it in mise.toml unless it's mise itself, a cask, or a system library with no mise equivalent.

## Editor: neovim

`alias v=nvim`, `alias vi=nvim`, `alias vim=nvim`. Configured by a single plugin-free `nvim/init.lua` (sensible defaults + native LSP via `vim.lsp.config`/`vim.lsp.enable`, requires Neovim 0.11+); LSP/formatter binaries install via mise. No plugin manager, no distro.

## Caps Lock → Control

Via Karabiner-Elements (Brewfile cask). Config is tracked at `karabiner/karabiner.json` and symlinked by `dot sync` to `~/.config/karabiner/karabiner.json`. On first launch grant Input Monitoring + Accessibility; the rebind (`caps_lock → left_control`, both device-scoped and profile-scoped) is then live. Survives sleep cycles and external keyboards.

Karabiner rather than the native `hidutil`/`defaults` modifier remap because its keyboard wildcard covers every device automatically — the native remap is keyed per keyboard vendor/product ID and must be re-applied for each new keyboard.

## 1Password SSH agent

`ssh/config` points `IdentityAgent` at the 1Password 8 agent socket. Enable the agent in 1Password → Settings → Developer → "Use the SSH agent" before pushing this config — otherwise SSH breaks. Keys stored in your 1Password vault are then offered to every SSH host (with touch-to-approve if configured).

Commit signing uses the same 1Password agent via `gpg.format = ssh` + `op-ssh-sign` in `.gitconfig` (see Git signing above).

## Notes

- `DOTFILES_DIR` is exported from `.zshenv`; the default points to `$HOME/Code/dotFiles`. Override via `DOTFILES_DIR=...` if your clone lives elsewhere. `dot` itself re-resolves it (env → dir of its resolved symlink target → `~/dotFiles`), so the repo is relocatable.
- Use escape sequences, not raw PUA powerline glyphs, in any tracked file — Write/Edit silently strips raw codepoints.
