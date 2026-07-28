# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[**boom**](https://github.com/alxjrvs/boom) — the small TypeScript dotfiles+workspace
engine extracted from this repo. This repo is pure *config*: a `boomfile`, a
couple of `hooks/`, and the payload boom symlinks into place. The prompt is
[starship](https://starship.rs); the Claude Code statusline lives in its own
repo ([thegnarco/claude-statusline](https://github.com/thegnarco/claude-statusline)).

## Philosophy

Small, native, and legible by intent. Configs carry only deliberate divergences
from a tool's defaults — never a line that restates one. Every dependency is
guilty until proven load-bearing; bespoke machinery gets cut the moment a
built-in can do the job (extracting the engine into `boom` was the largest such
cut). One config runs on every machine with no host overlays. The full set of
principles lives in [`CLAUDE.md`](CLAUDE.md#northern-principles).

## Setup (fresh machine)

```bash
curl -fsSL https://raw.githubusercontent.com/alxjrvs/boom/main/install.sh | sh
boom source set alxjrvs/dotFiles
```

`boom source set` clones this repo into boom's managed config cache, records it,
and reconciles the machine. Preview without touching anything first:
`boom source --dry-run`.

## Day-to-day

The command surface belongs to boom, not this repo, so it isn't restated here (and
can't drift out of date). The canonical reference is the [boom docs][boom-docs] —
or `boom --help` / `boom man` locally. In practice you'll reach for two verbs:
**`boom source`** re-syncs the machine from `boomfile.toml` after you edit config
(fast on a no-op; `--only="<section>"` scopes it, `--dry-run` previews); **`boom
verify`** is the read-only drift check (exit `0` clean / `2` warn / `1` fail).

[boom-docs]: https://alxjrvs.github.io/boom/

## Making it yours

Everything here is policy except a handful of identity values:

| What | Where |
|------|-------|
| Git name + email | `.gitconfig` `[user]` |
| 1Password signing-key item name | `boomfile` / the `git-signing` setup (default `GitHubSSH`) |
| MCP token references | `dot-claude/settings.json` `*_COMMAND` resolvers → `op-agent secret op://…` |
| 1Password vault filter for SSH keys | `ssh/1password-agent.toml` |
| Statusline source repo | `hooks/claude_statusline.ts` (`repo=…` in the boomfile) |
| Editor / identity prefs | `dot-claude/CLAUDE.md` |

## What's here

| Path | Purpose |
|------|---------|
| `boomfile` | The config boom reads — symlink table, packages, macOS defaults, inline steps, hooks |
| `hooks/` | Imperative escape hatches: `op-agent.sh` (1Password-agent CLI), `claude_statusline.ts` |
| `.zshrc` / `zsh/` | Thin loader + numbered zsh fragments |
| `.gitconfig`, `.gitmessage` | Git identity, commit template, 1Password SSH signing |
| `git-template/hooks/pre-commit` | Per-repo gitleaks + MCP-secret guard, copied into new repos via `init.templateDir` |
| `starship.toml` | Prompt |
| `ghostty/config` | Terminal (Ghostty, sole terminal) |
| `nvim/init.lua` | Plugin-free neovim (native LSP, ≥0.11) |
| `dot-claude/` | Claude Code `CLAUDE.md` + `settings.json` (symlinked into `~/.claude/`) |
| `Brewfile` / `mise.toml` | Packages (Lean A: brew = casks, mise = dev CLIs) |
| `sheldon/`, `atuin/`, `bat/`, `ssh/`, `gh/config.yml` | Payload configs |
| `lefthook.yml`, `.github/workflows/lint.yml` | Lint gate (shellcheck + shfmt + gitleaks) for this repo's shell |
| `LICENSE` | MIT |

## Secrets, signing, terminal, packaging

The load-bearing doctrine lives in [`CLAUDE.md`](CLAUDE.md): the `op-agent` CLI
(one verb-dispatched script for the agent service account, git PAT, and on-demand
secret reads), the Lean-A packaging policy, the Ghostty terminal,
and 1Password commit signing. In brief:

- **Git signing** is 1Password via `op-ssh-sign` (`gpg.format = ssh`); the
  machine-local `~/.gitconfig.local` carries `gpgSign`/`signingkey` so a box
  without 1Password doesn't fail commits.
- **1Password SSH agent**: `ssh/config` points `IdentityAgent` at the 1Password
  8 socket — enable it in 1Password → Settings → Developer first.
- **Caps Lock → Control** natively via `hidutil` (a RunAtLoad LaunchAgent, `launchd/com.alxjrvs.capslock-control.plist`) — no Karabiner kernel extension.
- **Editor**: `nvim`, a single plugin-free `init.lua`; LSP binaries via mise.

## The engine

Anything about reconcile/verify semantics, symlink internals, the manifest, or
orphan reaping lives in [**boom**](https://github.com/alxjrvs/boom) and its
[docs][boom-docs], not here. This repo is boom's first consumer — and the
reference example of a `boomfile`.
