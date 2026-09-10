---
paths:
  - "**/home/dot_claude/hooks/*.sh"
  - "**/.claude/hooks/*.sh"
---

# Touching a hook

One hook lives here: `verify-gate.sh` (Stop, the repo's own commit gate over the turn's changed
files). Everything else in this config stops a bad ACTION; this checks the WORK.

- **It fails open, by design.** A missing `jq`, a bad payload, a timeout: exit 0. A hook that
  wedges the session gets deleted, which is worse than one that misses.
- **A Stop hook runs every turn**, so it stays narrow: only on a dirty tree, only in a repo that
  declares a gate, only over the changed files, once per tree state, under a time bound.
- **Name the source `executable_<name>.sh`**: chezmoi sets the target's mode from that prefix,
  not from the checkout.
- **Add the regression case before changing behaviour.** `tests/all.sh` discovers every suite in
  its directory. Most cases assert the gate did NOT fire, so a stub hook passes them; run the
  negative control named in the suite's header before trusting green.
- bash 3.2: no arrays, no `declare -g`. A hook cannot assume its PATH.

**A hook cannot be the write boundary on an MCP path.** A `PreToolUse` matcher matches a tool
name, so nothing here reaches `mcp__github__*`. That boundary is `--exclude-tools` on the server
registration in `home/run_after_50-provision.sh`.
