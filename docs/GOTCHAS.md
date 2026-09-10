# Gotchas still armed

Traps that cost a day once: one mechanism and the rule it forces, in one place. History is in
the PRs; when a subject is gone, delete its entry.

## Claude Code

- **Go binaries cannot verify TLS inside the Bash sandbox** (`gh`, `op`, `chezmoi`, `gcloud`).
  `gh` is in `sandbox.excludedCommands`; `chezmoi apply` runs from a normal terminal. `op-sa`
  is deliberately not excluded, so `op-sa read` fails there instead of reaching the vault.
- **The sandbox is not the whole control for secrets.** The keychain is reachable inside it,
  `op-sa run -- env` would print the service-account token without contacting 1Password, and a
  `gh alias` body runs unsandboxed. Those spellings are text-denied in `permissions.deny`.
- **`op` cannot serve a git push** for the same TLS reason, and the `credential-cache` socket
  is blocked, so the agent's push credential is git's `osxkeychain` helper with a pinned
  username.
- **A tool failing inside the sandbox reports it in its own vocabulary,** and looks like a
  broken repo: `brew bundle check` exits nonzero there while printing that the Brewfile is
  satisfied. `excludedCommands` matches what the agent typed, not grandchildren.
- **A Bash permission rule matches the whole command text,** subshells and heredocs included: a
  command that merely mentions a denied string is denied. Anchor on a verb, never a path.
- **The empty-string `NINETY_API_TOKEN` in `settings.json` is load-bearing:** Claude Code passes
  an unset `${VAR}` through as a literal, and the empty string keeps that placeholder out of the
  plugin's hands.
- **A `PreToolUse` matcher matches a tool name, and an MCP tool is not `Bash`.** A boundary on
  the MCP path is `--exclude-tools` on the server registration; none is set, by choice.
- **`gh` and the `github` MCP are two credentials on one account, and `gh` is the privileged
  one:** your OAuth token with `repo`, `gist` and `workflow`. Scoping the agent PAT closes
  nothing on the `gh` path; the `gh` verb rules in `permissions.deny` stand there.
- **gh cannot hold a second identity for the agent.** Its credential helper serves only the
  active account, and the keychain slot for that token has no username, so a second
  `GH_CONFIG_DIR` overwrites it. The agent's identity is a PAT in the keychain, not a gh login.
- **User-scoped MCP servers live only in `~/.claude.json`,** which nothing tracks; the
  provision script converges them on every apply.

## 1Password

- **Item titles in the agent vault are kebab-case:** every consumer re-parses an `op://` ref
  through `sh -c`, and a space word-splits it silently.
- **Service-account tokens have no visible expiry** anywhere. Mint with the default lifetime
  and revoke on incident; a scheduled rotation has nothing to observe. The provision script
  prints one line when a read fails, which is the only signal.
- **The agent's PAT is fine-grained, so it expires, and GitHub mails a warning.** A push that
  suddenly asks for a password is this, not a broken helper. Rotate it in the vault; the next
  apply propagates it.
- **A fine-grained PAT needs `Workflows: write`** to push under `.github/workflows/` and
  `Actions: read` before any MCP run or log tool answers; neither failure names the permission.
- **`op run --env-file` works for an agent only through `op-sa`:** the desktop integration
  needs Touch ID and is revoked when the app locks.
- **A keychain item is readable only by the binaries on its ACL,** and the creator is on it
  automatically. A credential git will read is written through git's helper, never `security`.
- **`git-credential-osxkeychain store` is a silent no-op on an existing item before git 2.45.**
  `erase` first: a no-op when absent, scoped to the username, and re-creating the item keeps its
  ACL pointing at the helper Xcode currently ships.
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
