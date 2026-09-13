# Gotchas still armed

Traps that cost a day once, each with the rule it forces. A trap explained beside its code lives
there, not here; when a subject is gone, delete its entry. History is in the PRs.

## Claude Code

- **Go binaries cannot verify TLS inside the Bash sandbox on macOS** (`gh`, `op`, `chezmoi`):
  Seatbelt denies the `com.apple.trustd.agent` Mach lookup that Go's `crypto/x509` needs.
  `sandbox.network.allowMachLookup` names that service. Linux has no trustd and no such
  failure.
- **`op` reaches the 1Password app over XPC, not a socket:** the Mach service
  `2BUA8C4S2C.com.1password.browser-helper` is the other name in `allowMachLookup`. The app's
  own authorization prompt remains the gate.
- **The sandbox is not the whole control for secrets.** The login keychain is reachable inside
  it (`gh` keeps its token there) and a `gh alias` body runs unsandboxed, so
  `security find-generic-password`, `gh auth token` and `git credential` are text-denied in
  `permissions.deny`. A text-deny matches the whole command text, subshells and heredocs
  included, so a command that merely mentions a denied string is denied: anchor on a verb, never
  a path.
- **The desktop app runs its own bundled Claude Code, not `~/.local/bin/claude`,** and the two
  update on different schedules. A settings key is verified in a terminal and in the Code tab.
- **An auto-mode denial is visible only in `/permissions` › Recently denied** (or a
  PermissionDenied hook); the denial log hook is gone, so "no denials in the log" proves
  nothing.
- **`chezmoi apply` cannot run inside the Bash sandbox:** its write scope is the working
  directory and `$TMPDIR`, every target and the state db are under `~`, and the `~/.claude`
  targets are paths no `allowWrite` can exempt. `sandbox.excludedCommands` runs `apply` and
  `update` unsandboxed; an agent passes `--force`, because after an app rewrite of
  settings.json chezmoi asks on a TTY it does not have. `verify`, `status` and `diff` run
  sandboxed.
- **Two writers rewrite `~/.claude/settings.json`.** The CLI preserves the mode and re-emits
  the file in its own key order with a trailing newline; the desktop shell writes it itself for
  its UI actions (plugin toggles, output style, workflow consent), mode 0600, key appended
  last, no trailing newline. The source is `private_`, carries every key either writer adds,
  and keeps its newline; a desktop-UI write is red by one byte until the next CLI write or
  apply. A choice saved by the CLI that the template does not declare lasts until the next
  apply; `chezmoi diff` shows what would go.
- **On Linux the sandbox needs bubblewrap and socat, and without them runs unsandboxed** after
  a warning. In a devcontainer the outer boundary is the sandbox; on a Linux desktop, install
  both.

## chezmoi

- **Apply never removes a target whose source was deleted.** The PR that deletes a source names
  the `rm` for each machine; `.chezmoiremove` is for a removal too big to type.
- **`run_onchange_` records its hash whenever the script exits 0, an early guard included.**
  Anything that may need a retry (behind `gh auth login`) is a `run_` script.
- **A run script cannot call `chezmoi`:** the outer apply holds the persistent-state lock, so
  the inner one times out and fails the apply.
- **`.chezmoiscripts` stays flat.** Scripts run in ASCII order of their target path, so a
  subdirectory reorders them; a template gate on line 1 instead would break CI's shellcheck on
  the raw source.

## macOS

- **op-ssh-sign waits on the 1Password app's authorization dialog.** A locked app blocks a
  human `git commit` from an unattended terminal; agents are unaffected, their settings env
  sets `commit.gpgSign=false`.
- **`defaults write` to a key the app does not read is converged and does nothing.** Check the
  key name against what the app reads, not against a blog post.
