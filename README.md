# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[**boom**](https://github.com/alxjrvs/boom) — the small TypeScript dotfiles+workspace
engine extracted from this repo. This repo is pure *config*: a `boomfile.toml`, a
couple of `hooks/`, and the payload boom symlinks into place. The prompt is
[starship](https://starship.rs); the Claude Code statusline lives in its own
repo ([TheGnarCo/claude-statusline](https://github.com/TheGnarCo/claude-statusline)).

## Philosophy

Small, native, and legible by intent. The principles live in
[`CLAUDE.md`](CLAUDE.md#principles) — once, there, rather than paraphrased here
and linked as well. A paraphrase beside its own source is the shape every
duplicated fact in this repo has taken before it rotted.

## Setup (fresh machine)

```bash
curl -fsSL https://raw.githubusercontent.com/alxjrvs/boom/v0.30.0/install.sh | sh
boom source set alxjrvs/dotFiles
```

The installer is pinned to a **tag, not `main`**, and that is the whole of the
change worth making here. `install.sh` already verifies the binary it downloads
against the release's published `SHA256SUMS`, refuses to install unverified, and
checks the macOS signature — so the payload was never the exposed part. The
script *fetching* it was: served from a mutable branch, it could have been
rewritten to drop those checks, and nothing would have noticed. A tag is
immutable. Bump it when `install.sh` itself changes; it bootstraps whatever the
latest boom release is, so the pin does not pin your boom version.

`boom source set` clones this repo into boom's managed config cache, records it,
and reconciles the machine. Preview without touching anything first:
`boom source --dry-run`.

## Day-to-day

The command surface belongs to boom, not this repo, so it isn't restated here (and
can't drift out of date). The canonical reference is the [boom docs][boom-docs] —
or `boom --help` locally. In practice you'll reach for two verbs:
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
| `agent-vault.txt` | The `claude-agent` 1Password vault items this repo resolves; `boom verify` fails when a declared one is missing. Not an inventory — the vault may hold more |
| `.zshrc` / `zsh/` | Thin loader + numbered zsh fragments |
| `.gitconfig`, `.gitmessage` | Git identity, commit template, 1Password SSH signing |
| `starship.toml` | Prompt |
| `ghostty/config` | Terminal (Ghostty, sole terminal) |
| `nvim/init.lua` | Plugin-free neovim (native LSP, ≥0.11) |
| `dot-claude/` | User-global Claude config. Symlinked into `~/.claude/`: `CLAUDE.md`, `settings.json`, `loop.md`, every `hooks/*.sh`, `skills/`, `agents/`, `rules/`. What is *billed to every session* is a smaller set than what is linked — the two `CLAUDE.md` files plus each skill's and agent's `description:` frontmatter, ~1,550 tokens; hook scripts and skill *bodies* cost nothing until used. `DECISIONS.md`, `SETTINGS.md`, `REFERENCE.md` are not linked at all. `scripts/context-budget.sh` owns the numbers and fails on an unbudgeted link |
| `Brewfile` / `mise.toml` | Packages (Lean A: brew = casks, mise = dev CLIs) |
| `sheldon/`, `atuin/`, `bat/`, `ssh/`, `gh/config.yml` | Payload configs |
| `lefthook.yml`, `.github/workflows/lint.yml` | Commit + CI gate: shellcheck, shfmt, biome, gitleaks, the hook suites, and the assertions in `scripts/` |
| `scripts/` | The shared assertions both gates call, so neither can drift from the other: `context-budget.sh`, `settings-guardrails.sh`, `plist-validity.sh`, `description-cap.sh`, `brew-drift.sh` |
| `LICENSE` | MIT |

## Secrets, signing, terminal, packaging

Where each kind of writing goes is stated once, in
[`CLAUDE.md`](CLAUDE.md#where-things-go); the reasoning lives in
[`dot-claude/DECISIONS.md`](dot-claude/DECISIONS.md) and the `settings.json` key
index in [`dot-claude/SETTINGS.md`](dot-claude/SETTINGS.md). Neither is
symlinked, so neither costs a session anything. In brief:

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
