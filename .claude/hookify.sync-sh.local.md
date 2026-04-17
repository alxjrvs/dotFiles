---
name: warn-sync-sh
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: /sync\.sh$
---

**sync.sh edit — read Guardrails first**

`sync.sh` has interactive symlink semantics via `link()` — conflicts prompt the user.

Before editing:
- Do not make the `link()` function non-interactive (no auto-overwrite).
- Preserve idempotency.
- See Guardrails in `CLAUDE.md`.
