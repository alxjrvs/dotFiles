# Claude's op calls read as the agent service account and write as the owner

- Status: accepted
- Date: 2026-11-17

## Context and Problem Statement

Which 1Password identity an agent's `op` call signs in as has changed six times:

- A service account, then an `op-sa` shim replacing `op-agent` (#304).
- "One credential path" (#361), then "one store" (#367).
- Every call as the agent service account, through a shim first on Claude's PATH (#562). The
  desktop app approves one shell at a time and Claude starts a shell per command, so signing in
  as the owner asked for biometrics on nearly every call.
- The same day, writes back to the owner (#563): the service account is read-only, so every write
  failed where it used to prompt.

Each flip fixed the last one's symptom. None wrote down which identity does what, so the next
change had nothing to hold to.

## Decision Drivers

- An agent never sees a secret value.
- No biometric prompt for routine reads.
- A write to the account is the owner's, with the owner's approval.
- A failure says what failed.

## Considered Options

1. The owner for everything, through the desktop app.
2. The service account for everything.
3. The service account by default, the owner only where the service account cannot serve.

## Decision Outcome

Option 3, as `~/.claude/bin/op` implements it. In Claude's shells, on a machine with the
`claude-agent` Environment mounted:

| Call | Signs in as |
|---|---|
| `op run`, `op inject` and anything not listed below | The service account, once. Never retried. |
| Metadata reads: `item get`, `item list`, `vault get`, `vault list`, `document list` | The service account. Retried as the owner only when the service account answers that it cannot see the vault or item. |
| Writes and admin: `item`/`document` create, edit, delete, move, share; `vault` create, edit, delete, user, group; `user`, `group`, `connect`, `service-account`, `events-api`, `account`, `signin`, `signout` | The owner, with a biometric prompt |
| Any call with `--account` | The owner |
| `op read` | Nobody: `Bash(op read*)` is denied, and the shim gives it no owner retry |

Without the mount (the work Mac, CachyOS) every call is the owner's, as before the shim.

A value goes from its item to the program that consumes it through `op run` or `op inject`, never
`op read`.

### Consequences

- Good: routine reads cost one approval per unlock, and writes still need the owner present.
- Good: a typo, a bad flag or an expired token prints its own error instead of a biometric prompt.
- Bad: the verb table must follow the `op` CLI. A new write verb goes to the service account and
  fails, loudly, until it is listed.
- Bad: the retry matches `op`'s error text. If the wording changes, an unseen vault fails instead
  of retrying, and the call needs `--account`.
- Bad: a misspelt vault or item name reads the same as an unseen one, so it still reaches the
  owner's prompt.
- `.github/apply-check.sh` fails if the deny rule goes or the shim routes `op read`.

## Reopen when

- 1Password lets a desktop-app approval outlast one shell, or lets a service account write.
- The service account can be granted a vault without being recreated.
- `op` gains a stable exit code or machine-readable error for "no access".
- A consumer turns up that can take a value only on stdout, which `op run` and `op inject` cannot
  serve.
- Agents on the work Mac or CachyOS need unattended reads.
