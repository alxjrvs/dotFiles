# Gotchas still armed

Traps that cost a day once: one mechanism and the rule it forces, in one place. History is in
the PRs; when a subject is gone, delete its entry.

## Claude Code

- **Go binaries cannot verify TLS inside the Bash sandbox on macOS** (`gh`, `op`, `chezmoi`):
  Seatbelt denies the `com.apple.trustd.agent` Mach lookup that Go's `crypto/x509` needs.
  `sandbox.enableWeakerNetworkIsolation` re-allows that one lookup and nothing else on macOS;
  `excludedCommands` is the documented alternative but is skipped for a command inside a shell
  loop. Linux has no trustd and no such failure.
- **The sandbox is not the whole control for secrets.** The keychain is reachable inside it and
  a `gh alias` body runs unsandboxed, so `op-sa`, `security find-*`, `gh auth token` and
  `gh alias` are text-denied in `permissions.deny`.
- **A tool failing inside the sandbox reports it in its own vocabulary,** and looks like a
  broken repo: `brew bundle check` exits nonzero there while printing that the Brewfile is
  satisfied.
- **A Bash permission rule matches the whole command text,** subshells and heredocs included: a
  command that merely mentions a denied string is denied. Anchor on a verb, never a path.
- **A `PreToolUse` matcher matches a tool name, and an MCP tool is not `Bash`.** A boundary on
  the MCP path is a `mcp__github__<tool>` entry in `permissions.deny`; none is set, by choice.
- **`gh` is the one GitHub credential, and the agent holds it.** The `gh` verb rules in
  `permissions.deny` are the only thing between the agent and a release, a gist, or the token.
- **User-scoped MCP servers live only in `~/.claude.json`,** which nothing tracks; the
  provision script converges them on every apply.
- **`claude plugin install` rewrites `~/.claude/settings.json` in its own key order,** so a
  managed copy written first is drift by the time apply ends. Anything that installs plugins
  runs as a `run_before_` script; chezmoi's copy lands last. The same rewrite follows a
  `/plugin` toggle in the TUI: edit the source, never the applied file.
- **The desktop app runs its own bundled Claude Code, not `~/.local/bin/claude`,** and the two
  update on different schedules. A settings key is verified in a terminal and in the Code tab.

## 1Password

- **Item titles in the agent vault are kebab-case:** every consumer re-parses an `op://` ref
  through `sh -c`, and a space word-splits it silently.
- **A service-account token minted without `--expires-in` never expires,** and nothing shows
  that. Pass `--expires-in`; a plugin that suddenly has no token is then a date, not a mystery.
- **`op run --environment` and `op run --env-file` work for an agent only through `op-sa`:**
  the desktop integration needs Touch ID, is bound to a tty, and is revoked when the app locks.
- **`security … -w` with no value cannot be scripted:** it reads `/dev/tty`, ignores a piped
  value under an interactive shell, and two bare Returns store an empty secret.

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
  the Mac-only scripts instead.

## GitHub

- **The ruleset requires the check named `lint`; a job beside it merges red under auto-merge.**
  Every check lives inside that one job.
- **Secret scanning and push protection are repo settings, not repo files:** a fork starts with
  both off. The README's forking section names them; nothing in the tree can turn them on.

## Shell

- **`/etc/zprofile` runs `path_helper`, which rebuilds PATH from scratch.** PATH additions go in
  `.zprofile`, after it.
