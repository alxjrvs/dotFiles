# dotFiles

A [chezmoi](https://www.chezmoi.io) source repo — there is no engine code here. `home/` is the
source state (chezmoi's `dot_`/`private_` naming), `scripts/verify.sh` is the by-hand drift
check, and everything else is repo plumbing. `chezmoi apply` reconciles the machine.

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

- chezmoi's default file mode: an edit here takes effect on `chezmoi apply`; another Mac gets
  it with `chezmoi update` after it lands. `chezmoi verify` is the honest drift signal.
- `home/dot_claude/` is the **user-global** Claude config (`~/.claude/`). The repo-root
  `.claude/` is this repo's project scope. Don't conflate them.
- CLIs go in `home/dot_config/mise/config.toml`, every version pinned exactly. The Brewfile is
  casks, the two bootstraps (`mise`, `chezmoi`) and what needs a system library. `gh` extensions
  are in the provision script. Upgrading is `brew upgrade --formula` then `mise upgrade --bump`
  (plain `mise upgrade` moves nothing against exact pins); `chezmoi apply` never upgrades.
- Machine setup is three chezmoi `run_` scripts in `home/`: `onchange` on the Brewfile hash,
  `onchange` on the macOS defaults, and an every-apply idempotent provision script.
- `claude` is a shell function (`home/dot_config/zsh/claude.zsh`), so `which claude`
  misleads.
- `gh` auth is keychain-backed; never `--insecure-storage`.
- nvim is plugin-free. `biome.json` and
  `home/dot_claude/settings.json` carry only divergences from defaults — don't tidy a key away
  without reading why it is there.
- Secrets: `op://` references only, never a plaintext token, never a `${VAR}` in a tracked
  `.mcp.json`. To use a secret, pass it (`op run --env-file=F -- CMD`), never read it.
- The hooks, guards, and their suites carry their own reasoning in their headers. Each guard fails
  open by design; add a regression case before changing one. A hook source is named
  `executable_*.sh`; chezmoi sets the target's mode from that prefix.
- Reasons, incidents, measurements: `docs/DECISIONS.md`. Outside `home/`, so it never reaches a
  machine and costs nothing per session — which is exactly why it, and not this file, holds the
  history.
