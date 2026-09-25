# Gotchas still armed

Each entry is a trap and the rule it forces. A trap explained next to its code lives there
instead. Delete an entry when its subject is gone.

## Claude Code

- **Go binaries (`gh`, `op`, `chezmoi`) cannot verify TLS inside the Bash sandbox** without the
  `com.apple.trustd.agent` Mach service, so `sandbox.network.allowMachLookup` names it.
- **`op` reaches the 1Password app over XPC, not a socket.** Its Mach service
  (`2BUA8C4S2C.com.1password.browser-helper`) is the other name in `allowMachLookup`. The app's
  own authorization prompt is still the gate.
- **The sandbox confines writes; reads are open unless named.** The login keychain and tool
  login files (`~/.convex`, `~/.expo`, netlify, wrangler) are readable inside it. In auto mode
  the classifier is what stops exfiltration: `classifyAllShell` sends every shell command
  through it, and WebFetch has no allow rule, so it sees that too.
- **`permissions.deny` matches text anywhere in the command**, so `*op read*` also denies
  `grep "loop read"`. Anchor on a verb, never on a path. It is a floor, not a wall.
- **Session transcripts are plaintext** under `~/.claude/projects/`, and they hold every file
  an agent read, for thirty days.
- **The desktop app runs its own bundled Claude Code, not `~/.local/bin/claude`.** The two
  update on different schedules, so check a settings key in both a terminal and the Code tab.
- **An auto-mode denial shows up only in `/permissions` › Recently denied.**
- **`autoMode` is user scope, so it governs only this machine's CLI.** A cloud session takes its
  mode from the web UI, and none of `~/.claude` reaches it. There, the ruleset on `main` is the
  only guard.
- **`chezmoi update` cannot run inside the Bash sandbox:** it writes all over `~`.
  `sandbox.excludedCommands` runs it unsandboxed. An agent passes `--force`, because chezmoi
  otherwise asks on a terminal the agent does not have.
- **Set `git config user.*` only in a throwaway repo** (`git -C "$tmp"`) or through
  `GIT_CONFIG_KEY_n`, never bare in a checkout. Every worktree shares the checkout's
  `.git/config`, and `verify` cannot see it.
- **A push that changes `.github/workflows/` needs the `workflow` scope**, which `gh auth
  login` does not request, and the rejection reads like branch protection. Agents push over
  HTTPS (the `insteadOf` pairs in the settings), so the fix is
  `gh auth refresh -h github.com -s workflow`, once, by hand.
- **On the web, an expired claude.ai login stalls a `/loop`** until the next `/login`.

## chezmoi

- **Apply never removes a target whose source was deleted.** The PR that deletes a source says
  what to `rm` on the Mac.
- **A `run_onchange_` script records its hash whenever it exits 0, even from an early guard.**
  Anything that may need a retry (for example, behind `gh auth login`) is a `run_` script.
- **`run_onchange_` on a file's hash re-runs when the file changes, not when the machine
  does.** A `brew install` by hand survives until the Brewfile next changes; `brew leaves`
  shows it. A Homebrew copy of a mise tool is not harmless: the two can migrate shared state,
  such as atuin's history database, out from under each other.
- **A run script cannot call `chezmoi`:** the outer apply holds the state lock, so the inner
  one times out and fails the apply.
- **`.chezmoiscripts` stays flat.** Scripts run in ASCII order of their target path, so a
  subdirectory would reorder them.
- **The settings modify template enforces declared keys only.** A key the app added is never
  drift, so `verify` will not flag it; `jq . ~/.claude/settings.json` shows the whole file.

## macOS

- **op-ssh-sign waits on the 1Password app's authorization dialog.** A locked app blocks a
  person's `git commit` or `git tag` from an unattended terminal. Agents' settings turn off
  `commit.gpgSign` only, so an agent's `git tag` waits on it too.
- **`defaults write` to a key the app does not read succeeds and does nothing.** Check the key
  name against what the app reads, not against a blog post.
