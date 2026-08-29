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

A new guard is wired in four places or it silently does nothing. The procedure,
including which four, is the `hook-authoring` skill — invoke it rather than
working from memory. Add a regression case under `dot-claude/hooks/tests/`
before changing behaviour; `all.sh` discovers the roster from the directory, so
a new suite needs no wiring.
