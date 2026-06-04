# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A macOS dotfiles repository owned end-to-end by **self-contained shell scripts** fronted by a thin [`dot`](dot) dispatcher — they install base dependencies, create symlinks, apply macOS defaults, render the shell prompt, drive the Claude Code statusline, and dispatch every Claude Code hook event. No Rust, no compiled binary: just `bash`, `git`, and `jq`.

There is no `dotctl/` crate anymore — it was replaced by these shell scripts (this branch/PR). Each subsystem lives in its own topic folder and every script is **self-contained**: the small helpers it needs (logging, os/host detection, symlink `link()`, jq getters, the git-cache path hash, color/gradient math) are inlined at the top of the script rather than sourced from a shared library. Duplication across scripts is intentional — it keeps each folder isolated and individually shareable.

Source of truth for setup behavior is `sync` + `install/*.sh`. Source of truth for prompt rendering is `prompt/git-data` + `prompt/prompt-render`. Source of truth for the statusline is `share/claude-statusline/statusline.sh`.

## Key Commands

```bash
dot sync                # Idempotent install/resync. Fast on no-op. Prompts to clean .bak files at the end (default yes).
dot sync --upgrade      # Same + brew update/upgrade/cleanup + mise upgrade.
dot sync --only=brew,mise   # Only the listed section tags.
dot update              # Bump everything (equivalent to sync --upgrade).
dot doctor              # Read-only health check; exits non-zero on failures.
dot prune               # Find + delete .bak files, stale worktrees, orphan workers, old cost dirs.
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
| `dot prune` | `./sync --only=prune` | `.bak` / stale-worktree / orphan-worker / old-cost cleanup (also runs standalone via `install/95-prune.sh`). |
| `dot render <tpl>` | `./render` | `op://` template resolver. |
| `dot git-data` | `prompt/git-data` | Hot path: gather git state, write shell-sourceable cache. |
| `dot prompt-render` | `prompt/prompt-render` | Hot path: read git-data cache, emit zsh PROMPT syntax. |
| `dot statusline` | `share/claude-statusline/statusline.sh` | Read Claude Code JSON on stdin, emit 3–6 lines with progress bars. |
| `dot subagent-statusline` | `share/claude-statusline/subagent-statusline.sh` | Subagent task statusline. |
| `dot hook <event>` | `hooks/<event>` | Dispatch a Claude Code hook event (event name maps 1:1 to a script in `hooks/`). |

`DOTFILES_DIR` resolution lives only in `dot`: `$DOTFILES_DIR` env → directory of `dot`'s resolved symlink target → legacy `~/dotFiles`; first candidate that is a directory containing a `Brewfile` wins. Every other script is a plain script you can run directly (`./prompt/git-data`) for development.

### sync / install modules

`sync` sources `install/NN-*.sh` modules in numeric order; each declares its tags and a `run` function, gated by a tag filter (`--only=<tags>`) and an OS guard. Modules: `00-brew 10-linux 20-sheldon 30-mise 40-symlinks 50-ghostty 60-claude 70-gh 80-git-maint 85-lefthook 90-macos 95-prune`. To add a sync section, add an `install/NN-name.sh` module, give it a tag, and `sync` will pick it up. macOS defaults data + `audit` live in `90-macos.sh`.

### Symlink Model

`link()` (inlined in `sync` and `install/40-symlinks.sh`) creates idempotent symlinks. On conflict, behavior depends on `$LINK_MODE`: `overwrite` (move existing to `.bak`, then link, set via `-f`), `skip` (`-s`), or default `interactive` (prompt). Mapping:

| Source | Destination |
|--------|-------------|
| `.zshrc`, `.zprofile`, `.zshenv`, `.hushlogin` | `~/` |
| `.gitconfig`, `.gitmessage`, `.gitignore`, `.editorconfig` | `~/` |
| `.ripgreprc`, `.fdignore` | `~/` |
| `zsh/[0-9]*.zsh` | `~/.config/zsh/` (sourced in numeric order by thin `.zshrc`) |
| `bat/config` | `~/.config/bat/config` |
| `mise.toml` | `~/.config/mise/config.toml` |
| `sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `lazygit/config.yml` | `~/.config/lazygit/config.yml` |
| `helix/languages.toml` | `~/.config/helix/languages.toml` |
| `karabiner/karabiner.json` | `~/.config/karabiner/karabiner.json` |
| `atuin/config.toml` | `~/.config/atuin/config.toml` |
| `gh/config.yml` | `~/.config/gh/config.yml` |
| `ssh/config` | `~/.ssh/config` (mode 600) |
| `git-template/hooks/pre-commit` | `~/.config/git/template/hooks/pre-commit` (referenced by `core.hooksPath`) |
| `dot` | `~/.local/bin/dot` |
| `dot-claude/{CLAUDE.md, settings.json, agents, commands}` | `~/.claude/` (individually) |
| `dot-claude/settings.local.json` (if present) | `~/.claude/settings.local.json` |

Everything is symlinked; there are no read-in-place or compiled-in files.

### Claude Code Configuration (`dot-claude/`)

Each entry is symlinked individually into `~/.claude/` by `dot sync` (claude tag):

- `CLAUDE.md` — user-level global instructions (identity, preferences, coding style).
- `settings.json` — permissions, env, sandbox, enabled plugins, hook dispatch, `statusLine` (→ `dot statusline`), `subagentStatusLine` (→ `dot subagent-statusline`).
- `agents/` — custom subagent definitions.
- `commands/` — custom slash commands.

**Hook dispatch:** Claude Code hook events route through `dot hook <event>`, which execs `hooks/<event>`. To add or modify a hook, add/edit the script in `hooks/` and wire it in `settings.json`. The wired set is intentionally minimal:

| Event | Script | Role |
|-------|--------|------|
| PreToolUse (Edit\|Write) | `hooks/lock-file-guard` | defender |
| PreToolUse (Bash) | `hooks/policy-guard` | defender |
| PostToolUse (Edit\|Write) | `hooks/format-on-save` | formatter |
| PostToolUse (Bash) | `hooks/trim-bash-output` | output spill |
| UserPromptSubmit | `hooks/user-prompt-submit` | git cache pre-warm |
| SessionStart | `hooks/session-start` | session banner title (`<repo>:<branch>`) |
| Stop | `hooks/stop` | session JSONL journal |

### Tests

Shell unit tests run under `bats` (a managed mise tool) in `tests/bats/`. `tests/golden/` holds byte-exact reference fixtures (captured from the prior Rust implementation) for `prompt/prompt-render`, the statusline, and the subagent statusline — `tests/verify-golden.sh` / `tests/verify-statusline.sh` diff the current scripts against them. `lefthook.yml` runs `shellcheck` + `shfmt -i 2 -ci -sr` pre-commit and `bats` + `dot doctor` pre-push.

## Packaging policy: Lean A (brew = casks, mise = dev CLIs)

Brewfile holds **only**: `mise` (chicken-and-egg bootstrap), casks (GUI apps, fonts), and any system library that has no mise equivalent.

`mise.toml` holds: all language toolchains AND all dev CLIs (including `jq`, `bats`, `shellcheck`, `shfmt`). Use the registry short-name where it resolves; fall back to `aqua:` then `github:` backends.

If you're about to add a CLI to `Brewfile`, stop — put it in `mise.toml` unless it's `mise` itself or it's a cask.

## Terminal: Ghostty

Ghostty is the chosen terminal emulator. The cask installs the .app;
`install/50-ghostty.sh` lays down a `~/.local/bin/ghostty` shim
pointing at `/Applications/Ghostty.app/Contents/MacOS/ghostty` so the
CLI is uniform with every other managed tool. `dot doctor` runs
`ghostty --version` like git/mise/lefthook, and validates
`ghostty/config` indirectly via the symlink integrity check.

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
op-run npm publish               # = op run --no-masking -- npm publish
```
For any CLI invocation that reads a token from env. Nothing is exported to the shell session; `op` resolves `op://` references at exec time only.

**2. `op://` references in config files**
```ini
# .npmrc
//registry.npmjs.org/:_authToken=op://Personal/npm/credential
```
Pair with `op-run` (pattern 1) — the wrapper resolves the references just for the child process.

**3. `gh auth token` keychain fallback — GitHub specifically**
`zsh/00-exports.zsh` derives `GITHUB_PERSONAL_ACCESS_TOKEN` from `gh auth token` at shell start; the token lives in the macOS keychain (managed by `gh auth login`), never on disk. The right pattern for any GH-token consumer because it inherits at fork time without writing the token anywhere.

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

- **Dependency lockfiles** (any file matching `*-lock*` or `*.lock*`): never edit by hand. The `hooks/lock-file-guard` PreToolUse hook blocks these; do not work around it.
- **`link()` symlink semantics**: the `link()` function prompts on conflict (interactive `$LINK_MODE`) unless `-f` or `-s` is passed. Do not change the default behavior to auto-overwrite.
- **`hooks/` dispatcher**: hooks run on every Claude Code action. A crash or hang here degrades the entire interactive surface. Add a bats test for any new hook before wiring it into `settings.json`.
- **Hot-path scripts** (`prompt/git-data`, `prompt/prompt-render`): these run on every prompt/refresh. Don't add subprocess spawns, network calls, or unbounded loops. `prompt-render` must stay fork-free — read the cache, render, exit.
- **Self-contained rule**: scripts inline their own helpers; there is no `shared/` library layer. Don't introduce one — keep each topic folder independently runnable and shareable.
- **Starship references**: replaced by `prompt/prompt-render`. If you see `starship` anywhere, treat it as historical — do not reintroduce.
- **AstroNvim / nvim references**: replaced by helix. There is no `nvim/` directory; do not propose re-adding one.

## Important Gotchas

- **Powerline glyphs (U+E0B0, U+E0B2, U+E0A0, U+276F, etc.)**: never paste raw glyphs into source. Use escape syntax — `$'\u{e0b0}'`/`$'❯'` in zsh, `printf '\xNN'` byte sequences in the bash-3.2-compatible statusline (`share/claude-statusline/statusline.sh`). Write/Edit silently strips raw codepoints, so the escape form is mandatory.
- **dot-claude vs .claude**: source of truth is `dot-claude/` in this repo. The `.claude/` directory at repo root holds machine-local overrides (gitignored) — don't confuse it with project-local Claude config.
- **Sheldon plugin order matters**: `fast-syntax-highlighting` must be last in `sheldon/plugins.toml`. It wraps every existing ZLE widget at load time, so anything that registers a widget must run before sheldon's `eval` line in `zsh/30-plugins.zsh`.
- **`dot` self-locates**: `dot` resolves `DOTFILES_DIR` from its own resolved symlink target, so the repo is relocatable. To move it: `mv` the repo, then run `DOTFILES_DIR=<new> <new>/dot sync --force` once to relink (or just re-run `bootstrap.sh`).
- **settings.json allow + excludedCommands**: when adding a new command to `permissions.allow`, also add it to `sandbox.excludedCommands` — omitting it means the sandbox blocks the command regardless of the allow rule.
- **`dot sync --only=<tag>` requires the tag to exist**: a module's declared tag and the `--only=` value must agree, or `--only=foo` silently runs nothing.
- **Statusline is bash-3.2 compatible**: `share/claude-statusline/statusline.sh` targets macOS system bash (3.2) so it's portable as a standalone drop-in (it has its own README + curl install). The installer/prompt/hook scripts do not carry that constraint and use bash-4+ features.
