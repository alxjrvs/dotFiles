# SSH Convergence on `dot sync` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `dot sync` converges the full SSH approach — dedicated fixed-socket signing agent, signing key, per-machine signingkey, allowed_signers, sandbox settings — so signing works inside the Claude Code sandbox on every machine.

**Architecture:** New sync-sourced module `install/45-ssh.sh` owns all signing convergence (moved out of `40-symlinks.sh`); `.zprofile` keeps the agent alive across logins; `dot-claude/settings.json` allows the literal socket path (seatbelt `subpath` is literal — proven, see spec); `dot doctor` gains read-only checks incl. a dead-glob lint.

**Tech Stack:** bash, ssh-agent/ssh-keygen, git config, jq, bats.

**Spec:** `docs/superpowers/specs/2026-06-05-ssh-sync-convergence-design.md`

**Multi-machine invariant:** shared symlinked files reference only stable per-machine-resolvable paths (`~`/`$HOME`); machine-specific data only in generated untracked files (`~/.gitconfig.local`, `~/.ssh/*`).

---

### Task 0: Determine settings form — does `allowUnixSockets` expand `~`?

The fix needs a literal socket path in `dot-claude/settings.json`. Filesystem
entries demonstrably expand `~` (the `~/.ssh/id_*` deny works), but
`allowUnixSockets` may use a different path normalizer. Decide empirically.

**Files:** none (throwaway experiment in `$CLAUDE_JOB_DIR/tmp` or `$TMPDIR`).

- [ ] **Step 1: Ensure a signing agent is running at the fixed path** (manual bootstrap of what the module will later automate):

```bash
mkdir -p ~/.ssh/agent && chmod 700 ~/.ssh ~/.ssh/agent
SSH_AUTH_SOCK=~/.ssh/agent/signing.sock ssh-add -l >/dev/null 2>&1 || {
  rm -f ~/.ssh/agent/signing.sock
  (umask 077; ssh-agent -a ~/.ssh/agent/signing.sock >/dev/null)
}
ls -la ~/.ssh/agent/signing.sock
```

Expected: socket exists.

- [ ] **Step 2: Probe with the `~` form** in a headless strict session:

```bash
cat > "$TMPDIR/sock-test.json" <<'EOF'
{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":true,"excludedCommands":[],"network":{"allowUnixSockets":["~/.ssh/agent/signing.sock"]}}}
EOF
claude -p --model haiku --settings "$TMPDIR/sock-test.json" \
  'Run with Bash: SSH_AUTH_SOCK=$HOME/.ssh/agent/signing.sock ssh-add -l; report the exact output and exit code, nothing else.'
```

Expected: either a key listing / "The agent has no identities" (= `~` expands, **use `~` form**) or "Operation not permitted" (= try Step 3).

- [ ] **Step 3 (only if Step 2 denied): Probe the absolute form** — same command with `"/Users/jarvis/.ssh/agent/signing.sock"` in `allowUnixSockets`. If this works, **use the absolute form** (username is identical on both machines). If neither works, STOP — return to investigation before any settings edits.

- [ ] **Step 4: Record the winning form** — note it in the Task 4 step below before executing Task 4 (replace `<SOCK_FORM>`).

---

### Task 1: `install/45-ssh.sh` module + bats tests (TDD)

**Files:**
- Create: `tests/bats/ssh-module.bats`
- Create: `install/45-ssh.sh`

- [ ] **Step 1: Write the failing tests**

`tests/bats/ssh-module.bats`:

```bash
#!/usr/bin/env bats
# Unit tests for install/45-ssh.sh (sync-sourced SSH signing convergence).
# CRITICAL: every test runs with HOME inside a bats temp dir. The setup
# guard fails the suite outright if HOME ever resolves to the real home
# (lesson from the fixture leak that wrote user.name=t into the real repo).

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ORIG_HOME="$HOME"

setup() {
  TDIR="$(mktemp -d "${TMPDIR:-/tmp}/bats-ssh.XXXXXX")"
  export HOME="$TDIR"
  # Guard: never run against the real home.
  [ "$HOME" != "$ORIG_HOME" ] || exit 1
  export DOTFILES_DIR="$ROOT"
  export __DOT_SYNC_SOURCED=1
  # sync-exported helper the module relies on.
  host_id() { printf 'testhost\n'; }
  export -f host_id
  # shellcheck source=/dev/null
  source "$ROOT/install/45-ssh.sh"
}
teardown() { rm -rf "$TDIR"; }

# ── key generation ───────────────────────────────────────────────────────────

@test "ensure_key: generates ed25519 keypair when absent" {
  run _ssh_ensure_key
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ssh/id_ed25519" ]
  [ -f "$HOME/.ssh/id_ed25519.pub" ]
  run stat -f '%Lp' "$HOME/.ssh/id_ed25519"
  [ "$output" = "600" ]
}

@test "ensure_key: never overwrites an existing key" {
  mkdir -p "$HOME/.ssh"
  echo "sentinel" > "$HOME/.ssh/id_ed25519"
  echo "sentinel-pub" > "$HOME/.ssh/id_ed25519.pub"
  _ssh_ensure_key || true
  [ "$(head -1 "$HOME/.ssh/id_ed25519")" = "sentinel" ]
  [ "$(cat "$HOME/.ssh/id_ed25519.pub")" = "sentinel-pub" ]
}

@test "ensure_key: re-derives missing .pub from existing key" {
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
  rm "$HOME/.ssh/id_ed25519.pub"
  run _ssh_ensure_key
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ssh/id_ed25519.pub" ]
  grep -q '^ssh-ed25519 ' "$HOME/.ssh/id_ed25519.pub"
}

# ── gitconfig.local ──────────────────────────────────────────────────────────

@test "gitconfig_local: created with gpgSign + signingkey" {
  mkdir -p "$HOME/.ssh"
  printf 'ssh-ed25519 AAAATESTKEY comment\n' > "$HOME/.ssh/id_ed25519.pub"
  run _ssh_ensure_gitconfig_local
  [ "$status" -eq 0 ]
  [ "$(git config --file "$HOME/.gitconfig.local" commit.gpgSign)" = "true" ]
  [ "$(git config --file "$HOME/.gitconfig.local" tag.gpgSign)" = "true" ]
  [ "$(git config --file "$HOME/.gitconfig.local" user.signingkey)" = "key::ssh-ed25519 AAAATESTKEY comment" ]
}

@test "gitconfig_local: signingkey updated on mismatch, unrelated keys preserved" {
  mkdir -p "$HOME/.ssh"
  printf 'ssh-ed25519 AAAANEWKEY comment\n' > "$HOME/.ssh/id_ed25519.pub"
  git config --file "$HOME/.gitconfig.local" user.signingkey "key::ssh-ed25519 OLDKEY x"
  git config --file "$HOME/.gitconfig.local" maintenance.repo "/some/repo"
  run _ssh_ensure_gitconfig_local
  [ "$(git config --file "$HOME/.gitconfig.local" user.signingkey)" = "key::ssh-ed25519 AAAANEWKEY comment" ]
  [ "$(git config --file "$HOME/.gitconfig.local" maintenance.repo)" = "/some/repo" ]
}

# ── allowed_signers ──────────────────────────────────────────────────────────

@test "allowed_signers: line appended when absent, idempotent, preserves other machines" {
  mkdir -p "$HOME/.ssh"
  printf 'ssh-ed25519 AAAATESTKEY comment\n' > "$HOME/.ssh/id_ed25519.pub"
  printf 'user@example.com ssh-ed25519 OTHERMACHINEKEY pro\n' > "$HOME/.ssh/allowed_signers"
  _ssh_ensure_allowed_signers
  _ssh_ensure_allowed_signers   # idempotency: run twice
  run grep -c 'AAAATESTKEY' "$HOME/.ssh/allowed_signers"
  [ "$output" = "1" ]
  grep -q 'OTHERMACHINEKEY' "$HOME/.ssh/allowed_signers"
}

# ── agent convergence (PATH-shimmed; never touches a real agent) ─────────────

@test "ensure_agent: stale socket removed and agent restarted with -a fixed path" {
  mkdir -p "$HOME/.ssh/agent" "$TDIR/bin"
  ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
  touch "$HOME/.ssh/agent/signing.sock"   # stale non-socket file
  cat > "$TDIR/bin/ssh-add" <<'SHIM'
#!/bin/bash
echo "ssh-add $*" >> "$SHIM_LOG"; exit 2
SHIM
  cat > "$TDIR/bin/ssh-agent" <<'SHIM'
#!/bin/bash
echo "ssh-agent $*" >> "$SHIM_LOG"; exit 0
SHIM
  chmod +x "$TDIR/bin/ssh-add" "$TDIR/bin/ssh-agent"
  export SHIM_LOG="$TDIR/shim.log" PATH="$TDIR/bin:$PATH"
  run _ssh_ensure_agent
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.ssh/agent/signing.sock" ]   # stale file removed
  grep -q -- "-a $HOME/.ssh/agent/signing.sock" "$SHIM_LOG"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/bats/ssh-module.bats`
Expected: FAIL — `install/45-ssh.sh: No such file or directory` in setup.

- [ ] **Step 3: Write the module**

`install/45-ssh.sh`:

```bash
#!/usr/bin/env bash
# install/45-ssh.sh — SSH signing convergence.
# Tags: ssh
# Sourced by sync; not standalone — helpers (host_id) come from sync, which
# exports them before sourcing this module.
#
# Auth keys live in 1Password (ssh/config IdentityAgent). Signing uses a
# dedicated agent at a FIXED socket path because the Claude Code sandbox
# compiles allowUnixSockets entries to literal seatbelt subpath rules —
# globs never match, so Apple's per-boot-randomized launchd socket cannot
# be allowed. See docs/superpowers/specs/2026-06-05-ssh-sync-convergence-design.md.

_ssh_tags() { printf 'ssh\n'; }

_ssh_ensure_dirs() {
  mkdir -p "${HOME}/.ssh/agent"
  chmod 700 "${HOME}/.ssh" "${HOME}/.ssh/agent"
}

# Generate the signing-only keypair if absent; re-derive a missing .pub.
# Never overwrites or rotates an existing key.
_ssh_ensure_key() {
  local key="${HOME}/.ssh/id_ed25519"
  if ! command -v ssh-keygen > /dev/null 2>&1; then
    printf '\033[0;33m  \xe2\x86\x92 ssh-keygen not found — skipping signing key setup\033[0m\n'
    return 0
  fi
  if [[ ! -e "$key" ]]; then
    if ssh-keygen -q -t ed25519 -N "" -C "signing-only $(host_id)" -f "$key"; then
      printf '\033[0;33m  \xe2\x86\x92 generated signing key %s\033[0m\n' "$key"
    else
      printf '\033[0;33m  \xe2\x86\x92 ssh-keygen failed — skipping signing key setup\033[0m\n'
      return 0
    fi
  fi
  chmod 600 "$key" 2> /dev/null || true
  if [[ ! -e "${key}.pub" ]] && [[ -s "$key" ]]; then
    if ssh-keygen -y -f "$key" > "${key}.pub" 2> /dev/null; then
      chmod 644 "${key}.pub"
      printf '\033[0;33m  \xe2\x86\x92 re-derived %s.pub\033[0m\n' "$key"
    else
      rm -f "${key}.pub"
      printf '\033[0;33m  \xe2\x86\x92 could not derive pubkey from %s\033[0m\n' "$key"
    fi
  fi
}

# Dedicated signing agent at a fixed socket path; load the key if absent.
_ssh_ensure_agent() {
  local sock="${HOME}/.ssh/agent/signing.sock"
  local key="${HOME}/.ssh/id_ed25519"
  [[ -f "$key" ]] || return 0
  if ! SSH_AUTH_SOCK="$sock" ssh-add -l > /dev/null 2>&1; then
    rm -f "$sock"
    if ! (umask 077 && ssh-agent -a "$sock" > /dev/null 2>&1); then
      printf '\033[0;33m  \xe2\x86\x92 could not start signing agent at %s\033[0m\n' "$sock"
      return 0
    fi
  fi
  local fp
  fp=$(ssh-keygen -lf "${key}.pub" 2> /dev/null | awk '{print $2}')
  if [[ -n "$fp" ]] && ! SSH_AUTH_SOCK="$sock" ssh-add -l 2> /dev/null | grep -qF "$fp"; then
    SSH_AUTH_SOCK="$sock" ssh-add -q "$key" 2> /dev/null ||
      printf '\033[0;33m  \xe2\x86\x92 could not load signing key into agent\033[0m\n'
  fi
}

# ~/.gitconfig.local: gpgSign on, signingkey = this machine's literal pubkey.
_ssh_ensure_gitconfig_local() {
  local cfg="${HOME}/.gitconfig.local"
  local pub="${HOME}/.ssh/id_ed25519.pub"
  if [[ ! -e "$cfg" ]]; then
    printf '# Machine-local git overrides — NOT in dotfiles. Written by dot sync.\n' > "$cfg"
    printf '\033[0;33m  \xe2\x86\x92 .gitconfig.local bootstrapped\033[0m\n'
  fi
  git config --file "$cfg" commit.gpgSign true
  git config --file "$cfg" tag.gpgSign true
  [[ -f "$pub" ]] || return 0
  local want current
  want="key::$(cat "$pub")"
  current=$(git config --file "$cfg" user.signingkey 2> /dev/null || true)
  if [[ "$current" != "$want" ]]; then
    git config --file "$cfg" user.signingkey "$want"
    printf '\033[0;33m  \xe2\x86\x92 signingkey set to this machine'"'"'s pubkey\033[0m\n'
  fi
}

# allowed_signers: ensure "<email> <pubkey>" line; append-only so every
# machine's key coexists (cross-machine verification).
_ssh_ensure_allowed_signers() {
  local allowed="${HOME}/.ssh/allowed_signers"
  local pub="${HOME}/.ssh/id_ed25519.pub"
  [[ -f "$pub" ]] || return 0
  local email
  email=$(git config --file "${DOTFILES_DIR}/.gitconfig" user.email 2> /dev/null || true)
  if [[ -z "$email" ]]; then
    printf '\033[0;33m  \xe2\x86\x92 no user.email in repo .gitconfig — skipping allowed_signers\033[0m\n'
    return 0
  fi
  local line
  line="$email $(cat "$pub")"
  if [[ ! -e "$allowed" ]] || ! grep -qxF "$line" "$allowed"; then
    printf '%s\n' "$line" >> "$allowed"
    printf '\033[0;33m  \xe2\x86\x92 allowed_signers updated\033[0m\n'
  fi
  chmod 600 "$allowed"
}

_ssh_run() {
  printf '\n==> SSH signing\n'
  _ssh_ensure_dirs
  _ssh_ensure_key
  _ssh_ensure_agent
  _ssh_ensure_gitconfig_local
  _ssh_ensure_allowed_signers
  printf '\033[0;32m  \xe2\x9c\x93 SSH signing converged\033[0m\n'
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/bats/ssh-module.bats`
Expected: all 7 PASS.

- [ ] **Step 5: Lint**

Run: `shellcheck install/45-ssh.sh tests/bats/ssh-module.bats && shfmt -i 2 -ci -sr -d install/45-ssh.sh`
Expected: clean (shfmt does not parse .bats — only the module is formatted).

- [ ] **Step 6: Commit**

```bash
git add install/45-ssh.sh tests/bats/ssh-module.bats
git commit -m "feat(ssh): sync module for signing key, fixed-socket agent, gitconfig.local"
```

---

### Task 2: Remove the migrated bootstrap from `install/40-symlinks.sh`

**Files:**
- Modify: `install/40-symlinks.sh:37-65`

- [ ] **Step 1: Delete the two bootstrap blocks** — `# Bootstrap ~/.gitconfig.local if absent.` through the `.gitconfig.local already exists` else-branch, and `# Bootstrap ~/.ssh/allowed_signers if absent.` through its closing `fi` (the blocks shown at `install/40-symlinks.sh:37-65`; both now live in `45-ssh.sh`). Keep the git-template hook link and the `dead_hook` cleanup above them, and keep the `# ── SSH config ──` symlink section below.

- [ ] **Step 2: Verify nothing references the removed code**

Run: `grep -rn 'gitconfig.local\|allowed_signers' install/ sync doctor | grep -v 45-ssh`
Expected: no hits in `40-symlinks.sh` (doctor hits appear after Task 6 — at this point, none).

- [ ] **Step 3: Lint + module smoke**

Run: `shellcheck install/40-symlinks.sh && ./sync --only=symlinks 2>&1 | tail -5`
Expected: clean lint; sync section completes with no gitconfig.local output.

- [ ] **Step 4: Commit**

```bash
git add install/40-symlinks.sh
git commit -m "refactor(sync): move signing bootstrap from 40-symlinks to 45-ssh"
```

---

### Task 3: `.zprofile` — fixed-socket agent block

**Files:**
- Modify: `.zprofile` (the `ssh-add` block at the bottom)

- [ ] **Step 1: Replace the Apple-agent block.** Current block (last comment + line of `.zprofile`):

```sh
# Git signing key → Apple ssh-agent (silent signing, no per-commit prompts).
# .gitconfig user.signingkey is the literal pubkey, so git signs via the
# agent (-U) and never reads the private key file — the Claude sandbox only
# allows the agent socket, not the key. Auth keys still live in 1Password
# (ssh/config IdentityAgent); this on-disk key exists for signing only.
# Login shell only; skips the fork when the agent already has identities.
ssh-add -l > /dev/null 2>&1 || ssh-add -q ~/.ssh/id_ed25519 2> /dev/null
```

New block:

```sh
# Git signing → dedicated ssh-agent at a FIXED socket path (silent signing,
# no per-commit prompts). Fixed path because the Claude sandbox compiles
# allowUnixSockets to literal seatbelt subpath rules — Apple's launchd agent
# socket is per-boot random and can never be allowed. git signs via the
# agent (-U) and never reads the key file (sandbox denies ~/.ssh/id_*).
# Auth keys still live in 1Password (ssh/config IdentityAgent ignores
# SSH_AUTH_SOCK). dot sync (install/45-ssh.sh) provisions key + agent.
export SSH_AUTH_SOCK="$HOME/.ssh/agent/signing.sock"
ssh-add -l > /dev/null 2>&1 || {
  rm -f "$SSH_AUTH_SOCK"
  (umask 077 && ssh-agent -a "$SSH_AUTH_SOCK" > /dev/null 2>&1)
  ssh-add -q ~/.ssh/id_ed25519 2> /dev/null
}
```

- [ ] **Step 2: Verify in a fresh login shell**

Run: `zsh -lc 'echo $SSH_AUTH_SOCK; ssh-add -l'`
Expected: `/Users/jarvis/.ssh/agent/signing.sock` + one ED25519 key listed.

- [ ] **Step 3: Verify signing still works end-to-end (unsandboxed)**

```bash
cd "$(mktemp -d)" && git init -q . && git commit --allow-empty -m sig-test \
  && git log --show-signature -1 2>&1 | grep -E 'Good "git" signature'
```

Expected: `Good "git" signature` line. (Requires Task 5's signingkey migration if the old hardcoded key differs — if this fails with a key mismatch, finish Task 5 first, run `dot sync --only=ssh`, and retry.)

- [ ] **Step 4: Commit**

```bash
git add .zprofile
git commit -m "feat(ssh): point SSH_AUTH_SOCK at fixed-path signing agent"
```

---

### Task 4: `dot-claude/settings.json` — literal socket allowance

**Files:**
- Modify: `dot-claude/settings.json` (`sandbox.network.allowUnixSockets`)

- [ ] **Step 1: Replace the dead glob entries.** Remove
`"/var/run/com.apple.launchd.*/Listeners"` and
`"/private/var/run/com.apple.launchd.*/Listeners"`; add the Task 0 winning
form `<SOCK_FORM>` (either `"~/.ssh/agent/signing.sock"` or
`"/Users/jarvis/.ssh/agent/signing.sock"`). Keep the `tsx` entries: they are
glob-dead too, but removing them is out of scope here — the doctor lint
(Task 6) will flag them for a follow-up.

- [ ] **Step 2: Validate JSON**

Run: `jq '.sandbox.network.allowUnixSockets' dot-claude/settings.json`
Expected: array with the new literal entry, no launchd globs.

- [ ] **Step 3: Commit**

```bash
git add dot-claude/settings.json
git commit -m "fix(claude): allow signing-agent socket literally; drop dead launchd globs"
```

---

### Task 5: Shared `.gitconfig` — drop hardcoded signingkey

**Files:**
- Modify: `.gitconfig:26-29`

- [ ] **Step 1: Replace the signingkey lines.** Current (`.gitconfig:26-29`):

```ini
	# Literal pubkey (not a file path) → git signs via ssh-agent (-U), so the
	# private key file is never read at commit time. The agent is loaded at
	# login by .zprofile; the sandbox only needs the agent socket allowed.
	signingkey = key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPKPdTHi3qsWUMivyLIXbsQ22P8F1/gMGPHuLgFUoDP jarvis@Alexs-MacBook-Air.local
```

New (comment only — the key itself is machine-local):

```ini
	# user.signingkey is machine-local (~/.gitconfig.local, written by
	# `dot sync` → install/45-ssh.sh) — a literal `key::` pubkey, so git signs
	# via the fixed-socket signing agent and never reads the private key file.
```

- [ ] **Step 2: Run sync + verify the effective key resolves**

Run: `./sync --only=ssh && git config user.signingkey`
Expected: `key::ssh-ed25519 …` matching `cat ~/.ssh/id_ed25519.pub`.

- [ ] **Step 3: Verify a signed commit still verifies** (same probe as Task 3 Step 3). Expected: `Good "git" signature`.

- [ ] **Step 4: Commit**

```bash
git add .gitconfig
git commit -m "refactor(git): signingkey is machine-local, written by dot sync"
```

---

### Task 6: `dot doctor` — SSH signing checks + dead-glob lint

**Files:**
- Modify: `doctor` (append a new section before the final summary block)

- [ ] **Step 1: Add the section** (uses existing `_ok`/`_warn` helpers; all
checks warn-only so pre-push `dot doctor` cannot start failing on
environmental drift):

```bash
# ── SSH signing chain ─────────────────────────────────────────────────────────
printf '\n==> SSH signing\n'

_op_sock="${HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
if [[ -S "$_op_sock" ]]; then
  _ok "1Password agent socket present (auth)"
else
  _warn "1Password agent socket missing — enable Settings → Developer → SSH agent"
fi

_sign_sock="${HOME}/.ssh/agent/signing.sock"
_sign_key="${HOME}/.ssh/id_ed25519"
if [[ -S "$_sign_sock" ]] && SSH_AUTH_SOCK="$_sign_sock" ssh-add -l > /dev/null 2>&1; then
  _sign_fp=$(ssh-keygen -lf "${_sign_key}.pub" 2> /dev/null | awk '{print $2}')
  if [[ -n "$_sign_fp" ]] && SSH_AUTH_SOCK="$_sign_sock" ssh-add -l 2> /dev/null | grep -qF "$_sign_fp"; then
    _ok "signing agent up with key loaded"
  else
    _warn "signing agent up but signing key not loaded — run: dot sync --only=ssh"
  fi
else
  _warn "signing agent unreachable at ~/.ssh/agent/signing.sock — run: dot sync --only=ssh"
fi

_eff_key=$(git config user.signingkey 2> /dev/null || true)
_pub_line=$(cat "${_sign_key}.pub" 2> /dev/null || true)
if [[ -n "$_pub_line" && "$_eff_key" == "key::${_pub_line}" ]]; then
  _ok "user.signingkey matches this machine's pubkey"
else
  _warn "user.signingkey does not match ~/.ssh/id_ed25519.pub — run: dot sync --only=ssh"
fi
if [[ -n "$_pub_line" ]] && grep -qF "$_pub_line" "${HOME}/.ssh/allowed_signers" 2> /dev/null; then
  _ok "pubkey present in allowed_signers"
else
  _warn "pubkey missing from ~/.ssh/allowed_signers — run: dot sync --only=ssh"
fi

# Dead-rule lint: seatbelt subpath matching is LITERAL — a glob in
# allowUnixSockets never matches anything (root cause of the 2026-06-05
# sandboxed-signing failure; regression guard).
if [[ -n "$_dotfiles" ]] && command -v jq > /dev/null 2>&1; then
  if jq -r '.sandbox.network.allowUnixSockets[]?' "${_dotfiles}/dot-claude/settings.json" 2> /dev/null | grep -q '\*'; then
    _warn "allowUnixSockets contains a glob — seatbelt subpath is literal; that rule is dead"
  else
    _ok "allowUnixSockets entries are literal"
  fi
fi

if [[ -e "${HOME}/.augment/ssh-config" ]]; then
  _ok "~/.augment/ssh-config include target present"
else
  _warn "~/.augment/ssh-config missing (ssh/config Include target; externally managed)"
fi
```

Note: `_dotfiles` already exists in `doctor` (`doctor:132`); place the section after it is set. Adjust the variable name if the surrounding code uses a different one at the insertion point.

- [ ] **Step 2: Run doctor**

Run: `./doctor; echo "exit=$?"`
Expected: new `==> SSH signing` section; `allowUnixSockets contains a glob` warning fires until Task 4 lands (or `entries are literal` after); exit code unchanged by the new warn-only checks.

- [ ] **Step 3: Lint + commit**

```bash
shellcheck doctor && shfmt -i 2 -ci -sr -d doctor
git add doctor
git commit -m "feat(doctor): SSH signing chain checks + allowUnixSockets dead-glob lint"
```

---

### Task 7: Docs — CLAUDE.md module list + gotcha

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the module list** in "sync / install modules": `… 40-symlinks 45-ssh 50-ghostty …`.

- [ ] **Step 2: Add a gotcha bullet** under "Important Gotchas":

```markdown
- **Sandbox `allowUnixSockets` is literal**: Claude Code compiles entries to
  seatbelt `subpath` rules — globs are matched as literal characters, never
  expanded. Any socket the sandbox must reach needs a stable literal path
  (this is why git signing uses a dedicated agent at
  `~/.ssh/agent/signing.sock`, not Apple's per-boot-random launchd socket).
  `dot doctor` lints for dead glob entries.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: 45-ssh module + literal allowUnixSockets gotcha"
```

---

### Task 8: Full verification

- [ ] **Step 1: Full converge + suites**

Run: `dot sync 2>&1 | tail -20 && bats tests/bats/ && ./doctor; echo "exit=$?"`
Expected: sync clean; all bats pass; doctor exit 0 with SSH section all-green (1Password + augment may warn on a box where they're absent).

- [ ] **Step 2: Strict-sandbox end-to-end probe.** Re-run the 5-check session (spec §8) with an override that mirrors the NEW settings:

```bash
cat > "$TMPDIR/strict-v2.json" <<EOF
{"sandbox":{"enabled":true,"failIfUnavailable":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":true,"excludedCommands":[],"network":{"allowUnixSockets":["<SOCK_FORM>"]}}}
EOF
claude -p --model sonnet --settings "$TMPDIR/strict-v2.json" \
  'Sandbox test, report CHECK n: PASS/FAIL one line each.
CHECK 1: cat ~/.ssh/id_ed25519 — expect blocked.
CHECK 3: SSH_AUTH_SOCK=$HOME/.ssh/agent/signing.sock ssh-add -l — expect key listed.
CHECK 4: mkdir -p repo && cd repo && git init -q && git commit --allow-empty -m t && git log --show-signature -1 | head -5 — expect Good "git" signature.
CHECK 5: ls ~/Library/"Group Containers"/2BUA8C4S2C.com.1password/ — expect blocked.'
```

Expected: CHECK 1/5 blocked (still PASS), CHECK 3/4 now PASS. **This is the acceptance gate for the whole feature.**

- [ ] **Step 3: Run `superpowers:verification-before-completion`** before claiming done.

---

### Task 9: Upstream issue (draft → user approves → post)

- [ ] **Step 1: Draft** `$TMPDIR/cc-issue.md`: title "sandbox: allowUnixSockets glob patterns compile to dead literal subpath rules"; body: settings example, expected (glob matches launchd socket) vs actual (EPERM; seatbelt `subpath` is literal), repro = the literal `/private/tmp/tsx-*/*.pipe` connect experiment, CC version 2.1.165, suggestion: expand globs at profile-build time or reject+warn on glob-looking entries.

- [ ] **Step 2: Show the draft to the user and get explicit approval** (outward-facing action).

- [ ] **Step 3: Post upon approval**: `gh issue create -R anthropics/claude-code --title ... --body-file ...`.

---

### Multi-machine rollout (after merge)

On the M2 Pro: `git pull && dot sync` → generates that machine's key, starts
its agent, writes its `~/.gitconfig.local`, appends its pubkey to its
`allowed_signers`. To verify the Air's commits there, the Air's pubkey line
must also be added to the Pro's `~/.ssh/allowed_signers` (manual one-liner,
or just accept per-machine verification — signatures are still valid on
GitHub either way once each key is uploaded as a signing key).
