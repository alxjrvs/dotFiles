# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A macOS dotfiles repository owned end-to-end by **self-contained shell scripts** fronted by a thin [`dot`](dot) dispatcher — they install base dependencies, create symlinks, apply macOS defaults, and drive the Claude Code statusline. The shell prompt is [starship](https://starship.rs) (config in `starship.toml`). No Rust, no compiled binary: just `bash`, `git`, and `jq`.

There is no `dotctl/` crate anymore — it was replaced by these shell scripts (this branch/PR). Each subsystem lives in its own topic folder and every script is **self-contained**: the small helpers it needs (logging, os/host detection, symlink `link()`, jq getters, the git-cache path hash, color/gradient math) are inlined at the top of the script rather than sourced from a shared library. Duplication across scripts is intentional — it keeps each folder isolated and individually shareable.

Source of truth for setup behavior is `sync` + `install/*.sh`. The shell prompt is starship (`starship.toml`, symlinked to `~/.config/starship.toml`). Source of truth for the statusline is `share/claude-statusline/statusline.sh`.

## Key Commands

```bash
dot sync                # Idempotent install/resync. Fast on no-op. Prompts to clean .bak files at the end (default yes).
dot sync --upgrade      # Same + brew update/upgrade/cleanup + mise upgrade.
dot sync --only=brew,mise   # Only the listed section tags.
dot update              # Bump everything (equivalent to sync --upgrade).
dot doctor              # Read-only health check; exits non-zero on failures.
dot prune               # Find + delete .bak files, stale worktrees, orphan workers.
bats tests/bats/        # Run the shell unit-test suite.
lefthook run pre-commit # shellcheck + shfmt -i 2 -ci -sr over staged shell files.
```

Fresh machine: `git clone … ~/dotFiles && ~/dotFiles/bootstrap.sh` (execs `dot sync`).

## Architecture

### The `dot` dispatcher + topic folders

`dot` (repo root) is a ~40-line bash script — the single command symlinked onto `PATH` at `~/.local/bin/dot`. It resolves `DOTFILES_DIR` once, then execs the matching topic script, passing args through:

| Subcommand | Execs | Purpose |
|------------|-------|---------|
| `dot sync` | `./sync` | Install/resync. Tag-gated steps (`--only=<tag,...>`). Idempotent. |
| `dot update` | `./sync --upgrade` | Bump everything. |
| `dot doctor` | `./doctor` | Read-only diagnostics; exits non-zero on failures. |
| `dot prune` | `./install/95-prune.sh` | `.bak` / stale-worktree / orphan-worker cleanup. Flags pass through (`-n` dry-run, `-y` unattended). Also runs at the tail of every full `dot sync`. |
| `dot statusline` | `share/claude-statusline/statusline.sh` | Read Claude Code JSON on stdin, emit 3–6 lines with progress bars. |
| `dot subagent-statusline` | `share/claude-statusline/subagent-statusline.sh` | Subagent task statusline. |

`DOTFILES_DIR` resolution lives only in `dot`: `$DOTFILES_DIR` env → directory of `dot`'s resolved symlink target → legacy `~/dotFiles`; first candidate that is a directory containing a `Brewfile` wins. The top-level scripts (`sync`, `doctor`, `share/claude-statusline/*`) are standalone — run them directly for development. The `install/NN-*.sh` modules are **sync-sourced, not standalone**: `sync` defines and exports the shared helpers (`os_kind`, `host_id`, `link`, …) before sourcing each module, so the modules carry no inlined helpers of their own. The sole exception is `install/95-prune.sh`, which keeps its own guard block + helpers because it also runs standalone (`./install/95-prune.sh` / `dot prune`).

### sync / install modules

`sync` sources `install/NN-*.sh` modules in numeric order; each declares its tags and a `run` function, gated by a tag filter (`--only=<tags>`). Modules: `00-brew 30-mise 40-symlinks 45-ssh 60-claude 70-gh 80-git-maint 85-lefthook 90-macos 95-prune`. To add a sync section, add an `install/NN-name.sh` module, give it a tag, and `sync` will pick it up. macOS defaults data + `audit` live in `90-macos.sh`. (`30-mise` also locks sheldon plugins — sheldon is a mise tool, so its binary only exists after `mise install`.)

### Symlink Model

`link()` (defined in `sync`, exported to the install modules) creates idempotent symlinks. On conflict, behavior depends on `$LINK_MODE`: `overwrite` (move existing to `.bak`, then link, set via `-f`), `skip` (`-s`), or default `interactive` (prompt). Mapping:

| Source | Destination |
|--------|-------------|
| `.zshrc`, `.zprofile`, `.zshenv`, `.hushlogin` | `~/` |
| `.gitconfig`, `.gitmessage`, `.gitignore`, `.editorconfig` | `~/` |
| `.ripgreprc`, `.fdignore` | `~/` |
| `zsh/[0-9]*.zsh` | `~/.config/zsh/` (sourced in numeric order by thin `.zshrc`) |
| `bat/config` | `~/.config/bat/config` |
| `mise.toml` | `~/.config/mise/config.toml` |
| `sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `starship.toml` | `~/.config/starship.toml` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `nvim/init.lua` | `~/.config/nvim/init.lua` |
| `karabiner/karabiner.json` | `~/.config/karabiner/karabiner.json` |
| `atuin/config.toml` | `~/.config/atuin/config.toml` |
| `gh/config.yml` | `~/.config/gh/config.yml` |
| `ssh/config` | `~/.ssh/config` (mode 600) |
| `ssh/1password-agent.toml` | `~/.config/1Password/ssh/agent.toml` |
| `ssh/git-ssh-sign` | `~/.local/bin/git-ssh-sign` (gpg.ssh.program wrapper) |
| `gh/gh-mcp-auth-header` | `~/.local/bin/gh-mcp-auth-header` (github MCP headersHelper → `gh auth token`) |
| `git-template/hooks/pre-commit` | `~/.config/git/template/hooks/pre-commit` (referenced by `core.hooksPath`) |
| `dot` | `~/.local/bin/dot` |
| `dot-claude/{CLAUDE.md, settings.json}` | `~/.claude/` (individually) |

Everything is symlinked; there are no read-in-place or compiled-in files.

### Claude Code Configuration (`dot-claude/`)

Each entry is symlinked individually into `~/.claude/` by `dot sync` (claude tag):

- `CLAUDE.md` — user-level global instructions (identity, preferences).
- `settings.json` — **deliberately minimal**: agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` + `teammateMode`), `editorMode: vim`, `statusLine` (→ `dot statusline`), `subagentStatusLine` (→ `dot subagent-statusline`). Nothing else — no permissions arrays, no sandbox block, no hook wiring, no plugins. Don't add settings without asking.

There is no `agents/`, `commands/`, or `hooks/` directory — custom subagents, slash commands, and hook scripts were all dropped (unused).

### Tests

Shell unit tests run under `bats` (a managed mise tool) in `tests/bats/`. The suite is deliberately small: `prune.bats` guards the only subsystem that wields `rm -rf` (`install/95-prune.sh`) — non-TTY never deletes, the `.bak` safety guard, dry/auto effects. `lefthook.yml` runs `shellcheck` + `shfmt -i 2 -ci -sr` + gitleaks + a `settings.json` validity check pre-commit, and `bats tests/bats/` pre-push. There is no golden-snapshot harness and no CI — rendering changes are eyeballed, not byte-diffed (this is a personal repo, not a published library).

## Packaging policy: Lean A (brew = casks, mise = dev CLIs)

Brewfile holds **only**: `mise` (chicken-and-egg bootstrap), casks (GUI apps, fonts), and any system library that has no mise equivalent.

`mise.toml` holds: all language toolchains AND all dev CLIs (including `jq`, `bats`, `shellcheck`, `shfmt`). Use the registry short-name where it resolves; fall back to `aqua:` then `github:` backends.

If you're about to add a CLI to `Brewfile`, stop — put it in `mise.toml` unless it's `mise` itself or it's a cask.

## Terminal: Ghostty

Ghostty is the chosen terminal emulator. The cask installs the .app; you
launch the app directly (no `~/.local/bin/ghostty` CLI shim — that was a
convenience wrapper, now removed). `dot sync` symlinks `ghostty/config`
to `~/.config/ghostty/config`, which `dot doctor` validates via the
symlink integrity check.

No other terminal emulators (iTerm2, WezTerm, Kitty, Alacritty, Warp)
are managed by this repo. If you find yourself adding one, stop —
Ghostty is the answer in this stack; revisit only if Mitchell Hashimoto
abandons it.

## Multi-host overlays

Two machines (M3 Air + M2 Pro). Host detection is the inlined `host_id`
helper: `scutil --get LocalHostName` substring match →
`air|pro|unknown`, with `DOTFILES_HOST=air|pro` env override
(also exposed as `dot sync --host=<name>` for dry-running the
other host's config locally).

Per-host surfaces today:

- **macOS defaults** — `install/90-macos.sh` carries the shared baseline;
  per-host overlays add or override entries by `(domain, key)` and the
  effective list is merged for the current host. `dot doctor` audits
  against the current host's effective list.
- **Brewfile** — shared `Brewfile` installs everywhere; if
  `Brewfile.<host>` exists, it installs AFTER the shared file (purely
  additive, brew bundle is idempotent). Use for formulae/casks only
  one host needs.

Symlinks, mise.toml, sheldon, and zsh fragments are intentionally
shared — divergence there isn't worth the overlay surface today.

## Secrets management

1Password CLI (`op`) is the source of truth. There is no `.secrets` file. Use the patterns below in priority order; drop down a tier only when the one above doesn't apply.

### Patterns

**1. `op-run` wrapper — one-shot CLI injection** (`zsh/80-functions.zsh`)
```sh
op-run npm publish               # = op run -- npm publish   (masking left ON)
```
For any CLI invocation that reads a token from env. Nothing is exported to the shell session; `op` resolves `op://` references at exec time only. Masking is deliberately **on** (no `--no-masking`): the child gets the real resolved value but 1Password redacts it from the child's stdout/stderr, so secrets don't leak into output an agent/transcript could capture. If a tool genuinely breaks under masked output, add a one-off wrapper and document why rather than weakening this default.

**2. `op://` references in config files**
```ini
# .npmrc
//registry.npmjs.org/:_authToken=op://Personal/npm/credential
```
Pair with `op-run` (pattern 1) — the wrapper resolves the references just for the child process.

**3. `gh auth token` keychain resolution — GitHub specifically**
The token lives in the macOS keychain (managed by `gh auth login`, secure storage), never on disk, and is NOT exported to the environment (a standing export would leak it into every subprocess). Resolve it on demand — `GITHUB_TOKEN="$(gh auth token)" some-tool` — only when a tool actually needs it.

**4. `direnv` + `op read` — project-local inheritance**
For values a project's subprocesses must inherit at fork time, use a per-project `.envrc` that resolves through `op read`:
```sh
# .envrc
export STRIPE_KEY="$(op read 'op://Personal/stripe/credential')"
```
`direnv` (already hooked in `zsh/30-plugins.zsh`) resolves on `cd`. Pair with a checked-in `.envrc.template`.

### Rules

- **Never commit a plaintext token** to any file. Use `op://` references or `op-run` instead.
- **Never add a token to a config file as plaintext.** If `.npmrc`-shape tools need credentials, use `op://` refs + `op-run`.
- **If you find a plaintext token anywhere**, revoke first, then migrate to `op` or a keychain CLI.
- `gitleaks` runs as a global pre-commit hook (`git-template/hooks/pre-commit`); it's a backstop, not the policy.

## Guardrails

Pause and confirm with the user before doing any of these:

- **Dependency lockfiles** (any file matching `*-lock*` or `*.lock*`): never edit by hand.
- **`link()` symlink semantics**: the `link()` function prompts on conflict (interactive `$LINK_MODE`) unless `-f` or `-s` is passed. Do not change the default behavior to auto-overwrite.
- **The prompt is starship**: configured by `starship.toml` (symlinked to `~/.config/starship.toml`), initialized via `eval "$(starship init zsh)"` in `zsh/50-prompt.zsh`. Keep the config minimal — there is no bespoke prompt renderer to maintain.
- **Self-contained rule**: scripts inline their own helpers; there is no `shared/` library layer. Don't introduce one — keep each topic folder independently runnable and shareable.
- **Neovim is plugin-free**: the editor is configured by a single `nvim/init.lua` (sensible defaults + native LSP via `vim.lsp.config`/`vim.lsp.enable`, requires Neovim 0.11+). There is no plugin manager (lazy.nvim, packer) and no AstroNvim/LazyVim distro — don't propose adding one; keep the config to a single self-contained `init.lua`. (Historical: this stack used helix before; if you see `helix`/`hx`, it's gone.)

## Important Gotchas

- **Powerline glyphs (U+E0B0, U+E0B2, U+E0A0, etc.)**: never paste raw glyphs into source. The one place this still matters is the bash-3.2-compatible statusline (`share/claude-statusline/statusline.sh`) — use `printf '\xNN'` byte sequences. Write/Edit silently strips raw codepoints, so the escape form is mandatory. (The prompt is starship now; its glyphs live in starship's own config/defaults.)
- **dot-claude vs .claude**: source of truth is `dot-claude/` in this repo. The `.claude/` directory at repo root holds machine-local overrides (gitignored) — don't confuse it with project-local Claude config.
- **Sheldon plugin order matters**: `fast-syntax-highlighting` must be last in `sheldon/plugins.toml`. It wraps every existing ZLE widget at load time, so anything that registers a widget must run before sheldon's `eval` line in `zsh/30-plugins.zsh`.
- **`dot` self-locates**: `dot` resolves `DOTFILES_DIR` from its own resolved symlink target, so the repo is relocatable. To move it: `mv` the repo, then run `DOTFILES_DIR=<new> <new>/dot sync --force` once to relink (or just re-run `bootstrap.sh`).
- **`gh` auth is keychain-backed**: the OAuth token lives in the macOS login keychain (gh secure storage); `~/.config/gh/hosts.yml` carries only non-secret host metadata. If a future `gh auth login` ever uses `--insecure-storage` it will dump the token plaintext into `hosts.yml` — don't; re-login with default (secure) storage. `gh auth status` should show `(keyring)`.
- **`dot sync --only=<tag>` requires the tag to exist**: a module's declared tag and the `--only=` value must agree, or `--only=foo` silently runs nothing.
- **Statusline is bash-3.2 compatible**: `share/claude-statusline/statusline.sh` targets macOS system bash (3.2) so it's portable as a standalone drop-in (it has its own README + curl install). The installer/prompt/hook scripts do not carry that constraint and use bash-4+ features.
