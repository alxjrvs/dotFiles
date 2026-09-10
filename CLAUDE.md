# dotFiles

A [chezmoi](https://www.chezmoi.io) source repo; there is no engine code. `home/` is the source
state (chezmoi's `dot_`/`private_` naming), everything else is repo plumbing. `chezmoi apply`
reconciles the machine; `chezmoi verify` is the drift signal.

## Principles

North Star: **small, exemplary, easily shareable: a senior engineer's showpiece, not an
over-engineered personal artifact.** When a rule and a principle collide, surface the tradeoff.

- Native over special: deleting custom code for a built-in is the highest-value change.
- Guilty until proven load-bearing: every dependency, wrapper, and line earns its weight.
- One source, every machine: `.chezmoiignore` names what is Mac-only, a runtime guard covers a
  tool that may be absent, and no by-hand step remains that `chezmoi apply` could converge.
- Standard, and agentic-enabled: 1Password, git, ssh, `gh`, MCP stay stock, wired for agents.
- Keep it legible: one line on the decision, nothing on the mechanism.

## Local facts

- `home/dot_claude/` is the **user-global** Claude config (`~/.claude/`). The repo-root
  `.claude/` is this repo's project scope. Don't conflate them.
- CLIs and apps are Brewfile lines, Mac only; mise holds node, bun and the npm-built language
  servers; the Claude Code CLI is the native installer and git is the system's. `chezmoi apply`
  reconciles and never upgrades.
- Machine setup is `home/.chezmoiscripts/`, flat: `onchange` on the Brewfile hash, `onchange` on
  the macOS defaults, and an every-apply idempotent provision script.
- One GitHub identity: `gh auth login`, keychain-backed, never `--insecure-storage`.
- nvim is plugin-free. `home/dot_claude/settings.json` carries divergences from defaults; don't
  tidy a key away without reading why it is there.
- Secrets: `op://` references only, never a plaintext token, and nothing here prints one.
- A source file's mode comes from its name (`executable_`, `private_`), never from the checkout.
- CI's `lint` job is the one required check and the only Linux test; every check lives in it.
- Traps still armed and the rule each forces: `docs/GOTCHAS.md`. History is the PRs.
