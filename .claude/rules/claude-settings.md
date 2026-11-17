---
paths:
  - "home/.chezmoitemplates/**"
  - "home/dot_claude/**"
---

# Claude config in the source state

- `home/dot_claude/` is the **user-global** Claude config (`~/.claude/`); the repo-root `.claude/`
  is this repo's project scope. Don't conflate them.
- `~/.claude/settings.json` is a modify template: chezmoi enforces only the keys in
  `home/.chezmoitemplates/claude-settings.json`, and a `null` there retires a key.
