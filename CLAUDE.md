# dotFiles

A [chezmoi](https://www.chezmoi.io) source repo in **symlink mode** — there is no engine code
here. `home/` is the source state (chezmoi's `dot_`/`private_` naming), `scripts/` holds the
checks lefthook, CI and the daily drift timer share, and everything else is repo plumbing.
`chezmoi apply` reconciles the machine; `scripts/verify.sh` reports drift.

## Principles

North Star: **small, exemplary, easily shareable — a senior engineer's showpiece, not an
over-engineered personal artifact.** When a rule and a principle collide, surface the tradeoff.

- Native over special: deleting custom code for a built-in is the highest-value change.
- Guilty until proven load-bearing: every dependency, wrapper, and line earns its weight.
- No gratuitous wrappers — call tools natively.
- One config, every machine: no host detection. Add the smallest guard where a real divergence
  appears.
- Standard, and agentic-enabled: 1Password, git, ssh, `gh`, MCP stay stock, wired for agents.
- Keep it legible: docs explain the decision and the gotcha, not the what.

## Local facts

- Symlink mode means an edit in this checkout is **live at once** — the file in `~` points
  here. Commit and push are how it reaches CI and other machines, not how it takes effect.
- `home/dot_claude/` is the **user-global** Claude config (`~/.claude/`). The repo-root
  `.claude/` is this repo's project scope. Don't conflate them.
- CLIs go in `home/dot_config/mise/config.toml`, every version pinned; Renovate bumps them.
  The Brewfile is casks, system libs, the two bootstraps (`mise`, `chezmoi`) and a few CLIs
  brew owns. `gh` extensions are `gh-extensions.txt`. Upgrading is `brew upgrade --formula`
  then `mise upgrade`; `chezmoi apply` never upgrades anything.
- Machine setup steps are chezmoi `run_` scripts in `home/`, darwin-gated by template. Each is
  either `onchange` on the hash of the file it applies, or cheap and idempotent every apply.
- `claude` is a shell function (`home/dot_config/zsh/65-claude.zsh`), so `which claude`
  misleads.
- `gh` auth is keychain-backed; never `--insecure-storage`.
- Never hand-edit a lockfile. nvim is plugin-free. `biome.json` and
  `home/dot_claude/settings.json` carry only divergences from defaults — don't tidy a key away
  without reading why it is there.
- Secrets: `op://` references only, never a plaintext token, never a `${VAR}` in a tracked
  `.mcp.json`. To use a secret, pass it (`op run --env-file=F -- CMD`), never read it.
- The hooks, guards, and their suites carry their own reasoning in their headers. Each guard fails
  open by design; add a regression case before changing one. A hook must be committed with its
  executable bit: in symlink mode it runs with the source file's mode.
- Reasons, incidents, measurements: `docs/DECISIONS.md`. Outside `home/`, so it never reaches a
  machine and costs nothing per session — which is exactly why it, and not this file, holds the
  history.
