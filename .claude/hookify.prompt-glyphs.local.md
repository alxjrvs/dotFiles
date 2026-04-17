---
name: warn-prompt-glyphs
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: (\.zshrc|theme\.sh)$
---

**Prompt / theme file edit**

This file contains raw powerline glyphs (U+E0B0, U+E0B2, U+E0A0, U+276F) that Edit/Write will strip silently.

Before continuing:
- Confirm the edit does not touch a line containing a glyph character.
- If it does, use a Python helper to write the file byte-exact instead of Edit.
- See the Guardrails section of `/Users/jarvis/dotFiles/CLAUDE.md`.
