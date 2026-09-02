# dotFiles

Pure config for [boom](https://github.com/alxjrvs/boom) — there is no engine code here. The repo
is `boomfile.toml` plus the payload it links into place. Anything about apply/verify/link
semantics, the manifest, or reaping belongs to boom: read the `boom` skill, regenerated from the
installed binary on every sync. `boom source` reconciles the machine; `boom verify` reports drift.

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

- `dot-claude/` is the **user-global** Claude config, symlinked into `~/.claude/`. The repo-root
  `.claude/` is this repo's project scope. Don't conflate them.
- CLIs go in `mise.toml`. `Brewfile` is casks, system libs, and the two bootstraps (`mise`,
  `boom`). `gh` extensions are a `pkg` entry over `gh-extensions.txt`. Upgrading is
  `brew upgrade --formula` then `mise upgrade`. No boom verb upgrades; `boom source --update`
  did, casks included, and is gone in boom 0.38.
- `claude` is a shell function (`zsh/65-claude.zsh`), so `which claude` misleads.
- `gh` auth is keychain-backed; never `--insecure-storage`.
- Never hand-edit a lockfile. nvim is plugin-free. `biome.json` and `dot-claude/settings.json`
  carry only divergences from defaults — don't tidy a key away without reading why it is there.
- Secrets: `op://` references only, never a plaintext token, never a `${VAR}` in a tracked
  `.mcp.json`. To use a secret, pass it (`op run --env-file=F -- CMD`), never read it.
- The hooks, guards, and their suites carry their own reasoning in their headers. Each guard fails
  open by design; add a regression case before changing one.
- Reasons, incidents, measurements: `dot-claude/DECISIONS.md`. Not symlinked, so it costs nothing
  per session — which is exactly why it, and not this file, holds the history.
