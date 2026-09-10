---
paths:
  - "**/home/dot_claude/hooks/*.sh"
  - "**/.claude/hooks/*.sh"
---

# Touching a hook

Two hooks live here: `repo-scope-guard.sh` (PreToolUse, `gh` writes outside the owned orgs)
and `verify-gate.sh` (Stop, the repo's own commit gate over the turn's changed files).

- **They fail open, by design.** A missing `jq`, a bad payload, an unparseable command: exit 0.
  A hook that wedges the session gets deleted, which is worse than one that misses.
- **They deny; they never emit `allow`.** Deny rules in `permissions.deny` cover the secret
  paths; a hook only subtracts.
- **Tokenize, never substring-match.** `guard-lib.sh` splits on unquoted separators and strips
  wrappers; `git commit -m "gh pr create"` must pass.
- **Wire it in `home/dot_claude/settings.json`** with an `"if"` on the handler (a substring rule,
  `Bash(*gh*)`), and commit the script with its executable bit.
- **Add the regression case before changing behaviour.** `tests/all.sh` discovers every suite in
  its directory. Most cases assert the guard did NOT fire, so a stub hook passes them; run the
  negative control named in each suite's header before trusting green.
- bash 3.2: no arrays, no `declare -g`. A hook cannot assume its PATH.
