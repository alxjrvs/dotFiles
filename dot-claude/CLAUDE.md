# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`); vim input everywhere (shell is zsh with vi keybindings, Claude Code runs `editorMode: vim`)
- Package managers: bun (preferred for JS), brew (system)
- Power user of Claude Code: hand-rolls dotfiles, hooks, statusline. Assume familiarity with the feature surface.

## Precedence

- These instructions are authoritative over auto-generated memory when the two conflict.

## Workflow

- Use bun over npm/yarn unless a project requires otherwise.
- Conventional commit style (feat:, fix:, chore:, …).
- Feature work happens in worktrees branched fresh from `origin/main` (`worktree.baseRef: fresh`). Prefer worktree isolation for any agent that edits code.
- `superpowers:verification-before-completion` is the unconditional final gate before claiming work done.

## Git & GitHub

- Default branch `main`; rebase, squash, linear history.
- Remotes are HTTPS; GitHub auth is the gh keychain credential (`gh auth status` should show `(keyring)` — never `gh auth login --insecure-storage`, which writes the token plaintext to `hosts.yml`). `git push` and `gh` work fully sandboxed — never claim they need the sandbox disabled.
- Never `git push --force` (use `--force-with-lease`), `--no-verify`, or `--no-gpg-sign`. These are deny-listed; the deny is policy, not an obstacle to route around with wrappers.
- NEVER delete the base branch of an open PR; run `gh pr list --base <branch>` first.
- For working-tree cleanup, prefer `git status` over `git clean -fd`; confirm before deleting tracked files.

## Sandbox contract

- Every Bash command runs sandboxed (OS-enforced filesystem + network rules), including `excludedCommands` like git/gh — exclusion only routes them through the permission flow, it does not unsandbox them.
- `allowUnsandboxedCommands` is `false` and stays false: a sandbox-blocked command hard-fails; the `dangerouslyDisableSandbox` retry is ignored. Do not propose flipping it for routine git/gh/build operations — they work sandboxed. The hatch is operator-only: flipped briefly for a named tool, then closed.
- When a command fails under the sandbox, diagnose the missing resource (denyRead path? unix socket? network domain?) and propose the narrowest targeted allow — in the project's `.claude/settings.json` where possible, since permission and sandbox arrays merge across scopes and the global file stays strict.
- SSH/raw TCP has no path through the sandbox proxy (it dies at DNS); HTTPS is the answer, not exclusion.
- The Read/Edit tools bypass the sandbox: every `sandbox.filesystem.denyRead`/`denyWrite` credential path keeps a `Read(...)`/`Edit(...)` mirror in `permissions.deny` (directory entries take `/**` on the mirror; file entries stay byte-identical). Keep them in lockstep — `tests/bats/hardening.bats` asserts the key pairs.
- Never deny-rule a git-tracked dotfiles file (`dot-claude/settings.json`, `hooks/*`, `dot`): sandboxed git can't check out a denyWrite path, and an `Edit()` deny on the live `~/.claude/settings.json` self-locks the file against every in-session edit path. Tampering with tracked files is git-visible instead.

## Secrets

- 1Password CLI (`op`) is the source of truth. NEVER propose a plaintext token in `.env`, `.npmrc`, or any config file: use an `op://` reference + the `op-run` wrapper, or `direnv` + `op read` in a per-project `.envrc`. The only exception is keychain-backed CLIs (gh) — document inline why the standard patterns don't apply.
- If you find an existing plaintext token anywhere: flag it before doing anything else, revoke first, then migrate.

Reference cheatsheets (slash commands, experimental env vars) live in `dot-claude/REFERENCE.md` — not auto-loaded.
