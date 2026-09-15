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
- **The sandbox contains writes, not secrets.** `WebFetch(domain:*)` opens every host to
  sandboxed Bash (only the `domain:` form feeds the sandbox; a bare `WebFetch` looks the same
  and silently restores per-host prompts), the login keychain and every tool's login file
  (`~/.convex`, `~/.expo`, netlify, wrangler) are readable inside it, and there is no built-in
  credential deny list. In auto mode the classifier is the exfiltration control for shell,
  guaranteed by `classifyAllShell` — it never sees the `WebFetch` tool itself, which an allow
  rule resolves ahead of it and auto mode does not drop on entry, so `WebFetch(domain:*)`
  fetches any URL in every unattended run. `sandbox.network.allowedDomains` with
  `strictAllowlist` was the candidate boundary and is **declined**: the sandbox is inert on two
  of the three surfaces, so it buys a Mac-only fence at the price of a hard denial on every host
  the allowlist has not measured. The classifier is the accepted control. #286's sixteen-domain
  list survives at `git show 4800e9d:dot-claude/settings.json` if that is ever revisited.
- **The `permissions.deny` patterns are a floor, and a macOS-shaped one:** `gh auth status -t`
  matches none of them and neither does its `--show-token` long form, `security` exists only on
  a Mac, and on Linux the token is one `cat ~/.config/gh/hosts.yml` away. `*op read*` is a
  two-character anchor, so `grep -r "loop read" src/` is denied with it. A text-deny matches the
  whole command text, subshells and heredocs included: anchor on a verb, never a path.
- **The session transcript is plaintext, under `~/.claude/projects/**/*.jsonl`,** and holds
  every file every agent read. `cleanupPeriodDays` is unset, so thirty days applies; the
  directory is outside `permissions.deny`, outside the sandbox and outside `chezmoi verify`.
  Never set it to `0` — that stops writing transcripts rather than keeping them.
- **The desktop app runs its own bundled Claude Code, not `~/.local/bin/claude`,** and the two
  update on different schedules. A settings key is verified in a terminal and in the Code tab.
- **An auto-mode denial is visible only in `/permissions` › Recently denied** (or a
  PermissionDenied hook); the denial log hook is gone, so "no denials in the log" proves
  nothing.
- **`autoMode` is user-or-managed scope, so it governs this CLI and nothing else.** A cloud
  session takes its mode from the web dropdown and pushes with the GitHub proxy's scoped
  credentials; no key under `~/.claude` reaches it, the hard-deny on the default branch
  included.
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
- **A test or agent that sets `git config user.*` does it in its own temp repo** (`git -C
  "$tmp"`) or through `GIT_CONFIG_KEY_n`, never bare in a checkout: the source checkout's
  `.git/config` is shared by every worktree, is not a chezmoi target so `verify` cannot see it,
  and since #388 nothing in the settings env masks `user.*`. A fixture identity authored real
  commits this way twice.
- **A push that touches `.github/workflows/` needs the `workflow` scope `gh auth login` never
  requests** (`repo`, `read:org`, `gist`), and the rejection reads like branch protection. SSH
  pushes are exempt, but the `insteadOf` pair in `private_settings.json.tmpl` rewrites every
  GitHub remote to HTTPS, so no agent session can reach that escape.
  `gh auth refresh -h github.com -s workflow` is the fix, once, by hand.
- **On Linux the sandbox needs bubblewrap and socat, and without them runs unsandboxed** after
  a warning. Neither is present in a devcontainer or in Claude Code on the web, so every
  `sandbox` key is inert on two surfaces of three and the container is the boundary; on a Linux
  desktop, install both. Never `failIfUnavailable`: it would refuse to start Claude Code on
  every Linux host here.

## chezmoi

- **`apply` renders whatever branch the source checkout is on and says nothing.** A session in
  any repo can `git switch` there (Claude Code's worktree isolation guards only the repo it was
  launched from); `update` then fails on a branch with no upstream, and `verify` compares the
  machine against not-main. The rule: the checkout stays on `main`.
- **`claude --teleport` checks out the cloud session's branch in the local checkout,** which
  springs the rule above with one command. Never teleport a dotFiles session into
  `~/Code/dotFiles`: finish it on the web, or teleport from a worktree once the Mac has
  confirmed a linked worktree passes teleport's repository check. A dirty tree only downgrades
  it to a stash prompt.
- **Never `--init` with `--source` from a worktree:** the config template pins `sourceDir` to
  the working tree it was rendered from, and the app deletes that directory with the worktree.
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
