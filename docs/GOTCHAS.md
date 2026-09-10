# Gotchas still armed

Traps that cost a day once and that no file in `home/` asserts on its own: one mechanism and
the rule it forces. History is in the PRs; when a subject is gone, delete its entry.

## Claude Code

- **Go binaries cannot verify TLS inside the Bash sandbox** (`gh`, `op`, `chezmoi`, `gcloud`).
  `gh` is in `sandbox.excludedCommands`; `chezmoi apply` runs from a normal terminal. `op-sa`
  is deliberately not excluded: an agent that types it fails there instead of reaching the vault.
- **`op` cannot serve a git push** for the same reason, and the `credential-cache` socket is
  blocked too, so the agent's push credential is git's `osxkeychain` helper with a pinned
  username.
- **A tool failing inside the sandbox reports it in its own vocabulary,** and looks like a
  broken repo. `excludedCommands` matches what the agent typed, not grandchildren. Read what a
  red line printed before believing it.
- **A Bash permission rule matches the whole command text,** subshells and heredocs included: a
  command that merely mentions a denied string is denied. Anchor on a verb, never a path.
- **A `PreToolUse` matcher matches a tool name, and an MCP tool is not `Bash`.** A boundary on
  the MCP path is `--exclude-tools` on the server registration.
- **`gh` and the `github` MCP are two credentials on one account, and `gh` is the privileged
  one:** your OAuth token with `repo`, `gist` and `workflow`. Scoping the agent PAT closes
  nothing on the `gh` path; the `gh` verb rules in `permissions.deny` stand there.
- **gh cannot hold a second identity for the agent.** Its credential helper serves only the
  active account, and the keychain slot for that token has no username, so a second
  `GH_CONFIG_DIR` overwrites it. The agent's identity is a PAT in the keychain, not a gh login.
- **User-scoped MCP servers live only in `~/.claude.json`,** which nothing tracks; the README
  registers them by hand.

## 1Password

- **Item titles in the agent vault are kebab-case:** every consumer re-parses an `op://` ref
  through `sh -c`, and a space word-splits it silently.
- **Service-account tokens have no visible expiry** anywhere. Mint with the default lifetime
  and revoke on incident; a scheduled rotation has nothing to observe.
- **The agent's PAT is fine-grained, so it expires yearly and GitHub mails a warning.** A push
  that suddenly asks for a password is this, not a broken helper.
- **A fine-grained PAT needs `Workflows: write`** to push under `.github/workflows/` and
  `Actions: read` before any MCP run or log tool answers; neither failure names the permission.
- **`op run --env-file` works for an agent only through `op-sa`:** the desktop integration
  needs Touch ID and is revoked when the app locks.
- **A keychain item is readable only by the binaries on its ACL,** and the creator is on it
  automatically. A credential git will read is written through git's helper, never `security`.
- **`security … -w` with no value cannot be scripted:** it reads `/dev/tty`, ignores a piped
  value under an interactive shell, and two bare Returns store an empty secret.

## chezmoi

- **`chezmoi verify` counts an every-apply script as a difference:** drift checks use
  `--exclude scripts`.
- **`chezmoi init` writes no config when the source has none, and removes none that exists.**
  A machine from before this repo dropped its template keeps `mode = "symlink"` in
  `~/.config/chezmoi/chezmoi.toml` until that file is deleted.
- **Nothing removes a target whose source was deleted.** `.chezmoiremove` is the one mechanism.
- **Target modes come from the source name** (`executable_`, `private_`), never the checkout.
- **`run_onchange_` records its hash even when the script exits 0 early.** Anything that may
  need to retry (behind `gh auth login`) belongs in the every-apply script.

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
