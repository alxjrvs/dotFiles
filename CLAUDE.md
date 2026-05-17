# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A dotfiles repository for macOS. All config files live here. Most are symlinked to their expected locations via `sync.sh`; a few (like `scripts/`) are read directly from `$HOME/dotFiles/` by shell scripts that hardcode that path.

## Key Commands

```bash
./sync.sh             # Full idempotent setup (Homebrew, mise, symlinks, plugins, macOS defaults)
brew bundle           # Install/update packages from Brewfile
mise install          # Install language versions from mise.toml
sheldon lock --update # Update zsh plugins
```

There are no build, test, or lint commands for this repo.

## Architecture

### Driver + module layout

`sync.sh` is a thin driver (≈120 lines) that handles arg parsing, the lock file, and `set -eo pipefail`, then sources `install/lib.sh` (shared helpers) followed by every `install/[0-9][0-9]-*.sh` module in numbered order. Each module gates itself on `$OS` and `should_run` so sourcing an inert module is a cheap no-op. To modify a single section, edit its module; to add a new section, drop a `NN-name.sh` in `install/` and pick a number that places it in the right execution order (00 brew → 90 macos).

### Symlink Model

`sync.sh` (via `install/lib.sh`) defines a `link()` function that creates idempotent symlinks with interactive conflict resolution. Source files in this repo map to their destinations:

| Source | Destination |
|--------|-------------|
| `.zshrc`, `.zprofile` | `~/` |
| `.gitconfig`, `.gitmessage`, `.editorconfig` | `~/` |
| `.ripgreprc`, `.fdignore` | `~/` |
| `bat/config` | `~/.config/bat/config` |
| `mise.toml` | `~/.config/mise/config.toml` |
| `sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `nvim/` | `~/.config/nvim` (AstroNvim v5) |
| `gh/config.yml` | `~/.config/gh/config.yml` |
| `ssh/config` | `~/.ssh/config` |
| `dot-claude/{CLAUDE.md, settings.json, hooks/, statusline-command.sh}` | `~/.claude/` (individually symlinked) |

### Read-in-place (no symlink)

Some files are consumed directly from `$HOME/dotFiles/` by scripts that hardcode that path. These must remain at that absolute location — they are not synced anywhere:

- `scripts/git-data.sh` — git state cache; sourced by `.zshrc` prompt and the Claude statusline.
- `scripts/theme.sh` — color palette sourced by `.zshrc`'s hand-rolled prompt.

### Claude Code Configuration (`dot-claude/`)

Each entry below is symlinked individually into `~/.claude/` by `sync.sh`. It contains:
- `CLAUDE.md` — user-level global instructions (identity, preferences, coding style)
- `settings.json` — permissions, hooks, environment variables
- `hooks/` — event hooks (shell formatting, lock file protection, output trimming, statusline data)
- `statusline-command.sh` — statusline renderer

## Secrets management

1Password CLI (`op`) is the source of truth. There is no `.secrets` file — it was decommissioned. Use the patterns below in priority order; drop down a tier only when the one above doesn't apply.

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
Pair with `op-run` (pattern 1) — the wrapper resolves the references just for the child process. Use for any tool whose config file holds tokens.

**3. `gh auth token` keychain fallback — GitHub specifically**
`zsh/00-exports.zsh` derives `GITHUB_PERSONAL_ACCESS_TOKEN` from `gh auth token` at shell start; the token lives in the macOS keychain (managed by `gh auth login`), never on disk. This is the right pattern for any GH-token consumer (Claude MCP, scripts, etc.) because it inherits at fork time without writing the token anywhere.

**4. `direnv` + `op read` — project-local inheritance**
For values a project's subprocesses must inherit at fork time, use a per-project `.envrc` that resolves through `op read`:
```sh
# .envrc
export STRIPE_KEY="$(op read 'op://Personal/stripe/credential')"
```
`direnv` (already hooked in `zsh/30-plugins.zsh`) resolves on `cd`. Pair with a checked-in `.envrc.template` so collaborators / future you can reproduce the env without plaintext on disk.

### Rules

- **Never commit a plaintext token** to any file. Use `op://` references or `op-run` instead.
- **Never add a token to a config file as plaintext.** If `.npmrc`-shape tools need credentials, use `op://` refs + `op-run`.
- **If you find a plaintext token anywhere**, revoke first, then migrate to `op` or a keychain CLI.
- `gitleaks` runs as a global pre-commit hook (`git-hooks/pre-commit`); known token shapes that hit a commit block it. Don't rely on this catching everything — it's a backstop, not the policy.

## Guardrails

Pause and confirm with the user before doing any of these:

- **Prompt code in `.zshrc` / `scripts/theme.sh`**: contains raw powerline glyphs (U+E0B0, U+E0B2, U+E0A0, U+276F). The Write/Edit tools strip unicode. To modify these sections, use a Python helper that writes the file byte-exact; never Edit a line containing a glyph directly.
- **Dependency lockfiles** (any file matching `*-lock*` or `*.lock*`): never edit by hand. The `lock-file-guard.sh` PreToolUse hook blocks these; do not work around it.
- **`sync.sh` symlink semantics**: the `link()` function prompts on conflict and is interactive. Do not refactor it to auto-overwrite or skip prompts.
- **Hardcoded `$HOME/dotFiles` paths**: `scripts/*.sh` assumes this absolute path. Do not refactor them to use `$PWD` or relative paths.
- **Starship references**: the user replaced Starship with a hand-rolled prompt. If you see `starship` in files, treat it as historical — do not reintroduce Starship code or dependencies.
- **gnar-term is a sideproject, not load-bearing**: `gnar-term/`, `.gnar-term/`, and the `gnar-term` section in `sync.sh` are sideproject dogfooding. The active terminal stack is Ghostty + Claude Code agent view. Do NOT pitch gnar-term as primary, recommend "use both with Ghostty," or extend the dotfiles to depend on it being installed.

## Important Gotchas

- **Unicode/Nerd Font glyphs**: The Write/Edit tools strip unicode characters. Use Python to write files containing special codepoints (e.g., powerline glyphs U+E0B0, U+E0B2, U+E0A0 in prompt code).
- **sync.sh is interactive**: The `link()` function prompts on conflicts. Don't expect unattended runs if symlink targets already exist as regular files.
- **dot-claude vs .claude**: Source of truth is `dot-claude/` in this repo. The `.claude/` directory at repo root holds machine-local overrides (e.g. `settings.local.json`) that are gitignored — don't confuse it with project-local Claude config.
- **Sheldon plugin order matters**: `zsh-syntax-highlighting` must be last in `sheldon/plugins.toml`.
- **Hardcoded `$HOME/dotFiles` path**: Scripts in `scripts/` are read via absolute path. If the repo is cloned somewhere else, those consumers break.
- **settings.json allow + excludedCommands**: When adding a new command binary to `permissions.allow`, you must also add it to `sandbox.excludedCommands` — omitting it means the sandbox blocks the command regardless of the allow rule. The reverse also applies: an `excludedCommands` entry without a matching allow rule signals intent but has no effect on prompting.
