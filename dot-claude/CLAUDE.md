# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`)
- Shell: zsh with vi keybindings
- Package managers: bun (preferred for JS), brew (system)
- Power user of Claude Code: hand-rolls dotfiles, hooks, statusline. Assume familiarity with the feature surface.

## Precedence

- These instructions are authoritative over auto-generated memory when the two conflict.

## Preferences

- Use bun over npm/yarn unless a project requires otherwise
- Use conventional commit style (feat:, fix:, chore:, etc.)
- **Secrets handling**: 1Password CLI (`op`) is the source of truth. NEVER propose adding a plaintext token to `.env`, `.npmrc`, or any config file. Default to an `op://` reference + the `op-run` wrapper, or `direnv` + `op read` in a per-project `.envrc` for fork-time inheritance. The only exception is keychain-backed CLIs (e.g., the `gh auth token` fallback handles GitHub) — document inline why the standard patterns don't apply. If you find an existing plaintext token in any repo, flag it before doing anything else: revoke first, then migrate.

## Git Workflow

- Default branch `main`; rebase, squash, linear history.
- Discouraged git flags (`--no-verify`, `--no-gpg-sign`, `git push --force` without `--force-with-lease`, force branch deletion): the `permissions.deny` list in `dot-claude/settings.json` is a best-effort backstop — it matches on prefix globs and is defeatable by wrappers (`git -c core.hooksPath=/dev/null …`, `sh -c …`), so treat it as discouragement, not a guarantee. The sandbox (filesystem `allowWrite`/`denyWrite` + network allowlists) is the enforced layer. NOTE the corrected model (see the Posture section): git/gh run *sandboxed first* (OS rules constrain them — `~/.gitconfig` is `denyWrite`, `github.com` must stay allow-listed), but with `allowUnsandboxedCommands:true` a sandbox-blocked git/gh is retried unsandboxed via the permission flow (this is what makes `git push` work). Per-prefix `permissions.deny` for git flags remains best-effort/wrapper-defeatable client-side discouragement; server-side (branch protection, CI gitleaks) + PreToolUse hooks remain the real backstop. Don't reach for these flags.
- NEVER delete the base branch of an open PR; this isn't hook-enforced. Run `gh pr list --base <branch>` first.
- For working-tree cleanup, prefer `git status` over `git clean -fd`; confirm before deleting tracked files.

## Sandbox & Permissions Posture (conscious choices)

- **Auto-approval surface**: `defaultMode:auto` + `autoAllowBashIfSandboxed:true` + `skipAutoPermissionPrompt:true` together mean sandboxed Bash runs without prompts (and would silently override any `ask: Bash(*)` rule). This is deliberate: the sandbox boundary (filesystem/network/socket rules), not per-command prompting, is the control for sandboxed commands.
- **Sandbox enforcement model** (verified 2026-06-07): commands run *sandboxed first* — `denyWrite`/`denyRead`/network rules are OS-enforced even for `excludedCommands` (a sandboxed `git init` under `$HOME` can't write `.git/hooks`/`.git/config` (platform default) or `~/.gitconfig` (our `denyWrite`); a sandboxed read of `~/.config/op` or any `.env` is blocked). With **`allowUnsandboxedCommands:true`** (set 2026-06-07 to enable git push — see below), a command that FAILS due to sandbox restrictions is then retried *unsandboxed* through the permission flow. So `excludedCommands` (git/gh/brew/…) effectively get unsandboxed execution **when the sandboxed attempt fails**, but normal sandboxed operations stay confined. Tradeoff: this re-enables the `dangerouslyDisableSandbox` escape; it is permission-flow-gated and kept as a deliberate fallback for tools that hit a sandbox wall. (It was originally added for git push; push now works purely sandboxed via keychain auth — see next bullet — but the retry remains useful as a general escape hatch.)
- **gh resolves its token from the keychain in-sandbox** (changed 2026-06-07): SSH still can't work in the sandbox (no raw TCP — the network allowlist only proxies HTTP/HTTPS; `ssh git@github.com` fails to even resolve), so GitHub auth must be HTTPS via a credential. The gh OAuth token is stored in the macOS **login keychain** (gh's default "secure storage"), NOT plaintext in `hosts.yml`. So `hosts.yml` is now sandbox-readable on purpose — it carries only non-secret host metadata (host, protocol, username; no `oauth_token`) that gh must load at startup for *every* command. The secret stays in the keychain, decrypted per-item by securityd (the calling binary's code signature must match the item ACL — `gh` does, even sandboxed). Two settings make this work in-sandbox: `~/.config/gh/hosts.yml` is removed from `denyRead`/`Read()`; and `~/Library/Keychains/login.keychain-db` is in `sandbox.filesystem.allowRead` so the legacy keychain search can find the item (the rest of `~/Library/Keychains` stays `denyRead`). Net: `gh auth status`, `gh auth token`, and `gh auth git-credential` (the github.com credential helper in `.gitconfig`) all succeed on the *first sandboxed attempt*, so HTTPS `git push` works in-sandbox without needing the `allowUnsandboxedCommands` retry. (The unsandboxed retry remains as a fallback. Requires a valid gh token in keychain storage — `gh auth status` should show `(keyring)`; refresh with `gh auth login` (default secure storage — do NOT use `--insecure-storage`, which writes the token plaintext into `hosts.yml`).)
  - **Security tradeoff (accepted 2026-06-07)**: allowing sandboxed read of `login.keychain-db` exposes the *encrypted* keychain blob to sandboxed code (offline-attack surface, mitigated by the login password). It does NOT hand out other apps' secrets — securityd still gates decryption by per-item ACL/code-signature, so a generic sandboxed `bash` can't decrypt items it didn't create. This is strictly better than the prior alternative (plaintext token in a readable file) and aligns with the keychain-backed-CLI exception in the secrets posture.
- **`denyWrite` is the OS-enforced anti-tamper control** (it applies to sandboxed Bash AND to sandboxed `excludedCommands` like git). It covers the credential/exec files a sandboxed/injected agent must never write: `~/.claude/.credentials.json`, `~/.claude.json`, `~/.gitconfig` + `~/.config/git/config` (GLOBAL git config — the real writable hooksPath/alias RCE target, since per-repo `.git/config`/`.git/hooks` are already platform-denied in the sandbox), `~/.cargo/credentials.toml` + `config.toml`, `~/.ssh` (private keys + `config` — swap-signing-key / host-redirect tamper; mirrored by `Edit(~/.ssh/**)` since the Edit tool bypasses the sandbox, and harmless to git commit signing, which reaches the agent via `allowUnixSockets` not a file write), and `/opt/homebrew/{bin,sbin}` (PATH-poisoning/privesc). Do NOT add git-tracked repo paths (e.g. `dot-claude/settings.json`, `hooks/`, `dot`) to `denyWrite` or to `Edit()` deny — it locks out maintenance AND breaks `git checkout`/`rebase`/`sync` on them (they run sandboxed); tampering there is git-visible instead. (Learned the hard way: an `Edit(//…/dot-claude/settings.json)` deny took effect live and made the file unmodifiable by every in-session path — Edit/Write/Bash/git — recoverable only from an external unsandboxed shell.)
- **Bypass mode stays available**: `skipDangerousModePermissionPrompt:true` is set and `disableBypassPermissionsMode` is intentionally NOT set — bypass mode is used deliberately on occasion, operator-initiated only. Accepted exposure: in bypass mode all prompts (including writes to `.git`, `.claude`, `.config/git`) are skipped.
- **The Read/Edit tools do not route through the sandbox** — that's what the `Read(...)`/`Edit(...)` mirrors in `permissions.deny` are for. Keep them in lockstep with `sandbox.filesystem.denyRead` when adding credential paths. Convention: a denyRead *directory* entry (`~/.aws`) needs the `/**` suffix on its `Read()` mirror (`Read(~/.aws/**)`); file entries stay byte-identical. `tests/bats/hardening.bats` asserts the mirror for the key paths.
- **GitHub auth is not exported** (changed 2026-06-07): `GITHUB_PERSONAL_ACCESS_TOKEN` is no longer exported in `.zprofile`. Exporting it leaked the PAT into every sandboxed Bash subprocess (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` only strips Anthropic/cloud creds). The `github` plugin MCP authenticates via the `gh` keychain directly; resolve on demand with `gh auth token` if a tool needs it.
- **Egress is the exfiltration surface**: `sandbox.network.allowedDomains` is the real exfil channel for sandboxed code, and the proxy filters on the client-supplied hostname without TLS inspection (domain-fronting is possible). The list is kept minimal (`github.com`/`api.github.com`/`codeload.github.com`/`*.githubusercontent.com` for git/clone/raw; package registries; dev hosts). Accepted residual risk; a TLS-terminating proxy (`httpProxyPort`) is the only hard control and is not currently warranted. `op-run` keeps masking ON (no `--no-masking`) so resolved secrets don't land in captured output.
- **Residual (accepted)**: a sandboxed agent could plant a per-repo `.git/config` hooksPath / `.git/hooks/` script ONLY if the platform's `.git` write-protection is ever relaxed; today it's platform-denied. A planted *per-repo* hook would also run sandboxed (contained); the cross-context risk (human later runs git unsandboxed in a tampered repo) is mitigated for the high-value GLOBAL config by the `~/.gitconfig` denyWrite above.

## Investigation Discipline

- For ambiguous tasks, ask a clarifying question after ~10 tool calls of exploration rather than spending 50+ calls investigating autonomously.
- "Do them all" / "finish phase X" / "address all open issues" are broad delegations: enter plan mode first, enumerate scope, then execute.

## Tool Preferences

- For multi-file or multi-step work, enter plan mode (`EnterPlanMode`) before touching code. Short, clearly-scoped tasks don't need it.
- For long-running or polling work, use `ScheduleWakeup` or the `loop` skill rather than re-running commands manually.
- For codebase research spanning more than ~3 file lookups, dispatch the `Explore` subagent.
- When dispatching an `Agent` that edits code, pass `isolation: "worktree"`.
- When dispatching an `Agent`, default to `model: "sonnet"`. Use `"haiku"` for pure lookups (file reads, greps, one-shot searches). Reserve the default (opus) for architecture, debugging, code review, or tasks that explicitly need heavy reasoning.
- Default to `/effort medium` for most prompts. Use `/effort high` for architecture, debugging, and review. Avoid `/effort max` — diminishing returns past high.
- For 2+ truly-independent investigation paths, prefer agent teams over sequential `Agent()` dispatches.
- For polling/maintenance work that should outlive a session, propose a routine via `/schedule` instead of leaving sessions open.
- For feature boundaries, prefer explicit `/compact` over autocompact firing mid-next-feature.

## Skill Usage

Prefer `implement:*` (CDD cycle) for code changes; `superpowers:*` as fallback. Whichever family drove the change, `superpowers:verification-before-completion` is the unconditional final gate — run it before claiming work done, every time.

Reference cheatsheets (slash commands, experimental env vars) live in `dot-claude/REFERENCE.md` — not auto-loaded.
