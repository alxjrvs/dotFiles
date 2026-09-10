# Gotchas still armed

Traps that cost a day once and that no file in `home/` asserts on its own. Each entry is one
mechanism and the rule it forces. History lives in the PRs (`gh pr view <n>`) and `git log -S`,
not here; when a subject is gone, delete its entry.

## Claude Code

- **Go binaries cannot verify TLS inside the Bash sandbox** (macOS Seatbelt blocks the trust
  daemon): `gh`, `op`, `chezmoi`, `gcloud`. `gh` is in `sandbox.excludedCommands`; run
  `chezmoi apply` from a normal terminal, not from an agent. `op-sa` is deliberately not
  excluded, so an agent that types it fails there instead of reaching the vault.
- **The `git credential-cache` socket is blocked in the sandbox** and `op` fails there, so the
  agent's push credential is git's own `osxkeychain` helper with a pinned username, never `op`.
- **A tool that writes its own cache or reads system config fails INSIDE the sandbox, and says
  so in its own vocabulary rather than the sandbox's** — it looks like the repo is broken.
  `brew bundle check` exits nonzero there while printing that the Brewfile is satisfied.
  `sandbox.excludedCommands` matches the command the agent TYPED, not its grandchildren. Do
  not trust a red line from a sandboxed run without reading what it printed.
- **A `!` negation inside an excluded DIRECTORY is silently inert.** git never descends into an
  ignored directory, so `.claude/` plus `!.claude/settings.json` does not track that file —
  re-including one needs `.claude/*` (the glob) instead. Nothing here needs that today; the
  trap is recorded because the fix looks like it works either way until you check `git status`.
- **A `PreToolUse` matcher matches a tool NAME, and an MCP tool is not `Bash`.** A guard wired
  to `Bash` has no opinion about an `mcp__github__*` call reaching the same API. A write
  boundary on that path has to be `--exclude-tools` on the server registration; an unknown name
  in that list is ignored silently, so verify any against `generate-docs`.
- **`gh` and the `github` MCP are two credentials on one account, and `gh` is the privileged
  one.** `get_me` reports `alxjrvs` down both paths, which makes them look interchangeable. They
  are not: `gh` holds a `gho_` OAuth token carrying `repo`, `gist` and `workflow`, while the MCP
  holds the agent PAT from the vault. Scoping that PAT therefore closes nothing on the `gh` path
  — the `gh` verb rules in `permissions.deny` are what stand there, and they stay.
- **A Bash permission rule matches the whole command text.** `Bash(x:*)` is a prefix and misses
  `env x`, `/usr/bin/x`, `(x`; `Bash(*x*)` is a substring and reaches subshells, substitutions and
  loop bodies. The deny floor is substring rules anchored on a verb (`*op read*`), never a path
  (`*/op *` blocked `ls src/op x`). A hook `allow` cannot bypass a deny rule.
- **`~/.config/gh/hosts.yml` holds no token under keyring storage.** A `Read` deny on it buys
  nothing and, merged into the sandbox, made every `gh` call fail to load its config.
- **gh keys its keychain entries by host only**, so a second `GH_CONFIG_DIR` overwrites the
  active token of the first. A distinct agent GitHub identity is a PAT in the keychain, not a
  second gh login.
- **User-scoped MCP servers live only in `~/.claude.json`.** Nothing tracks that file; the
  provision script converges the two entries on every apply.
- **A rule in `home/dot_claude/rules/` loads into every session unless it has `paths:`.**

## 1Password

- **Item titles in the agent vault are kebab-case.** Every consumer re-parses an `op://` ref
  through `sh -c`; a space word-splits it and the resolve fails silently.
- **Service-account tokens have no visible expiry** anywhere in 1Password (no CLI, no UI, no
  alert), so an expired one fails every resolve at once. Mint with the default lifetime and
  revoke on incident rather than scheduling a rotation nothing can observe.
- **The agent's GitHub PAT is fine-grained, so it expires — which inverts the entry above.**
  One year maximum, and GitHub mails a warning: an observable clock, unlike the service-account
  token beside it. What lapses is every agent push and every `mcp__github__*` call at once, so a
  push that suddenly asks for a password is this, not a broken credential helper.
- **A fine-grained PAT needs `Workflows: write` to push a change under `.github/workflows/`**,
  and `Actions: read` before any `mcp__github__*` run or job-log tool answers. Neither failure
  names the missing permission usefully — the push is rejected outright and the tools simply
  return nothing — so grant both when minting rather than diagnosing it later.
- **Service-account rate limits are per account per day** on personal plans; git no longer
  goes through it (see above), which is most of what kept it busy.
- **`op run --env-file` only works for an agent through `op-sa`**: the desktop-app integration
  needs Touch ID and is revoked when the app locks.
- **A keychain item is readable only by the binaries on its ACL,** and the creating binary is on
  it automatically. So a credential git will read is written by `git-credential-osxkeychain
  store`, never by `security`: an item `security` creates needs an explicit
  `-T "$(git --exec-path)/git-credential-osxkeychain"` or the first agent push raises a dialog
  no unattended session can answer.
- **`git-credential-osxkeychain store` is not idempotent before git 2.47.** The older helper's
  store onto an item that already exists is a silent no-op, so a rotated secret never lands on a
  Mac with an older Xcode git. Send an `erase` first: it is a no-op when the item is absent, and
  it is scoped to the username, so it cannot touch the human's own entry for the same host.
- **`security … -w` with no value cannot be scripted.** It prompts through `getpass(3)`, which
  reads `/dev/tty` and falls back to stdin only when no terminal is attached — so a piped value
  is silently ignored under an interactive shell, and two bare Returns store an empty secret. It
  looks like it works when tested from a process that has no tty, which is exactly how this trap
  got into this file backwards once.
- **`security delete-internet-password` exits 44 when the item is absent.** Under `set -e` that
  aborts the script, on precisely the fresh machine a delete-then-add was meant to serve.

## chezmoi

- **`chezmoi verify` counts an every-apply script as a difference**, so drift checks use
  `--exclude scripts`.
- **`chezmoi init` writes no config when the source has no config template**, and it does not
  remove one that is already there. A machine provisioned before this repo dropped its template
  keeps `~/.config/chezmoi/chezmoi.toml` with `mode = "symlink"` and an old `sourceDir`, and
  goes on symlinking. Deleting that file is what actually drops a machine to default file mode.
- **Nothing removes a target whose source file was deleted.** `chezmoi apply` only writes; a
  retired dotfile stays in `~` until someone removes it (or `.chezmoiremove` names it).
- **Target modes come from the source name** (`executable_`, `private_`), never from the
  checkout's file mode.
- **`run_onchange_` records its hash even when the script exits 0 early.** A step that may need
  to retry (anything behind `gh auth login`) belongs in the every-apply provision script.
- **Externals fetch on apply**, so an apply needs the network once per machine and per bump.

## Shell and tools

- **`/etc/zprofile` runs `path_helper`, which rebuilds PATH from scratch** and pushes anything
  `.zshenv` set below the system entries. PATH additions go in `.zprofile`, after it.
- **`fzf --zsh` binds Ctrl-R in viins and vicmd**; atuin rebinds viins only. An empty
  `FZF_CTRL_R_COMMAND` before the eval makes fzf skip that binding.
- **Homebrew's completions are not on `fpath` unless you add them**: `brew shellenv` does not
  set FPATH.
- **Karabiner rewrites `karabiner.json`** in its own key order when edited in its UI; run
  `chezmoi re-add ~/.config/karabiner/karabiner.json` afterwards or `chezmoi verify` goes red.
- **`brew bundle` never uninstalls.** Undeclaring a formula here is half of removing it;
  `brew bundle cleanup` (a dry run by default) lists the other half. Do not declare a brew copy
  of a mise-pinned tool to silence that list.
- **heroku has no homebrew-core formula** and its tap is untrusted, so a Brewfile line for it
  stops a fresh machine at an interactive prompt. When needed: `mise x npm:heroku -- heroku`.
- **`fetch.pruneTags` deletes a local tag you have not pushed yet**; `transfer.fsckObjects`
  breaks clones of old repos and verifies no provenance. Neither is set.
- **`gh extension install` needs an authenticated gh**, which on a fresh machine comes after the
  first apply; the provision script skips and converges on the next one.
