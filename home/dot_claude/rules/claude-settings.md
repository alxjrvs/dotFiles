---
paths:
  - "**/.claude/settings.json"
  - "**/.claude/settings.local.json"
  - "**/home/dot_claude/settings.json"
---

# Editing a Claude Code settings.json

- **A Bash rule matches the whole command text**, `*` standing for any text, and it reaches
  subshells, substitutions and loop bodies. `Bash(op read:*)` is a prefix; `Bash(*op read*)`
  is a substring and is the form the deny floor uses. Verify a new `deny` rule with a positive
  and a negative control before trusting it.
- **Every `Bash(...)` allow entry is inert in auto mode** while `autoMode.classifyAllShell` is
  true; the classifier judges shell commands instead.
- **The empty-string env vars are load-bearing**: an unset `${VAR}` is passed through as a
  literal and read as a real value.
- **`gh` and `op-sa` are in `sandbox.excludedCommands`** because Go binaries cannot verify TLS
  inside the macOS sandbox; the sandbox docs prescribe exactly this.
