# Gotchas still armed

Each is the reason behind a line of `home/.chezmoitemplates/claude-settings.json`, which JSON
cannot carry. They move into that template as comments, or become settings, and then this file
goes. Every other trap is a check in `mise run lint` or `mise run apply-check`.

- **Go binaries (`gh`, `op`, `chezmoi`) cannot verify TLS inside the Bash sandbox** without the
  `com.apple.trustd.agent` Mach service, so `sandbox.network.allowMachLookup` names it.
- **`op` reaches the 1Password app over XPC, not a socket.** Its Mach service
  (`2BUA8C4S2C.com.1password.browser-helper`) is the other name in `allowMachLookup`. The app's
  own authorization prompt is still the gate.
- **The sandbox confines writes; reads are open unless named.** The login keychain and tool
  login files are readable inside it. In auto mode the classifier is what stops exfiltration:
  `classifyAllShell` sends every shell command through it, and WebFetch has no allow rule.
- **`permissions.deny` matches text anywhere in the command**, so `*op read*` also denies
  `grep "loop read"`. Anchor on a verb, never on a path. It is a floor, not a wall.
- **`chezmoi update` cannot run inside the Bash sandbox:** it writes all over `~`.
  `sandbox.excludedCommands` runs it unsandboxed. An agent passes `--force`, because chezmoi
  otherwise asks on a terminal the agent does not have.
- **Set `git config user.*` only in a throwaway repo** (`git -C "$tmp"`) or through
  `GIT_CONFIG_KEY_n`, never bare in a checkout: every worktree shares the checkout's
  `.git/config`, and `verify` cannot see it.
- **op-ssh-sign waits on the 1Password app's authorization dialog.** Agents' settings turn off
  `commit.gpgSign` only, so an agent's `git tag` waits on it.
