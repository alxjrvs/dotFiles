# 1. Claude Code's sandbox is on

## Status

Accepted, 2026-11-17. The owner asked for it.

## Context

`sandbox` in `home/.chezmoitemplates/claude-settings.json` has been turned on, reshaped or turned
off about ten times. The flips this decision replaces:

| PR | State | Stated reason |
| :- | :- | :- |
| #286 | on, shaped as egress control | the first measured config |
| #342, #356, #385, #402, #404 | on, patched | each names one more thing the toolchain needed: gh, trustd, mise's cache, `chezmoi apply` |
| #458 | on, wider | agents could not run `mise run lint` or bind a port |
| #462 | off | "The owner asked for this", the same day as #458 |
| #524, #525, #531 | on, strict: no unsandboxed retry, exit if unavailable | op and gh kept inside it; 1Password's regional domains; localhost |
| #547 | off | owner asked: "turn the sandbox off everywhere, for now" |
| #552 | off | CachyOS stops installing bubblewrap and socat |

No PR that turned it off cites a protection that failed; #462 and #547 say only that the owner
asked. Session data for the 85 days before this decision names what got in the way: git's
`config.lock`, a stat of `.env`, GitHub over the network, 1Password's domains, mise tasks, and
binding a localhost port.

With it off, the `Read(...)` deny rules stop the Read tool only. `cat` in Bash reads the same
secrets files, and the auto-mode classifier is the one gate.

## Decision Drivers

- Safe: the secrets files the `Read` deny rules name are unreadable from Bash, enforced by the
  OS and not by a judgment about a command string.
- Hands off: git, gh, mise, bun and `op` work without the owner approving anything.
- Small: only keys the documentation lists today, and none that equals its default.

## Considered Options

1. Off, as #547 left it.
2. Strict, as #524 left it: `allowUnsandboxedCommands: false`, `failIfUnavailable: true`.
3. On, with the known blockers allowed through and the unsandboxed retry left to the auto-mode
   classifier.
4. On, with `Bash(dangerouslyDisableSandbox:true)` as an `ask` rule, so the owner approves every
   retry.

## Decision Outcome

Option 3.

- **Secrets.** Claude Code adds `Read` deny rules to the sandbox's `denyRead`, so the existing
  rules cover Bash with no second list.
- **The retry.** `allowUnsandboxedCommands` keeps its default. In auto mode the classifier judges
  a retry, and `autoMode.environment` tells it a retry has no floor. Under option 2 a command the
  sandbox could not run had no way out, and #547 followed two weeks later. Option 4 prompts, which
  is not hands off.
- **A host not listed.** `strictAllowlist` stays off, so in auto mode a command names the extra
  hosts it needs and the classifier judges them with it.
- **`excludedCommands`.** `op *`, because `~/.claude/bin/op` reads the service-account token from
  one of the denied files. The git subcommands that write `.git/config`, because the sandbox
  protects that file and `allowWrite` cannot lift it.
- **Kept inside.** gh, through `allowMachLookup` of `com.apple.trustd.agent` (#524 measured it);
  the documentation's alternative, excluding `gh *`, gives it full access.
- **`failIfUnavailable`** stays off: a machine that cannot start the sandbox still starts Claude
  Code. CachyOS installs bubblewrap and socat again so that it can.
- **`ignoreViolations`** for `/.env`: a tool that stats it is still refused, but the refusal is
  no longer reported as a violation for the agent to retry.

## Consequences

- An excluded `op run -- <cmd>` runs `<cmd>` outside the sandbox, and an excluded git command
  runs its hooks there. Both still pass the classifier and the `Bash(...)` deny rules.
- An `op` started inside a sandboxed command cannot read the token, so it signs in as the owner,
  with a biometric prompt.
- A call that mixes an excluded command with others (`git fetch && git switch -c …`) stays
  sandboxed, so the config write fails and the retry goes to the classifier.
- A tool that treats a refused `.env` as fatal still fails, and needs the retry.
- `*.github.com` is broad: anything a sandboxed command can read, it can send there.
- `~/.local/share/mise` is writable and holds programs on `PATH`.
- `apply-check` fails when the rendered settings have the sandbox off.

## Reopen when

Turning it off, or back to strict, cites one of these in the PR that does it:

1. A named command, with its sandbox error and Claude Code version, that fails inside the sandbox
   and that no documented key (`allowWrite`, `allowedDomains`, `allowMachLookup`,
   `excludedCommands`) lets through.
2. Session data, over at least two weeks, showing retries the classifier refused for work the
   owner asked for, with the commands.
3. A release that removes the classifier from the unsandboxed retry, or stops adding `Read` deny
   rules to `denyRead`, with the changelog entry.
4. A demonstrated read of a denied secrets file from a sandboxed command, which makes the
   sandbox's cost buy nothing.

"It got in the way" without a command is not on the list: add the key that lets the command
through instead.
