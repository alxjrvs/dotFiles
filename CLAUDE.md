# CLAUDE.md

This file guides Claude Code (claude.ai/code) when working in this repository.

## What This Is

A macOS **dotfiles repo** that is pure **config for [BoomTube](https://github.com/alxjrvs/botu)** — the small TypeScript dotfiles+workspace engine (the executable is `botu`), compiled to a single binary on `PATH`. This repo is its *first consumer*. There is no engine code here: the whole repo is a `botufile.toml` (the config), a handful of TypeScript `hooks/`, and the payload (`.zshrc`, `zsh/`, `nvim/`, `dot-claude/`, `Brewfile`, `mise.toml`, …) that botu symlinks into place.

```
botu init ~/Code/DevEnv/Dotfiles   # record this repo (writes botuinit.sh)
botu apply        # symlink/copy/install/run from the botufile.toml
botu verify       # check drift (exit 0 ok / 2 warn / 1 fail); --json for a report
botu fix          # repair drift (incl. reaping orphaned links)
botu rollback     # undo the last apply (restores backed-up files)
botu uninstall    # remove every managed link
```

Fresh machine: `git clone … && ./Dotfiles/botuinit.sh` (installs botu, points it here, applies).

## The `botufile.toml`

The config is a typed, validated TOML document; botu parses it once and runs each `[[section]]` under the verb. Within a section, resources run in phase order `link → copy → glob → packages → run → hook`. Schema:

- `[[section]]` with `name` (the `--only`/tag) and optional `when = { os, host, profile }` to gate by machine.
- `link` / `copy` `[{ src, dst, mode? }]` and `glob [{ pattern, into }]` — the symlink/copy contract (`dst` may use `~`).
- `brewfile = "FILE"` / `mise = true` — packages via the stock tools (the `Brewfile` / `mise.toml` are the data).
- `osx_default [{ domain, key, type, value }]` — a macOS default (the engine restarts the UI automatically when any changed).
- `run [{ on = "apply"|"verify", cmd }]` — a small inline imperative step.
- `hook [{ name, with? }]` — loads `hooks/<name>.ts` (a TypeScript resource module), passing `with` as inputs. For substantial imperative logic only.

Multi-machine: gate sections with `when`, or layer overlay files `botufile.<os|host|profile>.toml`.

## Northern Principles

One North Star: **small, exemplary, easily shareable — a senior engineer's showpiece, not an over-engineered personal artifact.** When a rule and a principle collide, surface the tradeoff to the owner.

1. **Native over special.** Prefer stock behavior to bespoke machinery; deleting custom code for a built-in is the highest-value change. (Extracting the engine into `botu` was the largest application of this.)
2. **Guilty until proven load-bearing.** Every dependency, wrapper, and line earns its weight on a *personal* repo, or it goes.
3. **No gratuitous wrappers.** Call tools natively. The lone bash script that survives is `op-agent`, which an external program execs by path (a plugin `*_COMMAND` resolver, see Secrets); git commit signing lives in the `git-signing.ts` hook.
4. **One config, every machine.** No host detection. Add the smallest possible guard at the point a genuine per-machine divergence appears.
5. **Standard, and agentic-enabled.** 1Password, Git, SSH, `gh`, MCP stay stock — but wired for agents. Secrets resolve through `op` on demand, never plaintext in git, never exported to the session env.
6. **Keep it legible.** Plain ops over clever math; docs explain the *decision and the gotcha*, not the *what*.

## hooks/

The imperative residue the config can't express. A botu hook is a `hooks/<name>.ts` module exporting `apply`/`verify`/`fix` functions that receive a typed `HookApi` (`with` inputs, `dryRun`, `env`, and `ok`/`warn`/`fail`/`note`); it self-locates this repo via `import.meta.dir`, and `fix` falls back to `apply`.

- **`git-signing.ts`** — converges git commit/tag signing via 1Password `op-ssh-sign` (machine-local `~/.gitconfig.local` + `~/.ssh/allowed_signers`), using the agent key named by `with.key` (default `GitHubSSH`).
- **`claude_statusline.ts`** — clones the `claude-statusline` repo beside this one and runs its installer.
- **`op-agent.sh`** — NOT a botu hook: a standalone bash CLI for all 1Password-agent machinery (see Secrets), `link`ed onto `PATH` as `op-agent` and driven by `run` steps (`op-agent provision` / `op-agent status`). Stays bash because external programs exec it by path (a plugin `*_COMMAND` resolver; git's `credential.helper`).

Small steps (`chmod 700 ~/.ssh`, `lefthook install`) are inline `run` (`on = "apply"`) entries, not files.

## Packaging policy: Lean A (brew = casks, mise = dev CLIs)

`Brewfile` holds **only** `mise` (bootstrap), casks (GUI apps, fonts), and system libs with no mise equivalent. `mise.toml` holds all language toolchains AND dev CLIs (`jq`, `shellcheck`, `shfmt`). If you're about to add a CLI to `Brewfile`, stop — it goes in `mise.toml` unless it's `mise` itself or a cask.

## Terminal: Ghostty (canonical), cmux (parallel agent sessions)

Ghostty is the daily driver (`TERMINAL=ghostty`, `ghostty/config`). cmux stays for **parallel Claude Code sessions** via `botu code cmux` (the workspace mirror, formerly `dot ws`). Two symlinked files: `ghostty/config` (rendering + Ghostty keybinds/visor; cmux also reads it for the visual subset) and `cmux/cmux.json` (cmux's app config — intentional divergences only). `botu code` mirrors `~/Code` into workspaces: `botu code init [DIR]` records the dir, `botu code claude` (symlinks every repo into one flat dir and opens `claude agents` there, so each repo is `@`-taggable for dispatch with no running agents) / `botu code cmux` (one workspace per repo).

## Secrets management

1Password (`op`) is the source of truth, following 1Password's two-tier model:

- **Interactive dev (you)** — desktop app + biometric; resolve via `op run` / `op://` refs / Environments.
- **Hands-off agent (Claude, MCP, cron)** — a **service account** scoped to the `claude-agent` vault; no biometric, no desktop dependency.

### Agent secrets — the `op-agent` CLI

`hooks/op-agent.sh` is the single script for all agent-1Password machinery, dispatched by verb:

- `op-agent provision` — idempotently ensures the `claude-agent` vault, a per-host service account with `read_items` on only that vault, and its token in the macOS login keychain (`op-claude-agent`); also confirms the `Claude Git PAT` vault item exists (a fresh-machine setup signal — the PAT is resolved on demand, never cached). Run via `on apply op-agent provision`. Foreground-only first run (minting authorizes through the desktop app).
- `op-agent status` — reports keychain token presence (`on verify`).
- `op-agent secret op://ref` — reads one secret value to stdout via the SA, the single read primitive for consumers that want a raw value (e.g. the spacebase `*_COMMAND`). **The ref is an argument, not a per-service file.** It sources the SA token from the keychain inline (no biometric, headless-safe), confined to one short-lived process so neither the token nor the secret reaches a Bash subprocess, the transcript, or OTEL. Follows the `op read` contract: value on success, nothing + nonzero on failure (so a failed read leaves the consumer's var empty and it falls through to its own default).
- `op-agent git-credential get` — git credential helper (scoped to `https://github.com` in the agent git config). Resolves the `Claude Git PAT` vault item via the same SA path as `secret` and emits `username=x-access-token` + `password=<pat>`; `store`/`erase` are no-ops (the vault is the source of truth). This is the canonical native-hook-fed-by-`op` pattern applied to git.

Every verb has a live consumer — no speculative surface. An HTTP MCP server, if one is ever added, formats its `headersHelper` Bearer line from `op-agent secret <its op:// ref>`; until then no bespoke header verb is carried.

### MCP secrets — one canonical pattern

Servers we control launch via 1Password's `op run --env-file=.env -- <server>` with `op://` references in a committable `.env` (`botu mcp add`). Plugin-bundled stdio servers use their own `*_COMMAND` resolver (e.g. spacebase's `SPACEBASE_API_KEY_COMMAND` → `op-agent secret op://…`); an HTTP server, if added, formats its `headersHelper` from `op-agent secret`. **Never write a `${VAR}` placeholder into a git-tracked `.mcp.json`/`.env`** (a later `claude mcp add` can expand it). `botu verify` and the `git-template` pre-commit both fail on a `${VAR}` in a tracked `.mcp.json` and on a resolved-token literal in any tracked `.mcp.json`/`.env`.

### Agent git auth

Git's native `credential.helper` is pointed at `op-agent git-credential` (fronted by git's `cache --timeout=900` helper), so the agent resolves its least-privilege fine-grained PAT from the `claude-agent` vault on demand — the **same single `op` primitive as every other agent secret**, the canonical "tool's own native hook fed by `op`" pattern (git's hook is the credential helper). The PAT lives only in 1Password: no keychain cache, no second mechanism. Headless, no biometric (SA token via `securityd`); the `cache` helper amortizes the per-op round-trip; and because the resolve path is `securityd` + network rather than a keychain *file* read, it survives a sandbox `credentials.files` deny on the keychain. Wired agent-only via `dot-claude/settings.json` `GIT_CONFIG_*`. Your own terminal git keeps its `gh` helper + 1Password signing.

### Rules

- Never commit a plaintext token. Use `op://` references or `op run --`.
- Controlled servers → `op run --env-file`; plugin servers → their `*_COMMAND` (→ `op-agent secret`); a future HTTP MCP server → `headersHelper` formatted from `op-agent secret`.
- npm registry auth → `npm/npmrc` (linked to `~/.npmrc`, the canonical userconfig) carries `_authToken=${NPM_TOKEN}`, expanded by npm at read time; publish via `op run -- npm publish`. Daily public installs need no token, so nothing exports a secret to the session env.
- If you find a plaintext token anywhere, revoke first, then migrate.

### Standing threats (keep the surface small)

The minimal MCP/plugin footprint is a *security* decision, not just taste — every enabled server widens the prompt-injection/exfil blast radius. Two live vectors shape the posture:

- **`~/.claude.json` postinstall hijack** (Mitiga, unpatched-by-design): a malicious npm/bun package's `postinstall` can rewrite `~/.claude.json` to MITM MCP traffic and steal OAuth tokens — invisible in provider logs. No patch is coming (it presupposes code execution as the Claude user). Native mitigations, already mostly in place: don't run untrusted `npm/bun install` as the agent user; keep MCP OAuth surface minimal; prefer scoped/fine-grained tokens (the `claude-agent` SA + per-repo PATs cap the blast radius); the `editorMode`-level `permissions.deny` floor blocks direct keychain token reads. No bespoke `~/.claude.json` integrity-checker — that's machinery this repo would otherwise delete.
- **Repo-controlled config CVEs** (CVE-2025-59536 RCE, the `enableAllProjectMcpServers` auto-approve bypass, CVE-2026-21852 `ANTHROPIC_BASE_URL` key-exfil): all patched in current Claude Code, all pre-trust-dialog. Mitigation: stay current, never set `enableAllProjectMcpServers`/`enabledMcpjsonServers` globally (`botu verify` greps for them), don't open untrusted repos under `auto` mode.

There is no canonical "must-install" plugin set; `enabledPlugins` earns each entry by use, not by hype.

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
- **The engine is `botu`** (the BoomTube project): anything about apply/verify/fix/rollback semantics, symlink internals, the manifest/journal, or orphan reaping lives in `github.com/alxjrvs/botu`, not here. This repo is config.
