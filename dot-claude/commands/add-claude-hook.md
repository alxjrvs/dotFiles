---
description: Scaffold a new dot-claude/hooks/<name>.sh and wire it into settings.json
argument-hint: <hook-name> <event> [matcher]
---

# /add-claude-hook

Create a new Claude Code hook script and register it in `dot-claude/settings.json`.

## Arguments

- `<hook-name>` — e.g. `policy-guard`. Becomes `dot-claude/hooks/<hook-name>.sh`.
- `<event>` — one of: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`, `CwdChanged`, `PreCompact`, `PermissionDenied`, `Stop`.
- `[matcher]` — optional, e.g. `Bash` or `Edit|Write` for PreToolUse/PostToolUse. Empty for other events.

If any are missing, ask the user before scaffolding.

## Steps

1. **Create the hook script** at `~/dotFiles/dot-claude/hooks/<hook-name>.sh` using this template (adapt to the event's input shape):

   ```bash
   #!/usr/bin/env bash
   # <event> hook: <one-line purpose>.
   # Exit 0 = allow / continue. Exit 2 = block (PreToolUse only; stderr surfaces to model).
   # Reads tool input from stdin as JSON; emit hookSpecificOutput to stdout when modifying behavior.

   set -uo pipefail

   input=$(cat)

   # Extract relevant fields with jq -r '.tool_name // empty' etc.
   # Default to exit 0 unless the hook has a reason to intervene.

   exit 0
   ```

2. **Register in `dot-claude/settings.json`** under `hooks.<event>`:
   ```json
   {
     "matcher": "<matcher or empty string>",
     "hooks": [
       { "type": "command", "command": "bash ~/.claude/hooks/<hook-name>.sh", "timeout": 5 }
     ]
   }
   ```
   Match the indentation and formatting of existing hook entries. If an entry for this event already exists with the same matcher, append to its `hooks[]` array instead of creating a new matcher block.

3. **`chmod +x`** the new script.

4. **Lint** — Run `shellcheck -x` and `shfmt -d -i 2 -ci -sr` on the new file. Fix any findings before reporting done.

5. **Verify** — Confirm the hook fires on the next tool call of that type. Don't commit; let the user review the scaffold and add the actual logic before committing.

## Gotchas

- For `PreToolUse` on `Bash`: extract `cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')`.
- For `PostToolUse`: `.tool_response.stdout` and `.tool_response.stderr` are available.
- Always `2> /dev/null || true` external commands so hook failures don't bubble unexpectedly.
- Lefthook's pre-commit gate will block the commit if shellcheck/shfmt fail — fix at write time, not after.
