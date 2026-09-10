# Gotchas still armed

Traps that cost a day once: one mechanism and the rule it forces, in one place. History is in
the PRs; when a subject is gone, delete its entry.

## Claude Code

- **Go binaries cannot verify TLS inside the Bash sandbox** (`gh`, `op`, `chezmoi`, `gcloud`).
  `gh` is in `sandbox.excludedCommands`; `chezmoi apply` runs from a normal terminal. `op-sa`
  is deliberately not excluded, so `op-sa read` fails there instead of reaching the vault.
- **The sandbox is not the whole control for secrets.** The keychain is reachable inside it and
  a `gh alias` body runs unsandboxed, so `op-sa`, `security find-*`, `gh auth token` and
  `gh alias` are text-denied in `permissions.deny`.
- **A tool failing inside the sandbox reports it in its own vocabulary,** and looks like a
  broken repo: `brew bundle check` exits nonzero there while printing that the Brewfile is
  satisfied. `excludedCommands` matches what the agent typed, not grandchildren.
- **A Bash permission rule matches the whole command text,** subshells and heredocs included: a
  command that merely mentions a denied string is denied. Anchor on a verb, never a path.
- **The empty-string `NINETY_API_TOKEN` in `settings.json` is load-bearing:** Claude Code passes
  an unset `${VAR}` through as a literal, and the empty string keeps that placeholder out of the
  plugin's hands.
- **A `PreToolUse` matcher matches a tool name, and an MCP tool is not `Bash`.** A boundary on
  the MCP path is a `mcp__github__<tool>` entry in `permissions.deny`; none is set, by choice.
- **`gh` is the one GitHub credential, and the agent holds it.** The `gh` verb rules in
  `permissions.deny` are the only thing between the agent and a release, a gist, or the token.
- **User-scoped MCP servers live only in `~/.claude.json`,** which nothing tracks; the
  provision script converges them on every apply.

## 1Password

- **Item titles in the agent vault are kebab-case:** every consumer re-parses an `op://` ref
  through `sh -c`, and a space word-splits it silently.
- **Service-account tokens have no visible expiry** anywhere. Mint with the default lifetime
  and revoke on incident; a scheduled rotation has nothing to observe. A plugin that suddenly
  has no token is the only signal.
- **`op run --env-file` works for an agent only through `op-sa`:** the desktop integration
  needs Touch ID and is revoked when the app locks.
- **`security … -w` with no value cannot be scripted:** it reads `/dev/tty`, ignores a piped
  value under an interactive shell, and two bare Returns store an empty secret.

## chezmoi

- **Nothing removes a target whose source was deleted.** `.chezmoiremove` is the one mechanism.
- **Target modes come from the source name** (`executable_`, `private_`), never the checkout.
- **`run_onchange_` records its hash even when the script exits 0 early.** Anything that may
  need to retry (behind `gh auth login`) belongs in the every-apply script.
- **A run script cannot call `chezmoi`:** the outer apply holds the persistent-state lock, so
  the inner one times out and fails the apply. Scripts get `CHEZMOI_SOURCE_DIR` and
  `CHEZMOI_WORKING_TREE` in their environment instead.

## Shell and tools

- **`/etc/zprofile` runs `path_helper`, which rebuilds PATH from scratch.** PATH additions go in
  `.zprofile`, after it.
- **`fzf --zsh` binds Ctrl-R in viins and vicmd;** an empty `FZF_CTRL_R_COMMAND` before the
  eval makes it skip that binding so atuin's wins.
- **Homebrew's completions are not on `fpath`** unless `.zshrc` adds them.
- **Karabiner rewrites `karabiner.json`** in its own key order when edited in its UI:
  `chezmoi re-add ~/.config/karabiner/karabiner.json` afterwards.
- **`brew bundle` never uninstalls;** `brew bundle cleanup` lists the other half.
- **heroku has no homebrew-core formula** and its tap is untrusted, so a Brewfile line stops a
  fresh machine at a prompt. `mise x npm:heroku -- heroku` when needed.
