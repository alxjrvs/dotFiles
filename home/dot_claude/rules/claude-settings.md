---
paths:
  - "**/.claude/settings.json"
  - "**/.claude/settings.local.json"
  - "**/home/dot_claude/settings.json"
---

# Editing a Claude Code settings.json

- **A Bash rule matches the whole command text**, `*` standing for any text. The
  space before a trailing `*` is load-bearing: `Bash(ls *)` misses `lsof`,
  `Bash(ls*)` catches it. Verify any new `deny` rule with a positive *and* a
  negative control before trusting it.

- **The empty-string env vars are load-bearing**, not leftovers: an unset
  `${VAR}` is passed through as a literal and read as a real value.

`permissions.deny` is a floor, not the whole control — `home/dot_claude/hooks/op-guard.sh`
sits above it as an allow-list, because a deny-list of verbs fails open on the
verb nobody thought of.
