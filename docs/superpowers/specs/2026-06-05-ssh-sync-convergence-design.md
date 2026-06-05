# SSH convergence on `dot sync` — design

**Date:** 2026-06-05
**Status:** Approved (brainstormed with alxjrvs)

## Goal

`dot sync` converges the repo's full SSH approach on any machine, so a fresh
box (or a drifted one) ends up with working SSH auth *and* silent git commit
signing without manual steps.

## The SSH approach (unchanged — this spec automates it)

Hybrid, split by role:

- **Auth** (ssh to github/servers): **1Password SSH agent**. Keys live in
  1Password, touch-to-confirm per use (`IdentityAgent` in `ssh/config`).
  Sync never touches the vault.
- **Git signing**: **Apple ssh-agent** with a dedicated on-disk,
  passphrase-less, signing-only ed25519 key (`~/.ssh/id_ed25519`). Loaded at
  login by `.zprofile`; git signs via the agent (`gpg.format=ssh`, literal
  `key::` pubkey as signingkey) and never reads the private key file. Zero
  prompts per commit.

Trust model (stated explicitly, decided knowingly): a signature from this key
attests "made on this machine by something with agent access," not "human
reviewed." Any agent-socket-capable process — including Claude Code — signs
silently. The control point for unattended commits is the Claude permission
layer and PR review, not the signature. The private key file is
sandbox-denied (`~/.ssh/id_*`); the agent socket is the only signing path.

## Decisions made

1. **Scope: full convergence** — key generation, agent load, per-machine
   signingkey, allowed_signers, doctor checks.
2. **Generated key is passphrase-less** — matches the silent
   `ssh-add -q` login load and the key's signing-only role.
3. **`user.signingkey` moves to `~/.gitconfig.local`** — it is
   machine-specific data; the hardcoded M3 Air pubkey leaves the shared
   `.gitconfig`.

## Changes

### 1. New module `install/45-ssh.sh` (tag: `ssh`)

Sourced by sync (not standalone), helpers from sync. Idempotent steps:

1. **Perms**: ensure `~/.ssh` exists and is 700.
2. **Generate signing key if absent**: when `~/.ssh/id_ed25519` does not
   exist, `ssh-keygen -t ed25519 -N "" -C "signing-only $(host_id)"`;
   chmod 600 key / 644 pub. Never overwrite or rotate an existing key.
   If `~/.ssh/id_ed25519` exists but `id_ed25519.pub` is missing, derive it
   with `ssh-keygen -y` rather than regenerating.
3. **Agent load**: if the key's fingerprint is not in `ssh-add -l`, run
   `ssh-add -q ~/.ssh/id_ed25519` (so signing works immediately, not just
   after next login). Failure is a warning, not an abort.
4. **`~/.gitconfig.local`** (creates the file if absent):
   - `commit.gpgSign=true` / `tag.gpgSign=true` (bootstrap moves here from
     `40-symlinks.sh`).
   - `user.signingkey = key::<contents of id_ed25519.pub>` — written when
     absent, **updated when it mismatches the local pubkey** (use
     `git config --file` for both read and write; never regex the file).
5. **`~/.ssh/allowed_signers`**: ensure the line `<email> <pubkey>` is
   present, where email comes from
   `git config --file "$DOTFILES_DIR/.gitconfig" user.email`.
   **Append, never overwrite** — both machines' keys must coexist so
   cross-machine signature verification works. chmod 600. (Bootstrap moves
   here from `40-symlinks.sh`.)

Error handling: missing `ssh-keygen`, underivable email, or agent failure →
yellow warning + skip that step; never abort sync. Non-interactive safe.

### 2. `install/40-symlinks.sh`

The git-signing bootstrap block (gitconfig.local + allowed_signers) is
**removed** — it moves to `45-ssh.sh`. The `ssh/config` symlink + perms stay
in 40 (it is a symlink concern). The `ssh` tag remains on both modules.

### 3. Shared `.gitconfig`

Delete the hardcoded `signingkey = key::ssh-ed25519 …` line; update the
adjacent comment to say signingkey is machine-local (`~/.gitconfig.local`,
written by `dot sync`).

### 4. `dot doctor` additions (read-only)

- **1Password agent socket** exists at
  `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock` —
  warn if missing (auth side degraded).
- **Signing key**: `~/.ssh/id_ed25519` exists with 600 perms; its
  fingerprint appears in `ssh-add -l` (warn "run dot sync / re-login" if
  not loaded).
- **Signing chain**: effective `git config user.signingkey` matches the
  local pubkey, and that pubkey appears in `~/.ssh/allowed_signers`.
- **`~/.augment/ssh-config`** (the `Include` target in `ssh/config`)
  exists — warn-only, externally managed.

Doctor stays read-only; all new checks are warnings except missing
`~/.ssh/config` symlink (already covered by the symlink integrity check).

### 5. Tests (`tests/bats/`)

Bats tests for the module's convergence helpers:

- allowed_signers: line appended when absent, not duplicated when present,
  other machines' lines preserved.
- gitconfig.local: created with signingkey + gpgSign; signingkey updated on
  mismatch; unrelated keys (e.g. `maintenance.repo`) preserved.
- key generation skipped when key exists.

All tests run with `HOME` pointed at a bats temp dir and **assert the guard**
(fail fast if `HOME` resolves to the real home) — the suite must never be
able to touch the real `~/.ssh` or `~/.gitconfig.local` (lesson from the
fixture leak that set `user.name=t` in the real repo).

## Out of scope

- Distinguishing Claude's commits from human commits (separate key /
  conditional signing) — explicitly discussed and deferred.
- 1Password vault management, key rotation, Linux 1Password socket paths
  (module steps that are darwin-specific are guarded by `os_kind`).
- `.zprofile` changes — the login-time `ssh-add` line is already correct.
