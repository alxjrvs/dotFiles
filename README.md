# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs). Owned end-to-end by a set of **self-contained shell scripts** fronted by a thin [`dot`](dot) dispatcher — they install base dependencies, create symlinks, apply macOS defaults, and power the prompt + statusline + Claude Code hooks. No Rust, no compiled binary; just `bash`, `git`, and `jq`.

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
| `dot sync --only=brew,mise` | Only the listed sections (tags: `brew mise sheldon symlinks claude gh git shell ssh ghostty bat atuin lazygit zsh git-template nvim karabiner lefthook macos linux prune`). |
| `dot update` | Bump everything to current — equivalent to `dot sync --upgrade`. |
| `dot doctor` | Read-only diagnostics: tool presence, symlink integrity, drift. Exits non-zero on failures. |
| `dot prune` | Delete `.bak` files, stale worktrees, orphan workers; bound state journals; age out stale session shards. |

## What's here

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | Fresh-machine entry point (exec `dot sync`) |
| `dot` | Thin dispatcher; the single dotfiles command on PATH. Resolves `DOTFILES_DIR`, execs the matching topic script. |
| `sync`, `doctor`, `render` | Top-level commands (install/resync, health check, `op://` template resolver) |
| `install/` | Numbered `NN-*.sh` sync modules (brew, mise, symlinks, macos, prune, …), sourced by `sync` in order |
| `prompt/` | `git-data` (git-state → cache) + `prompt-render` (cache → zsh PROMPT). Hot path. |
| `share/claude-statusline/` | Self-contained, curl-installable Claude Code statusline (`statusline.sh` + `subagent-statusline.sh`) with its own README |
| `hooks/` | One self-contained script per Claude Code hook event |
| `tests/` | `bats/` unit tests + `golden/` fixtures (byte-exact prompt/statusline references) |
| `.zshrc` | Thin loader — sources fragments from `~/.config/zsh/*.zsh` |
| `zsh/` | Numbered zsh fragments (exports, options, vi, plugins, completions, prompt, tools, aliases, functions) |
| `.zprofile`, `.zshenv` | Login env, including `DOTFILES_DIR` export |
| `.gitconfig`, `.gitmessage` | Git identity, commit template, signing (gpgSign overrides live in `~/.gitconfig.local`) |
| `git-template/hooks/pre-commit` | Global pre-commit hook (gitleaks; referenced by `core.hooksPath`) |
| `ghostty/config` | Ghostty terminal config |
| `atuin/config.toml` | Atuin (shell history) config |
| `lazygit/config.yml` | Lazygit config (Nord theme) |
| `bat/config` | Bat config |
| `ssh/config` | SSH client config (1Password agent, ControlMaster) |
| `karabiner/karabiner.json` | Karabiner-Elements rules (Caps Lock → Control) |
| `dot-claude/` | Claude Code: `CLAUDE.md`, `settings.json` (hooks dispatch via `dot hook <event>`) |
| `Brewfile` | `brew "mise"` + casks (GUI apps, fonts). All dev CLIs live in mise.toml. |
| `mise.toml` | Language toolchains + every dev CLI. Single update path via `mise upgrade`. |
| `sheldon/plugins.toml` | Zsh plugin config |
| `lefthook.yml` | Pre-commit/pre-push gate (shellcheck + shfmt + bats + doctor) for this repo |

## Claude Code integration

`dot-claude/` is symlinked into `~/.claude/` by `dot sync`. Contents:

- `CLAUDE.md` — user-level global instructions
- `settings.json` — permissions, env, hook commands (all `dot hook <event>`), `statusLine` → `dot statusline`, `subagentStatusLine` → `dot subagent-statusline`

The statusline is the self-contained `share/claude-statusline/statusline.sh` (context bar + Pro/Max rate-limit windows from native `rate_limits` JSON), reached via `dot statusline`. It's a drop-in you can `curl` onto any machine — see `share/claude-statusline/README.md`.

The wired Claude Code hook events route through `dot hook <event>`; the
event name maps 1:1 to a script in `hooks/`. The authoritative
event/script table lives in [CLAUDE.md](CLAUDE.md) under **Hook
dispatch** — one table, not two drifting copies.

## Tests

Shell unit tests run under [`bats`](https://github.com/bats-core/bats-core) (a managed mise tool) in `tests/bats/`. Golden fixtures in `tests/golden/` hold byte-exact reference output (regenerable snapshots of the current shell scripts) for `prompt/prompt-render`, the statusline, and the subagent statusline. Re-baseline after an intentional rendering change with `tests/verify-golden.sh --update` / `tests/verify-statusline.sh --update`, then commit the fixture diff. `lefthook.yml` runs `shellcheck` + `shfmt -i 2 -ci -sr` pre-commit and `bats` + `dot doctor` (skip-external) + `tests/verify-golden.sh` pre-push. CI (`.github/workflows/test.yml`, macOS) mirrors the lint + bats checks on push to `main` and every PR — it skips `dot doctor` and the golden verifiers, which depend on a fully provisioned machine.

## Git signing

`.gitconfig` configures SSH commit/tag signing but **does not** set `gpgSign = true` directly. The actual toggle lives in machine-local `~/.gitconfig.local` (bootstrapped by `dot sync`). This keeps fresh boxes from failing commits before SSH keys are present.

`dot sync` also bootstraps `~/.ssh/allowed_signers` from `~/.ssh/id_ed25519.pub` so `git log --show-signature` verifies your own commits.

To disable signing on a given machine, edit `~/.gitconfig.local`.

## gitleaks pre-commit

`core.hooksPath` (set in `.gitconfig`) points every repo at `git-template/hooks/pre-commit`, which runs `gitleaks protect --staged`. The hook also chain-runs any repo-local `pre-commit` if present. Emergency bypass `git commit --no-verify` is deny-listed for Claude in `dot-claude/settings.json` (`permissions.deny`), not by a hook.

## lefthook (this repo only)

`lefthook.yml` adds a pre-commit gate on staged shell files (`shellcheck` + `shfmt -i 2 -ci -sr` + gitleaks + `settings.json` validity) plus a pre-push gate (`bats tests/bats/` + `dot doctor` with `DOTFILES_DOCTOR_SKIP_EXTERNAL=1` + `tests/verify-golden.sh`). `dot sync` runs `lefthook install` automatically. The same lint + bats checks also run in CI (`.github/workflows/test.yml`).

## difftastic

Wired as a git difftool. Run with `git dft` (alias for `git difftool`) — uses [difft](https://difftastic.wilfred.me.uk/) for syntax-aware diffs.

## Secrets

1Password CLI (`op`) is the source of truth — there is no on-disk `.secrets` file. Patterns:

- **`op-run <cmd>`** (`zsh/80-functions.zsh`) — one-shot CLI injection. `op-run npm publish` resolves `op://` refs at exec time and never writes them anywhere.
- **`op://` references in config files** — pair with `op-run`. The wrapper resolves them just for the child process.
- **`gh` keychain auth** — the GitHub token lives in the macOS keychain (`gh auth login`, secure storage) and is deliberately NOT exported to the environment (a standing export would leak it into every subprocess). Resolve on demand with `gh auth token` when a tool needs it.
- **`direnv` + `op read` in `.envrc`** — for project-local env that must inherit at fork time. `direnv` is already hooked in `zsh/30-plugins.zsh`.

## Completions

`carapace` provides multi-shell completions for ~600 CLIs (gh, mise, op, kubectl, …). Loaded via `_zsh_cached_load` in `zsh/40-completions.zsh`, integrated with `fzf-tab` for preview windows. First shell after install regenerates the cache automatically.

## Packaging: Lean A (brew = casks, mise = dev CLIs)

The Brewfile holds **only** `brew "mise"` + casks (GUI apps, fonts, the 1Password CLI cask, the Claude desktop cask). Every dev CLI — language toolchains, git surface (gh, delta, lazygit, gitleaks, lefthook), file/text tools (bat, fd, ripgrep, jq, yq, eza, dust, glow, gdu), linters (shfmt, shellcheck), test tooling (bats), shell-init-time tools (sheldon, atuin, direnv, fzf, zoxide), and the Tier 3 escapees (supabase, carapace, watchexec, bottom, pueue, git-absorb, neovim) — lives in `mise.toml`.

The PATH wiring in `.zshenv` puts `~/.local/share/mise/shims` first so every mise-managed tool resolves in every shell context (interactive, non-interactive, git hooks, editor subprocesses) without waiting for `mise activate`. This makes it safe to ship shell-init dependencies (sheldon, atuin, direnv) from mise — they're on PATH before `.zshrc` fragments load.

Update path: `mise upgrade` (or `dot update`).

Rule: if you're about to add `brew "..."` to the Brewfile, stop. Put it in mise.toml unless it's mise itself or it's a cask. CLAUDE.md "Packaging policy" section restates this for tools.

## Editor: neovim

`alias v=nvim`, `alias vi=nvim`, `alias vim=nvim`. Configured by a single plugin-free `nvim/init.lua` (sensible defaults + native LSP via `vim.lsp.config`/`vim.lsp.enable`, requires Neovim 0.11+); LSP/formatter binaries install via mise. No plugin manager, no distro.

## Caps Lock → Control

Via Karabiner-Elements (Brewfile cask). Config is tracked at `karabiner/karabiner.json` and symlinked by `dot sync` to `~/.config/karabiner/karabiner.json`. On first launch grant Input Monitoring + Accessibility; the rebind (`caps_lock → left_control`, both device-scoped and profile-scoped) is then live. Survives sleep cycles and external keyboards.

## 1Password SSH agent

`ssh/config` points `IdentityAgent` at the 1Password 8 agent socket. Enable the agent in 1Password → Settings → Developer → "Use the SSH agent" before pushing this config — otherwise SSH breaks. Keys stored in your 1Password vault are then offered to every SSH host (with touch-to-approve if configured).

Commit signing piggybacks on the same SSH key via `gpg.format = ssh` in `.gitconfig`.

## Notes

- `DOTFILES_DIR` is exported from `.zshenv`; the default points to `$HOME/dotFiles`. Override via `DOTFILES_DIR=...` if your clone lives elsewhere. `dot` itself re-resolves it (env → dir of its resolved symlink target → `~/dotFiles`), so the repo is relocatable.
- Files containing PUA powerline glyphs (`zsh/50-prompt.zsh`, `prompt/prompt-render`, `share/claude-statusline/statusline.sh`) use escape syntax (`$'\uXXXX'` or `printf '\xNN'`) — ASCII source, evaluated at runtime. Safe to edit with the Claude Edit tool.
