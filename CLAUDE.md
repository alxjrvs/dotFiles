# dotFiles

A [chezmoi](https://www.chezmoi.io) source repo; there is no engine code. `home/` is the source
state (chezmoi's `dot_`/`private_` naming), everything else is repo plumbing. `chezmoi apply`
reconciles the machine; `chezmoi verify` is the drift signal.

## Principles

North Star: **small, exemplary, easily shareable: a senior engineer's showpiece, not an
over-engineered personal artifact.** When a rule and a principle collide, surface the tradeoff.

- Native over special: deleting custom code for a built-in is the highest-value change.
- Guilty until proven load-bearing: every dependency, wrapper, and line earns its weight.
- One config, every machine: no host detection. A once-per-machine command beats convergence
  code that runs on every apply.
- Standard, and agentic-enabled: 1Password, git, ssh, `gh`, MCP stay stock, wired for agents.
- Keep it legible: one line on the decision, nothing on the mechanism.

## Local facts

- `home/dot_claude/` is the **user-global** Claude config (`~/.claude/`). The repo-root
  `.claude/` is this repo's project scope. Don't conflate them.
- Every CLI and app is a Brewfile line; mise holds only node and bun. `chezmoi apply`
  reconciles and never upgrades.
- Machine setup is three chezmoi `run_` scripts in `home/`: `onchange` on the Brewfile hash,
  `onchange` on the macOS defaults, and an every-apply idempotent provision script.
- `gh` auth is keychain-backed; never `--insecure-storage`.
- nvim is plugin-free. `home/dot_claude/settings.json` carries only divergences from defaults.
- Secrets: `op://` references only, never a plaintext token. To use one, pass it
  (`op run --env-file=F -- CMD`), never read it.
- A source file's mode comes from its name (`executable_`, `private_`), never from the checkout.
- Traps still armed and the rule each forces: `docs/GOTCHAS.md`. History is the PRs.
