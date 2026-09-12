# Gotchas still armed

Traps that cost a day once: one mechanism and the rule it forces, in one place. History is in
the PRs; when a subject is gone, delete its entry.

## Claude Code

- **Go binaries cannot verify TLS inside the Bash sandbox on macOS** (`gh`, `op`, `chezmoi`):
  Seatbelt denies the `com.apple.trustd.agent` Mach lookup that Go's `crypto/x509` needs.
  `sandbox.network.allowMachLookup` names that one service and nothing else.
  `enableWeakerNetworkIsolation` is documented for MITM proxies, and `excludedCommands` is
  skipped for a command inside a shell loop. Linux has no trustd and no such failure.
- **The sandbox is not the whole control for secrets.** The login keychain is reachable inside
  it and a `gh alias` body runs unsandboxed, so `security find-generic-password`,
  `gh auth token` and `git credential` are text-denied in `permissions.deny`. A text-deny
  matches the whole command text, subshells and heredocs included, so a command that merely
  mentions a denied string is denied: anchor on a verb, never a path.
- **A tool failing inside the sandbox reports it in its own vocabulary,** and looks like a
  broken repo: `brew bundle check` exits nonzero there while printing that the Brewfile is
  satisfied.
- **User-scoped MCP servers live only in `~/.claude.json`,** which nothing tracks; the
  provision script converges them on every apply.
- **Claude Code rewrites `~/.claude/settings.json` in its own key order,** so a whole-file copy
  is drift by the next session. The target is a `modify_` script: the declared keys converge,
  keys the app adds stay, and the on-disk order is kept, so a rewrite is not drift. A `/plugin`
  toggle of a declared plugin is undone by the next apply; an undeclared one it keeps. Edit the
  source, never the applied file.
- **The desktop app runs its own bundled Claude Code, not `~/.local/bin/claude`,** and the two
  update on different schedules. A settings key is verified in a terminal and in the Code tab.

## chezmoi

- **Nothing removes a target whose source was deleted.** `.chezmoiremove` is the one mechanism.
- **`run_onchange_` records its hash even when the script exits 0 early.** Anything that may
  need to retry (behind `gh auth login`) belongs in the every-apply script.
- **A run script cannot call `chezmoi`:** the outer apply holds the persistent-state lock, so
  the inner one times out and fails the apply. Scripts get `CHEZMOI_SOURCE_DIR` and
  `CHEZMOI_WORKING_TREE` in their environment instead.
- **Under `.chezmoiroot`, `.chezmoi.sourceDir` is the `home/` subdirectory,** so the documented
  `sourceDir = {{ .chezmoi.sourceDir }}` pin would make init look for `home/home`. The config
  template pins `.chezmoi.workingTree`.
- **Scripts sort by target path, so a subdirectory under `.chezmoiscripts` reorders them:**
  `darwin/10-brew` runs after `50-provision`. The directory stays flat; `.chezmoiignore` names
  the Mac-only scripts instead (a template gate on line 1 would also break CI's shellcheck).

## GitHub

- **The ruleset requires the check named `lint`; a job beside it merges red under auto-merge.**
  `lint` is the summary job, and it fails unless every matrix leg succeeded.
- **Secret scanning, push protection and the ruleset are repo settings, not repo files:** a
  fork starts with none of them. `.github/gate.sh` sets them; nothing turns them on by itself.

## Shell

- **`/etc/zprofile` runs `path_helper`, which rebuilds PATH from scratch.** PATH additions go in
  `.zprofile`, after it.
