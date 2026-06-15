# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A macOS dotfiles repository owned end-to-end by a handful of **shell scripts** fronted by a thin [`dot`](dot) dispatcher — they install base dependencies, create symlinks, and apply macOS defaults. The shell prompt is [starship](https://starship.rs) (config in `starship.toml`). The Claude Code statusline lives in its own repo (`github.com/alxjrvs/claude-statusline`). Just `bash`, `git`, and `jq`.

Each subsystem lives in its own topic folder. The helpers shared by the standalone scripts (`os_kind`, `resolve_dotfiles_dir`, and the `link()` symlinker) live in one small **`lib/common.sh`**, sourced by `sync` and `doctor`.

Source of truth for setup behavior is `sync` + `install/*.sh`. The shell prompt is starship (`starship.toml`, symlinked to `~/.config/starship.toml`). The Claude Code statusline is a separate project (`github.com/alxjrvs/claude-statusline`). `install/60-claude.sh` (claude tag) clones it to `~/Code/claude-statusline` and runs its `install.sh`, which symlinks `claude-statusline` + `claude-subagent-statusline` into `~/.local/bin`; `dot-claude/settings.json` references those paths.

## Northern Principles

One North Star: **small, exemplary, easily shareable — a senior engineer's showpiece, not an over-engineered personal artifact.** The principles below are the compass headings that point there; every concrete rule, policy, and guardrail in this file is downstream of one of them. They are the *why* behind the *what* — when you face a decision no rule covers, derive the answer from these. When a specific rule and a principle appear to collide, **surface the tradeoff to the owner rather than silently keeping the bespoke thing.**

1. **Native over special.** Prefer a tool's stock behavior to bespoke machinery wrapped around it; deleting custom code in favor of a built-in is the highest-value change you can make here. Configs carry only *intentional divergences* from defaults, in the idiomatic form — never a line that merely restates a default. (This is why the prompt is stock starship, the editor is a single plugin-free `init.lua`, and `settings.json` is deliberately minimal.)

2. **Guilty until proven load-bearing.** Every dependency, wrapper, convention, and line of config must earn its weight on a *personal* repo. Nothing stays because it's "best practice" — ceremony justifies itself by what it prevents, or it goes. When in doubt, cut and see what breaks. Protected, never cut without asking: `brew`, `neovim`, `ghostty`.

3. **No gratuitous wrappers.** Don't wrap a command just to re-expose it — call tools natively (`op run --`, `eval "$(starship init zsh)"`). Keep *only* the shims an external program execs by path with no native alternative: `git-ssh-sign` (1Password commit signing) and `gh-mcp-auth-header` (GitHub MCP `headersHelper`). A shim that merely forwards is a smell.

4. **One config, every machine.** No host detection, no per-host overlay. If a genuine per-machine divergence appears, add the *smallest possible guard at that point* — never a host-overlay system built preemptively. (Machine-local escape hatches that already exist: `~/.gitconfig.local` for signing, `DOTFILES_DIR` for relocation.)

5. **Standard, and agentic-enabled.** 1Password, Git, SSH, `gh`, and the MCP wiring stay stock installs — but wired for agents end-to-end (op MCP, op SSH agent, GitHub MCP, the on-demand auth shims). Secrets resolve through `op` on demand, never plaintext, never exported to env or written to disk.

6. **Keep it legible.** Plain integer ops over clever math; if the math turns obscure, drop the feature instead. One small shared `lib/common.sh` over duplicated inline helpers. Docs explain the *decision and the gotcha* — the *what* is already in the code, so don't restate it.

The sections that follow (Packaging policy, Terminal stack, One config, Secrets, Guardrails) are this repo's de-facto ADRs — each is a principle made concrete. There are no separate ADR files by design: the decision lives next to the thing it governs.

## Key Commands

```bash
dot sync                # Idempotent install/resync. Fast on no-op.
dot sync --upgrade      # Same + brew update/upgrade/cleanup + mise upgrade.
dot sync --only=brew,mise   # Only the listed section tags.
dot update              # Bump everything (equivalent to sync --upgrade).
dot sync --dry-run      # Mutate nothing; print what each module WOULD do.
dot doctor              # Read-only health check. Exit: 0 clean, 1 failures, 2 warnings only.
dot doctor --fix        # Same + repair symlinks: reap orphans, relink missing/incorrect.
dot doctor --full       # Same + a full-history gitleaks scan (slow, on-demand).
dot watchtower          # Local 1Password security audit via the op CLI (foreground only).
lefthook run pre-commit # shellcheck + shfmt -i 2 -ci -sr over staged shell files.
mise x -- bats test/    # Run the lib/common.sh unit tests.
```

Fresh machine: `git clone … ~/dotFiles && ~/dotFiles/bootstrap.sh` (execs `dot sync`).

## Architecture

### The `dot` dispatcher + topic folders

`dot` (repo root) is a short bash script — the single command symlinked onto `PATH` at `~/.local/bin/dot`. It resolves `DOTFILES_DIR` once, then execs the matching topic script, passing args through:

| Subcommand | Execs | Purpose |
|------------|-------|---------|
| `dot sync` | `./sync` | Install/resync. Tag-gated steps (`--only=<tag,...>`). Idempotent. |
| `dot update` | `./sync --upgrade` | Bump everything. |
| `dot doctor` | `./doctor` | Read-only diagnostics; exits non-zero on failures. `--fix` repairs the symlink contract (reap orphans + relink missing/incorrect) — doctor's only mutation. |
| `dot watchtower` | `./watchtower` | Local "Watchtower"-style 1Password audit (breached/reused/weak/unsecured) built on the `op` CLI. Reads passwords locally, emits only hashes/metadata. Dev creds (localhost/`.local`/LAN URL, or the `watchtower-ignore` tag) are listed separately, never flagged. Foreground only (op desktop-auth needs the calling session); `--vault=NAME`, `--no-breach`. |

`DOTFILES_DIR` resolution lives only in `dot`: `$DOTFILES_DIR` env → directory of `dot`'s resolved symlink target → fallback `~/dotFiles`; first candidate that is a directory containing a `Brewfile` wins. The top-level scripts (`sync`, `doctor`) are standalone — run them directly for development. The `install/NN-*.sh` modules are **sync-sourced, not standalone**: `sync` sources `lib/common.sh` (which defines `link()` alongside the other shared helpers), then exports those helpers (`os_kind`, `resolve_dotfiles_dir`, `link`) before sourcing each module, so the modules carry no helpers of their own.

### sync / install modules

`sync` sources `install/NN-*.sh` modules in numeric order; each declares its tags and a `run` function, gated by a tag filter (`--only=<tags>`). Modules: `00-brew 30-mise 40-symlinks 45-ssh 60-claude 85-lefthook 90-macos`. To add a sync section, add an `install/NN-name.sh` module, give it a tag, and `sync` will pick it up. macOS defaults data + `audit` live in `90-macos.sh`. (`30-mise` also locks sheldon plugins — sheldon is a mise tool, so its binary only exists after `mise install`.)

### Symlink Model

`link()` (defined in `lib/common.sh`, exported by `sync` to the install modules, and reused by `dot doctor --fix`) creates idempotent symlinks. On conflict, behavior depends on `$LINK_MODE`: `overwrite` (replace, set via `-f`), `skip` (`-s`), or default `interactive` (prompt). Overwrite does not back up the displaced file — the canonical content is in this git repo. Mapping:

| Source | Destination |
|--------|-------------|
| `.zshrc`, `.zprofile`, `.zshenv`, `.hushlogin` | `~/` |
| `.gitconfig`, `.gitmessage`, `.gitignore`, `.editorconfig` | `~/` |
| `.ripgreprc`, `.fdignore` | `~/` |
| `zsh/[0-9]*.zsh` | `~/.config/zsh/` (sourced in numeric order by thin `.zshrc`) |
| `bat/config` | `~/.config/bat/config` |
| `mise.toml` | `~/.config/mise/config.toml` (tools only) |
| `mise-settings.toml` | `~/.config/mise/conf.d/settings.toml` (global-only `[settings]`; mise loads `conf.d/*` only as global, so `trusted_config_paths` isn't ignored+warned the way it is when `mise.toml` is read as this repo's project-local config) |
| `sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `starship.toml` | `~/.config/starship.toml` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `nvim/init.lua` | `~/.config/nvim/init.lua` |
| `karabiner/karabiner.json` | `~/.config/karabiner/karabiner.json` |
| `atuin/config.toml` | `~/.config/atuin/config.toml` |
| `gh/config.yml` | `~/.config/gh/config.yml` |
| `ssh/config` | `~/.ssh/config` (mode 600) |
| `ssh/1password-agent.toml` | `~/.config/1Password/ssh/agent.toml` |
| `gh/gh-mcp-auth-header` | `~/.local/bin/gh-mcp-auth-header` (github MCP headersHelper → `op read`) |
| `render/render-mcp-auth-header` | `~/.local/bin/render-mcp-auth-header` (Render MCP headersHelper → `op read`) |
| `git-template/hooks/pre-commit` | `~/.config/git/template/hooks/pre-commit` (copied into new repos via `init.templateDir`) |
| `dot` | `~/.local/bin/dot` |
| `dot-claude/{CLAUDE.md, settings.json}` | `~/.claude/` (individually) |

Everything is symlinked — every destination traces back to a file in this repo.

### Claude Code Configuration (`dot-claude/`)

Each entry is symlinked individually into `~/.claude/` by `dot sync` (claude tag):

- `CLAUDE.md` — user-level global instructions (identity, preferences).
- `settings.json` — **deliberately minimal**; it carries only deliberate divergences from Claude Code defaults, enumerated in `dot-claude/CLAUDE.md` (the canonical list — don't restate it here). Don't add settings without asking.

Don't add `agents/`, `commands/`, or `hooks/` directories without asking — `dot-claude/` stays at these two symlinked files plus `REFERENCE.md`.

### Linting & tests

Three lightweight automation layers:

- **pre-commit** (`lefthook.yml`, installed by `dot sync` lefthook tag): `shellcheck` + `shfmt -i 2 -ci -sr` + `gitleaks protect` + a `settings.json` validity check over staged shell files.
- **commit-msg** (`lefthook.yml`): rejects throwaway subjects (bare `WIP`/`wip` or a single character) so they don't enter permanent history. Commit convention is `scope: summary` or `type(scope): summary` (e.g. `feat(mcp): …`, `docs+chore: …`). Bypass once with `git commit --no-verify`.
- **CI** (`.github/workflows/lint.yml`): mirrors the pre-commit gate (shellcheck/shfmt/gitleaks/settings) and runs the `bats` unit tests on push to `main` and on PRs. Lint only — never runs `dot sync` or mutates anything.

Tests live in `test/` (`bats`): `test/common.bats` covers the `lib/common.sh` helpers (`link`, `os_kind`, `resolve_dotfiles_dir`). Run locally with `mise x -- bats test/`. The surface is deliberately small — `lib/common.sh` has the highest fan-in (sourced by `sync`, `doctor`, `watchtower`), so that's where a unit test earns its weight; the installer modules stay verified by `dot sync --dry-run` rather than a heavier harness.

## Packaging policy: Lean A (brew = casks, mise = dev CLIs)

Brewfile holds **only**: `mise` (chicken-and-egg bootstrap), casks (GUI apps, fonts), and any system library that has no mise equivalent.

`mise.toml` holds: all language toolchains AND all dev CLIs (including `jq`, `shellcheck`, `shfmt`). Use the registry short-name where it resolves; fall back to `aqua:` then `github:` backends.

If you're about to add a CLI to `Brewfile`, stop — put it in `mise.toml` unless it's `mise` itself or it's a cask.

## Terminal: cmux (built on Ghostty)

`cmux` is the default terminal — set via `TERMINAL=cmux` in
`zsh/00-exports.zsh`. It's a libghostty-based agent multiplexer for
running parallel Claude Code sessions with vertical tabs and git-worktree
isolation. macOS has no system "default terminal" role, so the env var is
a declaration of intent (the XDG convention), not a hard switch; launch
cmux directly (Dock/Raycast).

Ghostty stays installed as the **engine + config source**, not a separate
daily driver: cmux renders with libghostty and reads
`~/.config/ghostty/config`, so it inherits the Ghostty theme/font/colors.
`dot sync` symlinks `ghostty/config` to `~/.config/ghostty/config` (the
cask installs Ghostty.app; `dot doctor` validates the symlink). Both casks
live in the Terminal section of the Brewfile.

No other terminal emulators (iTerm2, WezTerm, Kitty, Alacritty, Warp) are
managed by this repo. The stack is exactly two and they are one unit —
Ghostty (engine + config) and cmux (the default terminal on top of it).
If you find yourself adding a third, stop; revisit only if Mitchell
Hashimoto abandons Ghostty.

## One config, every machine

This repo runs on more than one Mac but is deliberately **single-config**:
there is no host detection and no per-host overlay. `Brewfile`,
`mise.toml`, the macOS defaults in `install/90-macos.sh`, symlinks, and zsh
fragments are identical everywhere. If a genuine per-machine divergence
ever appears, add the smallest possible guard at that point — don't
add a host-overlay system preemptively.

## Secrets management

1Password CLI (`op`) is the source of truth for secrets. Use the patterns below in priority order; drop down a tier only when the one above doesn't apply.

### Patterns

**1. `op run -- <cmd>` — one-shot CLI injection**
```sh
op run -- npm publish            # resolves op:// refs at exec time; masking ON
```
For any CLI invocation that reads a token from env. Nothing is exported to the shell session; `op` resolves `op://` references at exec time only. Masking is on by default (no `--no-masking`): the child gets the real resolved value but 1Password redacts it from the child's stdout/stderr, so secrets don't leak into output an agent/transcript could capture. If a tool genuinely breaks under masked output, pass `--no-masking` for that one call and note why rather than making it the default.

**2. `op://` references in config files**
```ini
# .npmrc
//registry.npmjs.org/:_authToken=op://Personal/npm/credential
```
Pair with `op run --` (pattern 1) — it resolves the references just for the child process.

**3. `gh auth token` keychain resolution — GitHub specifically**
The token lives in the macOS keychain (managed by `gh auth login`, secure storage), never on disk, and is NOT exported to the environment (a standing export would leak it into every subprocess). Resolve it on demand — `GITHUB_TOKEN="$(gh auth token)" some-tool` — only when a tool actually needs it.

**4. `mise` `[env]` — project-local inheritance**
For values a project's subprocesses must inherit at fork time, put them in the project's `mise.toml` `[env]`, resolving secrets through `op` at activation:
```toml
# mise.toml
[env]
STRIPE_KEY = "{{ exec(command='op read op://Personal/stripe/credential') }}"
```
mise activates on `cd` (its shims are already on PATH via `.zshenv`). For one-off commands, `op run -- <cmd>` (pattern 1) is simpler.

### Rules

- **Never commit a plaintext token** to any file. Use `op://` references or `op run --` instead.
- **Never add a token to a config file as plaintext.** If `.npmrc`-shape tools need credentials, use `op://` refs + `op run --`.
- **If you find a plaintext token anywhere**, revoke first, then migrate to `op` or a keychain CLI.
- `gitleaks` runs from the pre-commit hook template (`git-template/hooks/pre-commit`, copied into new repos via `init.templateDir`); it's a backstop, not the policy.

## Guardrails

Pause and confirm with the user before doing any of these:

- **Dependency lockfiles** (any file matching `*-lock*` or `*.lock*`): never edit by hand.
- **`link()` symlink semantics**: the `link()` function prompts on conflict (interactive `$LINK_MODE`) unless `-f` or `-s` is passed. Do not change the default behavior to auto-overwrite. (`dot doctor --fix` deliberately invokes it with `LINK_MODE=overwrite` for its opt-in repair path — that's explicit, not the default.)
- **The prompt is starship**: configured by `starship.toml` (symlinked to `~/.config/starship.toml`), initialized via `eval "$(starship init zsh)"` in `zsh/50-prompt.zsh`. Keep the config minimal.
- **Shared helpers live in `lib/common.sh`**: `os_kind`, `resolve_dotfiles_dir`, and `link()`, sourced by `sync` and `doctor` (callers set `_DOTFILES_SELF_DIR` first). Don't re-inline them.
- **Neovim is plugin-free**: the editor is configured by a single `nvim/init.lua` (sensible defaults + native LSP via `vim.lsp.config`/`vim.lsp.enable`, requires Neovim 0.11+). There is no plugin manager (lazy.nvim, packer) and no AstroNvim/LazyVim distro — don't propose adding one; keep the config to a single self-contained `init.lua`.

## Important Gotchas

- **dot-claude vs .claude**: `dot-claude/` is the source of truth for **user/global** Claude config (symlinked into `~/.claude/`). The repo-root `.claude/` is this repo's **project-scoped** config and follows the native Claude Code convention — `.claude/settings.json` is **committed** (currently the `sandbox.enabled:false` relief-valve, since this installer repo can't run under the strict global sandbox) and only `.claude/settings.local.json` is gitignored machine-local. Don't conflate the two: `dot-claude/` is global, `.claude/` is this-repo-only.
- **Sheldon plugin order matters**: `fast-syntax-highlighting` must be last in `sheldon/plugins.toml`. It wraps every existing ZLE widget at load time, so anything that registers a widget must run before sheldon's `eval` line in `zsh/30-plugins.zsh`.
- **`dot` self-locates**: `dot` resolves `DOTFILES_DIR` from its own resolved symlink target, so the repo is relocatable. To move it: `mv` the repo, then run `DOTFILES_DIR=<new> <new>/dot sync --force` once to relink (or just re-run `bootstrap.sh`).
- **`gh` auth is keychain-backed**: the OAuth token lives in the macOS login keychain (gh secure storage); `~/.config/gh/hosts.yml` carries only non-secret host metadata. If a future `gh auth login` ever uses `--insecure-storage` it will dump the token plaintext into `hosts.yml` — don't; re-login with default (secure) storage. `gh auth status` should show `(keyring)`.
- **`dot sync --only=<tag>` requires the tag to exist**: a module's declared tag and the `--only=` value must agree. A tag no module declares fails loudly (`==> ✗ --only=foo matched no module`, exit 1) — it does not silently run nothing.
