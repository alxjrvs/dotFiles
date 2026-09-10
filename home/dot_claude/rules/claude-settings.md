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
- **Anchoring a deny rule on a verb must cover every spelling of the binary.** `*op item get*`
  is right where bare `*item get*` matched prose — but it misses `op-sa item get`, so both are
  listed. Narrowing a rule is where a hole gets opened; add the negative control too.
- **Every `Bash(...)` allow entry is inert in auto mode** while `autoMode.classifyAllShell` is
  true; the classifier judges shell commands instead.
- **The empty-string env vars are load-bearing**: an unset `${VAR}` is passed through as a
  literal and read as a real value.
- **`gh` is in `sandbox.excludedCommands`; `op-sa` is deliberately NOT.** `gh` needs to work
  there and `op-sa` failing there is the control — `docs/GOTCHAS.md` has the mechanism. Do not
  "fix" op-sa by adding it.
- **The write boundary on the MCP path is `--exclude-tools`, not a rule here.** A `PreToolUse`
  matcher matches a tool name, so nothing in this file reaches `mcp__github__*`. That list
  lives in `home/run_after_50-provision.sh`.
