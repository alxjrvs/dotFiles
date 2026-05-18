# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A macOS dotfiles repository owned end-to-end by [`dotctl`](dotctl/) — a single Rust binary that installs base dependencies, creates symlinks, applies macOS defaults, renders the shell prompt, drives the Claude Code statusline, and dispatches every Claude Code hook event. There is no `sync.sh`, no `install/*.sh`, and no `scripts/` directory; the previous bash-script regime was absorbed into `dotctl` over PRs #20–#24 + Phase 2–6.

Source of truth for setup behavior is `dotctl/src/sync.rs`. Source of truth for prompt/statusline rendering is `dotctl/src/prompt.rs` and `dotctl/src/statusline.rs`.

## Key Commands

```bash
dotctl sync             # Idempotent install/resync. Fast on no-op.
dotctl sync --upgrade   # Same + brew update/upgrade/cleanup.
dotctl sync --only=brew,mise   # Only the listed section tags.
dotctl update           # Bump everything (equivalent to sync --upgrade).
dotctl doctor           # Read-only health check; exits non-zero on failures.
cargo test --manifest-path=dotctl/Cargo.toml   # Run dotctl's test suite.
make lint               # shellcheck on tracked shell scripts.
make fmt                # shfmt -w on tracked shell scripts.
```

Fresh machine: `git clone … ~/dotFiles && ~/dotFiles/bootstrap.sh` (installs rustup, builds dotctl, execs `dotctl sync`).

## Architecture

### dotctl-owned model

`dotctl` is a single Rust binary at `dotctl/src/main.rs` with seven subcommands:

| Subcommand | Purpose |
|------------|---------|
| `sync` | Install/resync. Tag-gated steps (`--only=<tag,...>`). Idempotent. |
| `update` | `sync --upgrade`. |
| `doctor` | Read-only diagnostics; exits non-zero on failures. |
| `git-data` | Hot path: gathers git state, writes shell-sourceable cache. Called from prompt, statusline, and `UserPromptSubmit` hook. |
| `prompt-render` | Hot path: reads git-data cache, emits zsh PROMPT-syntax with `%{...%}` escapes. Replaces the old `scripts/theme.sh` + bash prompt. |
| `statusline` | Reads Claude Code JSON on stdin, refreshes git cache, emits 3–5 lines with progress bars. |
| `hook <event>` | Dispatches every Claude Code hook event. Event name maps 1:1 to a kebab-case match arm in `dotctl/src/hook.rs`. |

Sync steps are gated on `should_run(&[tags])` and on `Os::Darwin` / `Os::Linux`. To add a new sync section, add a `step_xxx(ctx)` function in `sync.rs`, call it from `run()`, and gate it on a tag. Mirror the bash-module shape this replaced.

### Symlink Model

`sync::link()` in `dotctl/src/sync.rs` creates idempotent symlinks. On conflict, behavior depends on `--force` (overwrite with `.bak`), `--skip`, or default (interactive prompt). Mapping:

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
| `atuin/config.toml` | `~/.config/atuin/config.toml` |
| `gh/config.yml` | `~/.config/gh/config.yml` |
| `ssh/config` | `~/.ssh/config` (mode 600) |
| `git-hooks/pre-commit` | `~/.config/git/hooks/pre-commit` (referenced by `core.hooksPath`) |
| `dot-claude/{CLAUDE.md, settings.json, agents, commands}` | `~/.claude/` (individually) |
| `dot-claude/settings.local.json` (if present) | `~/.claude/settings.local.json` |

There are no read-in-place files; everything is either symlinked or compiled into the `dotctl` binary.

### Claude Code Configuration (`dot-claude/`)

Each entry is symlinked individually into `~/.claude/` by `dotctl sync` (claude tag):

- `CLAUDE.md` — user-level global instructions (identity, preferences, coding style).
- `settings.json` — permissions, env, sandbox, enabled plugins, hook dispatch.
- `agents/` — custom subagent definitions.
- `commands/` — custom slash commands.

**Hook dispatch:** all nine Claude Code hook events route through `dotctl hook <event>`. The match arms live in `dotctl/src/hook.rs`. To add or modify a hook, edit `hook.rs` — `settings.json` should not gain new shell-command hooks.

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

## Packaging policy: Lean A (brew = casks, mise = dev CLIs)

Brewfile holds **only**: `mise` (chicken-and-egg bootstrap), casks (GUI apps, fonts), and any system library that has no mise equivalent.

`mise.toml` holds: all language toolchains AND all dev CLIs. Use the registry short-name where it resolves; fall back to `aqua:` then `github:` backends.

If you're about to add a CLI to `Brewfile`, stop — put it in `mise.toml` unless it's `mise` itself or it's a cask.

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

- **Dependency lockfiles** (any file matching `*-lock*` or `*.lock*` — except `dotctl/Cargo.lock`, which is intentionally committed for binary-crate reproducibility): never edit by hand. The `dotctl hook lock-file-guard` PreToolUse hook blocks these; do not work around it.
- **`dotctl/src/sync.rs` symlink semantics**: the `link()` function prompts on conflict (Interactive mode) unless `-f` or `-s` is passed. Do not change the default behavior to auto-overwrite.
- **`dotctl/src/hook.rs` dispatcher**: hooks run on every Claude Code action. A panic or timeout here degrades the entire interactive surface. Add tests for any new event handler before wiring it into `settings.json`.
- **Hot-path subcommands** (`git-data`, `prompt-render`, `statusline`): these run on every prompt/refresh. Don't add subprocess spawns, network calls, or unbounded loops. Read the cache, render, exit.
- **Starship references**: the user replaced Starship with the `dotctl prompt-render` Rust binary. If you see `starship` anywhere, treat it as historical — do not reintroduce.
- **AstroNvim / nvim references**: the user replaced AstroNvim viewer-mode with helix. There is no `nvim/` directory; do not propose re-adding one.

## Important Gotchas

- **Powerline glyphs (U+E0B0, U+E0B2, U+E0A0, U+276F)**: never paste raw glyphs into source. All glyph references in this repo use escape syntax — `\u{e0b0}` in Rust (`dotctl/src/prompt.rs`), `$'❯'` in zsh (`zsh/50-prompt.zsh`). Write/Edit silently strips raw codepoints, so the escape form is mandatory.
- **dot-claude vs .claude**: source of truth is `dot-claude/` in this repo. The `.claude/` directory at repo root holds machine-local overrides (e.g. `settings.local.json`, local hookify rules) that are gitignored — don't confuse it with project-local Claude config.
- **Sheldon plugin order matters**: `fast-syntax-highlighting` must be last in `sheldon/plugins.toml`. It wraps every existing ZLE widget at load time, so anything that registers a widget (e.g. `add-zle-hook-widget`) must run before sheldon's `eval` line in `zsh/30-plugins.zsh`.
- **dotctl self-replaces during sync**: `step_dotctl` runs `cargo install --force` on the binary that's currently executing. The OS preserves the in-memory mapping of the running process; the on-disk `dotctl` is the *new* version after this step. Anything you spawn after that point gets the new code.
- **settings.json allow + excludedCommands**: when adding a new command binary to `permissions.allow`, you must also add it to `sandbox.excludedCommands` — omitting it means the sandbox blocks the command regardless of the allow rule. The reverse also applies: an `excludedCommands` entry without a matching allow rule signals intent but has no effect on prompting.
- **`dotctl sync --only=<tag>` requires the tag to exist**: the tag list in `Cli` doc (`main.rs`) and the `should_run(&[...])` calls in `sync.rs` must agree. If they drift, `--only=foo` silently runs nothing instead of erroring.
