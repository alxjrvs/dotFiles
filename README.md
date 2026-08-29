# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[**boom**](https://github.com/alxjrvs/boom) — the small TypeScript dotfiles+workspace
engine extracted from this repo. This repo is pure *config*: a `boomfile.toml`, a
couple of `hooks/`, and the payload boom symlinks into place. The prompt is
[starship](https://starship.rs); the Claude Code statusline lives in its own
repo ([TheGnarCo/claude-statusline](https://github.com/TheGnarCo/claude-statusline)).

## Philosophy

Small, native, and legible by intent. Configs carry only deliberate divergences
from a tool's defaults — never a line that restates one. Every dependency is
guilty until proven load-bearing; bespoke machinery gets cut the moment a
built-in can do the job (extracting the engine into `boom` was the largest such
cut). One config runs on every machine with no host overlays. The full set of
principles lives in [`CLAUDE.md`](CLAUDE.md#principles).

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

## Forking this repo

Ordered by what breaks first, not by where it lives. Everything else is policy.

**1 — Identity, or your commits are signed as someone else.**

| What | Where |
|------|-------|
| Git name + email | `.gitconfig` `[user]` |
| Agent commit identity | `dot-claude/settings.json` — `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_EMAIL`, and the `Co-Authored-By` trailer |

Miss these and every commit an agent makes on your machine is authored and
co-signed as `alxjrvs`, silently, into public history.

**2 — 1Password, or `boom verify` fails on day one.**

| What | Where |
|------|-------|
| Service-account vault name | `agent-vault.txt` (audited by `boom verify` against a vault named `claude-agent`) |
| Secret references | `dot-claude/settings.json` `*_COMMAND` resolvers, `npm/publish.env` — all `op://claude-agent/…` |
| SSH signing-key item | `boomfile.toml` `key = "GitHubSSH"`, and `ssh/1password-agent.toml` |

`ssh/1password-agent.toml` scopes per ITEM, not per vault — 1Password's
least-privilege recommendation, and the file says so.

**3 — Org scope, which is a security control and not a preference.**

`_owned_orgs()` in `dot-claude/hooks/guard-lib.sh` is the single source: it gates
which repos `repo-scope-guard.sh` will let an agent write to. On a fork it
protects the wrong orgs until you change it.

**4 — Cosmetic, in your own time.** The launchd labels
(`launchd/com.alxjrvs.*.plist`, wired at `boomfile.toml`), the OTEL attribution
in `.claude/settings.json`, the statusline source repo in
`hooks/claude_statusline.ts`, and the four private repos named in
`dot-claude/skills/butter-stack/SKILL.md`.

## What's here

| Path | Purpose |
|------|---------|
| `boomfile.toml` | The config boom reads — symlink table, packages, macOS defaults, inline steps, hooks |
| `hooks/` | **boom lifecycle hooks.** `op-agent.sh` (1Password-agent CLI), `git-signing.ts`, `claude_statusline.ts`, `claude-canary.sh`. The directory name is boom's contract, not a choice — `[[section.hook]]` resolves scripts from a hardcoded `hooks/`, so this cannot be renamed to something less collision-prone |
| `dot-claude/hooks/` | **Claude Code guards**, unrelated to the above: PreToolUse/SessionStart/Stop hooks plus their suites. Symlinked into `~/.claude/hooks/` |
| `git-template/hooks/` | **git hooks**, copied into every new repo via `init.templateDir` |
| `agent-vault.txt` | Declared contents of the `claude-agent` 1Password vault; drift in either direction fails `boom verify` |
| `.zshrc` / `zsh/` | Thin loader + numbered zsh fragments |
| `.gitconfig`, `.gitmessage` | Git identity, commit template, 1Password SSH signing |
| `starship.toml` | Prompt |
| `ghostty/config` | Terminal (Ghostty, sole terminal) |
| `nvim/init.lua` | Plugin-free neovim (native LSP, ≥0.11) |
| `dot-claude/` | User-global Claude config. `CLAUDE.md` + `settings.json` are symlinked into `~/.claude/` and billed to every session; `DECISIONS.md`, `SETTINGS.md`, `REFERENCE.md`, `skills/`, `hooks/` are not |
| `Brewfile` / `mise.toml` | Packages (Lean A: brew = casks, mise = dev CLIs) |
| `sheldon/`, `atuin/`, `bat/`, `ssh/`, `gh/config.yml` | Payload configs |
| `lefthook.yml`, `.github/workflows/lint.yml` | Commit + CI gate: shellcheck, shfmt, biome, gitleaks, the hook suites, and the assertions in `scripts/` |
| `scripts/` | The shared assertions both gates call, so neither can drift from the other: `context-budget.sh`, `settings-guardrails.sh`, `plist-validity.sh`, `skill-description-cap.sh`, `brew-drift.sh` |
| `LICENSE` | MIT |

## Secrets, signing, terminal, packaging

`CLAUDE.md` holds only what every session must load; the reasoning behind these
choices lives in [`dot-claude/DECISIONS.md`](dot-claude/DECISIONS.md) and the
`settings.json` key index in [`dot-claude/SETTINGS.md`](dot-claude/SETTINGS.md) —
neither is symlinked, so neither costs a session anything. In brief:

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
reference example of a `boomfile.toml`.
