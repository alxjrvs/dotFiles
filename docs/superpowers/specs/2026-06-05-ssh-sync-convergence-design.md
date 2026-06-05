# SSH convergence on `dot sync` — design (v2)

**Date:** 2026-06-05
**Status:** Approved (brainstormed with alxjrvs; v2 supersedes v1 after
root-cause investigation of sandboxed agent access)

## Goal

`dot sync` converges the repo's full SSH approach on any machine (M3 Air,
M2 Pro, future boxes), so a fresh box ends up with working SSH auth *and*
git commit signing that works **inside the Claude Code sandbox** — no
manual steps, no per-commit prompts.

## The SSH approach

Hybrid, split by role:

- **Auth** (ssh to github/servers): **1Password SSH agent**. Keys live in
  1Password, touch-to-confirm per use (`IdentityAgent` in `ssh/config`).
  Sync never touches the vault.
- **Git signing**: **dedicated signing-only ssh-agent at a fixed socket
  path** (`~/.ssh/agent/signing.sock`) holding a passphrase-less,
  on-disk, signing-only ed25519 key (`~/.ssh/id_ed25519`). Git signs via
  the agent (`gpg.format=ssh`, literal `key::` pubkey) and never reads the
  private key file. Zero prompts per commit.

### Why a dedicated agent (root-cause finding)

Claude Code's sandbox compiles each `sandbox.network.allowUnixSockets`
entry to a seatbelt `(allow network-outbound (remote unix-socket (subpath
"<literal>")))` rule. **`subpath` is a literal prefix match — globs are
not interpreted and fail silently.** Proven 2026-06-05 by: (1) decompiling
the profile generator in the CC 2.1.165 binary, (2) EPERM connecting to
every glob-intended path, (3) successful connect to a socket at the
*literal* path `/private/tmp/tsx-*/*.pipe`.

Apple's default launchd agent socket (`/var/run/com.apple.launchd.<random>/
Listeners`) has a per-boot random component, so **no static literal can
ever allow it**. The existing glob entries in `dot-claude/settings.json`
are dead weight; signing previously worked only because `git` is in
`sandbox.excludedCommands` (i.e., unsandboxed). A dedicated agent at a
fixed path makes the literal-subpath semantics work *for* us.

Upstream: file an issue against Claude Code — `allowUnixSockets` silently
ignoring glob patterns (entries that look like patterns compile to dead
literals with no warning).

### Trust model (stated explicitly, decided knowingly)

A signature from this key attests "made on this machine by something with
agent access," not "human reviewed." Any agent-socket-capable process —
including sandboxed Claude Code — signs silently. The control point for
unattended commits is the Claude permission layer and PR review, not the
signature. The private key file is sandbox-denied (`~/.ssh/id_*`); the
agent socket is the only signing path, and it can only sign — auth keys
stay behind 1Password's touch gate.

## Decisions made

1. **Scope: full convergence** — agent provisioning, key generation,
   per-machine signingkey, allowed_signers, sandbox settings, doctor.
2. **Generated key is passphrase-less** — signing-only role; file perms +
   sandbox deny-read are the at-rest boundary.
3. **`user.signingkey` lives in `~/.gitconfig.local`** — machine-specific;
   the hardcoded M3 Air pubkey leaves the shared `.gitconfig`.
4. **Dedicated signing agent at `~/.ssh/agent/signing.sock`** (v2) —
   replaces reliance on Apple's randomized launchd agent socket.
5. **Multi-machine invariant**: every changed file stays machine-agnostic.
   Shared, symlinked files (`.zprofile`, `dot-claude/settings.json`,
   `ssh/config`, `.gitconfig`) may reference only stable per-machine paths
   (`~/...`); all machine-specific data (keys, signingkey) lives in
   generated, untracked files (`~/.gitconfig.local`, `~/.ssh/*`).

## Changes

### 1. New module `install/45-ssh.sh` (tag: `ssh`)

Sourced by sync (not standalone). Idempotent steps:

1. **Dirs/perms**: `~/.ssh` 700; `~/.ssh/agent` 700.
2. **Generate signing key if absent**: `ssh-keygen -t ed25519 -N "" -C
   "signing-only $(host_id)"` → `~/.ssh/id_ed25519`, 600/644. Never
   overwrite or rotate. If the `.pub` is missing but the key exists,
   derive it with `ssh-keygen -y`.
3. **Signing agent up**: if `SSH_AUTH_SOCK=~/.ssh/agent/signing.sock
   ssh-add -l` fails, remove a stale socket and start
   `ssh-agent -a ~/.ssh/agent/signing.sock`; then `ssh-add` the signing
   key if its fingerprint is absent. (Same logic as the `.zprofile`
   block — sync makes signing work *now*, zprofile keeps it working at
   every login.)
4. **`~/.gitconfig.local`** (created if absent; `git config --file` for
   all reads/writes):
   - `commit.gpgSign=true` / `tag.gpgSign=true` (moves here from
     `40-symlinks.sh`).
   - `user.signingkey = key::<contents of id_ed25519.pub>` — written when
     absent, updated when it mismatches the local pubkey.
   - `gpg.ssh.program` left default; no machine-specific paths needed.
5. **`~/.ssh/allowed_signers`**: ensure line `<email> <pubkey>` present
   (email from `git config --file "$DOTFILES_DIR/.gitconfig" user.email`).
   **Append, never overwrite** — both machines' keys coexist so
   cross-machine verification works. chmod 600.

Error handling: missing `ssh-keygen`, underivable email, agent-start
failure → yellow warning + skip; never abort sync. Non-interactive safe.

### 2. `.zprofile` — replace the `ssh-add` line

The current `ssh-add -q ~/.ssh/id_ed25519` block (Apple launchd agent) is
**replaced** with the fixed-socket block:

```sh
export SSH_AUTH_SOCK="$HOME/.ssh/agent/signing.sock"
ssh-add -l > /dev/null 2>&1 || {
  rm -f "$SSH_AUTH_SOCK"
  (umask 077; ssh-agent -a "$SSH_AUTH_SOCK" > /dev/null 2>&1)
  ssh-add -q ~/.ssh/id_ed25519 2> /dev/null
}
```

Pointing `SSH_AUTH_SOCK` at the signing agent is safe for auth: 1Password
auth goes through `IdentityAgent` in `ssh/config`, which ignores
`SSH_AUTH_SOCK`.

### 3. `dot-claude/settings.json` (shared, symlinked — machine-agnostic)

- **Remove** the two dead glob entries
  (`/var/run/com.apple.launchd.*/Listeners`, `/private/var/run/...`).
- **Add** the literal socket path to `sandbox.network.allowUnixSockets`.
  Implementation must first verify whether `~` is expanded for
  `allowUnixSockets` the way it is for `filesystem` entries (test in a
  throwaway `--settings` session); use `~/.ssh/agent/signing.sock` if so,
  else the `/Users/jarvis/...` absolute form (identical username on both
  machines).
- `git` **stays** in `excludedCommands` for now; removing it is a
  follow-up experiment once sandboxed signing is proven in daily use.

### 4. Shared `.gitconfig`

Delete the hardcoded `signingkey = key::ssh-ed25519 …` line; update the
adjacent comment: signingkey is machine-local (`~/.gitconfig.local`,
written by `dot sync`), and the signing agent is the dedicated
fixed-socket agent, not Apple's launchd agent.

### 5. `install/40-symlinks.sh`

The git-signing bootstrap block (gitconfig.local + allowed_signers) is
removed — it moves to `45-ssh.sh`. The `ssh/config` symlink + perms stay.

### 6. `dot doctor` additions (read-only)

- **1Password agent socket** exists (auth side) — warn if missing.
- **Signing agent**: `~/.ssh/agent/signing.sock` exists AND
  `SSH_AUTH_SOCK=<sock> ssh-add -l` lists the signing key's fingerprint —
  warn "run dot sync / re-login" otherwise.
- **Signing chain**: effective `git config user.signingkey` matches the
  local pubkey; pubkey present in `~/.ssh/allowed_signers`.
- **Sandbox parity**: warn if `dot-claude/settings.json` still contains a
  glob (`*`) inside `allowUnixSockets` (dead-rule lint, this finding's
  regression guard).
- **`~/.augment/ssh-config`** include target exists — warn-only.

### 7. Tests (`tests/bats/`)

- allowed_signers: appended when absent; not duplicated; other machines'
  lines preserved.
- gitconfig.local: created with signingkey + gpgSign; signingkey updated
  on mismatch; unrelated keys preserved.
- key generation skipped when key exists; `.pub` re-derived when missing.
- agent block: stale-socket cleanup + reuse logic (mock `ssh-agent`/
  `ssh-add` with PATH shims).
- All tests run with `HOME` in a bats temp dir and **fail fast if `HOME`
  resolves to the real home** (lesson from the `user.name=t` fixture
  leak).

### 8. End-to-end verification (manual, after implementation)

Strict-sandbox headless session (`allowUnsandboxedCommands:false`,
`failIfUnavailable:true`, `excludedCommands:[]`, plus the new
allowUnixSockets entry) re-runs the 5-check probe from 2026-06-05; CHECK 3
(agent reachable) and CHECK 4 (signed commit, `Good "git" signature`)
must flip to PASS; CHECKs 1/2/5 (key unreadable, no escape, vault sealed)
must stay PASS.

## Out of scope

- Removing `git` from `sandbox.excludedCommands` (follow-up experiment).
- Distinguishing Claude's commits from human commits — discussed,
  deferred.
- 1Password vault management, key rotation, Linux socket paths
  (darwin-guarded via `os_kind`).
- The upstream Claude Code issue text is a deliverable of implementation,
  but its acceptance is not a gate for this design.
