---
paths:
  - "**/dot-claude/hooks/*.sh"
  - "**/.claude/hooks/*.sh"
---

# Touching a guard hook

Three properties hold for every script here, and breaking one is silent:

- **They fail open, by design.** A missing `jq`, a bad envelope, an unparseable
  command: all exit 0 and allow. A guard that wedges the session gets deleted,
  which is worse than one that misses. Keep new error paths failing open.
- **They may deny, never allow.** No guard emits `permissionDecision: "allow"` —
  that would bypass the permission system and put the hook *above*
  `permissions.deny`. Subtract permission only, so the two compose.
- **Tokenize, never substring-match.** `guard-lib.sh` carries the quote-aware
  splitter. `git log --grep "git push"` must pass untouched.

## Wire it in four places or it does nothing

This is the step that gets missed, and the failure is silent: the script sits on
disk, passes its own suite, and enforces nothing.

1. `dot-claude/settings.json` — a handler under the right event. Put an `"if"`
   on the HANDLER, never on the matcher group: it is silently dropped there.
2. `boomfile.toml` — a `[[section.link]]` with `mode = "755"`, or it is never
   symlinked into `~/.claude/hooks/`.
3. `scripts/settings-guardrails.sh` — add the filename to `wired_hooks`. This is
   what makes un-wiring it fail lefthook, CI and `boom verify` rather than
   passing all three.
4. `lefthook.yml` and `.github/workflows/lint.yml` — a suite entry.

## Tests

Add the regression case before changing behaviour. `all.sh` discovers the roster
from `dot-claude/hooks/tests/`, so a new suite needs no wiring. Fixture-table
cases go in `cases.tsv`; a guard whose verdict depends on machine state needs
its own harness — copy `wtremove.sh` or `reposcope.sh`.

**Record the negative control, measured.** When most cases assert the guard did
NOT fire, a hook that does nothing passes them all. Run a stub (`exit 0`) and an
inverted variant, and write the resulting failure counts into the suite header.
Do not reason them out: the counts were wrong both times someone tried.

## Portability

bash 3.2 — a hook cannot assume its PATH, and launchd or a mid-provision machine
can hand it the system bash. No arrays, no `${arr[@]}` on a possibly-empty array,
no `declare -g`.
