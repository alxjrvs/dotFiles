# CLAUDE.md

This file guides Claude Code (claude.ai/code) when working in this repository.

## What This Is

A macOS **dotfiles repo** that is now pure **config for [`botu`](https://github.com/alxjrvs/botu)** — the small bash dotfiles+workspace engine extracted from this repo. botu lives on `PATH`; this repo is its *first consumer*. There is no engine code here anymore: the whole repo is a `botufile` (the config), a handful of `hooks/`, and the payload (`.zshrc`, `zsh/`, `nvim/`, `dot-claude/`, `Brewfile`, `mise.toml`, …) that botu symlinks into place.

```
botu init ~/Code/DevEnv/dotFiles   # record this repo (writes botuinit.sh)
botu apply        # symlink/copy/install/run from the botufile
botu verify       # check drift (exit 0 ok / 2 warn / 1 fail)
botu fix          # repair drift (incl. reaping orphaned links)
botu uninstall    # remove every managed link
```

Fresh machine: `git clone … && ./dotFiles/botuinit.sh` (installs botu, points it here, applies).

## The `botufile`

The config is a short bash program of verb-aware declarations; `botu apply|verify|fix` source it once under the matching verb. No JSON, no templating — the config *is* the program. Vocabulary:

- `section "Name"` — group + tag (for `--only=Name`).
- `link [--mode M] SRC DST` / `copy [--mode M] SRC DST` / `glob PAT DSTDIR` — the symlink/copy contract (DST may use `~`).
- `brewfile FILE` / `mise_install` — packages via the stock tools (the `Brewfile` / `mise.toml` are the data).
- `osx_default DOMAIN KEY TYPE VALUE` — a macOS default (the engine restarts the UI automatically when any changed).
- `on apply|verify CMD…` — a small inline imperative step (no file needed; the botufile is bash).
- `hook NAME [k=v…]` — sources `hooks/NAME.sh`, calls `_NAME_<verb>`, passes data as `$BOTU_k`. For substantial imperative logic only.

## Northern Principles

One North Star: **small, exemplary, easily shareable — a senior engineer's showpiece, not an over-engineered personal artifact.** When a rule and a principle collide, surface the tradeoff to the owner.

1. **Native over special.** Prefer stock behavior to bespoke machinery; deleting custom code for a built-in is the highest-value change. (Extracting the engine into `botu` was the largest application of this.)
2. **Guilty until proven load-bearing.** Every dependency, wrapper, and line earns its weight on a *personal* repo, or it goes.
3. **No gratuitous wrappers.** Call tools natively. The lone shims that survive are ones an external program execs by path: `git-ssh-sign` (1Password commit signing) and `op-agent` (the MCP `headersHelper`, see Secrets).
4. **One config, every machine.** No host detection. Add the smallest possible guard at the point a genuine per-machine divergence appears.
5. **Standard, and agentic-enabled.** 1Password, Git, SSH, `gh`, MCP stay stock — but wired for agents. Secrets resolve through `op` on demand, never plaintext in git, never exported to the session env.
6. **Keep it legible.** Plain ops over clever math; docs explain the *decision and the gotcha*, not the *what*.

## hooks/

The imperative residue the DSL can't express. A hook becomes a file only for (a) substantial multi-step logic, or (b) a script an external program execs by path.

- **`op-agent.sh`** — one verb-dispatched CLI for all 1Password-agent machinery (see Secrets). Replaces the old `install/47-op-agent.sh` and the two per-service `*-mcp-auth-header` shims. Linked onto `PATH` as `op-agent`; driven by `on apply op-agent provision` / `on verify op-agent status`.
- **`claude_statusline.sh`** — clones the `claude-statusline` repo beside this one and runs its installer.

Small steps (`chmod 700 ~/.ssh`, `lefthook install`) are inline `on apply` lines, not files.

## Packaging policy: Lean A (brew = casks, mise = dev CLIs)

`Brewfile` holds **only** `mise` (bootstrap), casks (GUI apps, fonts), and system libs with no mise equivalent. `mise.toml` holds all language toolchains AND dev CLIs (`jq`, `shellcheck`, `shfmt`). If you're about to add a CLI to `Brewfile`, stop — it goes in `mise.toml` unless it's `mise` itself or a cask.

## Terminal: Ghostty (canonical), cmux (parallel agent sessions)

Ghostty is the daily driver (`TERMINAL=ghostty`, `ghostty/config`). cmux stays for **parallel Claude Code sessions** via `botu code cmux` (the workspace mirror, formerly `dot ws`). Two symlinked files: `ghostty/config` (rendering + Ghostty keybinds/visor; cmux also reads it for the visual subset) and `cmux/cmux.json` (cmux's app config — intentional divergences only). `botu code` mirrors `~/Code` into workspaces: `botu code init [DIR]` records the dir, `botu code claude` (idle `claude --bg` per repo) / `botu code cmux` (one workspace per repo).

## Secrets management

1Password (`op`) is the source of truth, following 1Password's two-tier model:

- **Interactive dev (you)** — desktop app + biometric; resolve via `op run` / `op://` refs / Environments.
- **Hands-off agent (Claude, MCP, cron)** — a **service account** scoped to the `claude-agent` vault; no biometric, no desktop dependency.

### Agent secrets — the `op-agent` CLI

`hooks/op-agent.sh` is the single script for all agent-1Password machinery, dispatched by verb:

- `op-agent provision` — idempotently ensures the `claude-agent` vault, a per-host service account with `read_items` on only that vault, its token in the macOS login keychain (`op-claude-agent`), and caches the fine-grained git PAT into the keychain for `osxkeychain` git auth. Run via `on apply op-agent provision`. Foreground-only first run (minting authorizes through the desktop app).
- `op-agent status` — reports keychain token presence (`on verify`).
- `op-agent header op://ref` — emits `{"Authorization":"Bearer …"}` for an HTTP MCP server's `headersHelper`. **The ref is an argument, not a per-service file** — this one verb replaced the two identical-but-for-`OP_REF` shims. It sources the SA token from the keychain inline (no biometric, headless-safe), confined to one short-lived process so neither the token nor the secret reaches a Bash subprocess, the transcript, or OTEL. `{}` on any failure (clean connection failure, no malformed Bearer).

`headersHelper` runs its value as a shell command, so `op-agent header op://claude-agent/…` works directly. Wire each HTTP MCP server's `headersHelper` to `op-agent header <its op:// ref>`.

### MCP secrets — one canonical pattern

Servers we control launch via 1Password's `op run --env-file=.env -- <server>` with `op://` references in a committable `.env` (`botu mcp add`). HTTP servers use the `op-agent header` hook above. Plugin-bundled stdio servers use their own `*_COMMAND` resolver (e.g. spacebase's `SPACEBASE_API_KEY_COMMAND`). **Never write a `${VAR}` placeholder into a git-tracked `.mcp.json`/`.env`** (a later `claude mcp add` can expand it). `botu verify` and the `git-template` pre-commit both fail on a `${VAR}` in a tracked `.mcp.json` and on a resolved-token literal in any tracked `.mcp.json`/`.env`.

### Agent git auth

Uses the stock `osxkeychain` helper (not `op`), so the agent pushes with a least-privilege fine-grained PAT (cached by `op-agent provision`), headlessly, no biometric. Wired agent-only via `dot-claude/settings.json` `GIT_CONFIG_*`. Your own terminal git keeps its `gh` helper + 1Password signing.

### Rules

- Never commit a plaintext token. Use `op://` references or `op run --`.
- HTTP MCP → `op-agent header`; controlled servers → `op run --env-file`; plugin servers → their `*_COMMAND`.
- If you find a plaintext token anywhere, revoke first, then migrate.

## Claude Code Configuration (`dot-claude/`)

Symlinked individually into `~/.claude/` (the `Claude` section of the botufile):

- `CLAUDE.md` — user-level global instructions (identity, preferences).
- `settings.json` — **deliberately minimal**; only divergences from defaults (enumerated in `dot-claude/CLAUDE.md`). Don't add settings without asking.

## Guardrails

- **Dependency lockfiles** (`*-lock*`, `*.lock*`): never edit by hand.
- **The prompt is starship** (`starship.toml`); keep it minimal.
- **Neovim is plugin-free** (single `nvim/init.lua`, native LSP, ≥0.11). No plugin manager, no distro.
- **`link` semantics live in botu, not here** — this repo only *declares* links in the botufile.

## Gotchas

- **dot-claude vs .claude**: `dot-claude/` is the source of truth for **user/global** Claude config (committed, symlinked into `~/.claude/`). The repo-root `.claude/` is this repo's **project-scoped**, gitignored config. Don't conflate them.
- **Sheldon plugin order**: `fast-syntax-highlighting` must be last in `sheldon/plugins.toml` (it wraps every existing ZLE widget at load).
- **`gh` auth is keychain-backed**: token in the login keychain (gh secure storage); `~/.config/gh/hosts.yml` carries only non-secret metadata. Never `gh auth login --insecure-storage`.
- **The engine is `botu`**: anything about apply/verify/fix semantics, symlink internals, the manifest, or orphan reaping lives in `github.com/alxjrvs/botu`, not here. This repo is config.
