# Gotchas still armed

Traps that cost a day once, each with the rule it forces. A trap explained beside its code lives
there, not here; when a subject is gone, delete its entry. History is in the PRs.

## Claude Code

- **Go binaries cannot verify TLS inside the Bash sandbox on macOS** (`gh`, `op`, `chezmoi`):
  Seatbelt denies the `com.apple.trustd.agent` Mach lookup that Go's `crypto/x509` needs.
  `sandbox.network.allowMachLookup` names that one service and nothing else. Linux has no
  trustd and no such failure.
- **The sandbox is not the whole control for secrets.** The login keychain is reachable inside
  it (`gh` keeps its token there) and a `gh alias` body runs unsandboxed, so
  `security find-generic-password`, `gh auth token` and `git credential` are text-denied in
  `permissions.deny`. A text-deny matches the whole command text, subshells and heredocs
  included, so a command that merely mentions a denied string is denied: anchor on a verb, never
  a path.
- **The desktop app runs its own bundled Claude Code, not `~/.local/bin/claude`,** and the two
  update on different schedules. A settings key is verified in a terminal and in the Code tab.

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

- **`defaults write` to a key the app does not read is converged and does nothing.** Check the
  key name against what the app reads, not against a blog post.
