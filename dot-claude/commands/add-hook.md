---
description: Scaffold a new dotfiles hook script and wire it into settings.json
argument-hint: <event-name> <claude-event> [matcher]
---

# /add-hook

Scaffold a new Claude Code hook handler as a **standalone bash script** in `hooks/`. Every hook in this repo routes through `dot hook <event-name>` — see `hooks/` and `dot-claude/settings.json`. Adding a hook means: create the script, make it executable, write a bats unit test, then wire the settings.json entry.

## Arguments

- `<event-name>` — kebab-case slug for the new arm, e.g. `pr-link-injector`. Becomes the argument to `dot hook <event-name>`.
- `<claude-event>` — one of: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`, `Stop`, `CwdChanged`, `PreCompact`, `PermissionDenied`.
- `[matcher]` — optional, e.g. `Bash` or `Edit|Write` for PreToolUse/PostToolUse. Empty for the others.

If any are missing, ask before scaffolding.

## Steps

1. **Create the hook script** at `hooks/<event-name>` (no `.sh` extension, matches the `dot hook <event>` dispatch). Template:

   ```bash
   #!/usr/bin/env bash
   # hooks/<event-name> — <one-line purpose>.
   # Reads Claude Code JSON from stdin; emits structured JSON response to stdout.
   # Exit 0 = allow/continue. For PreToolUse: exit 2 = block (stderr shown to model).
   set -uo pipefail

   # ── Helpers ──────────────────────────────────────────────────────────────────
   _log() { printf '[<event-name>] %s\n' "$*" >&2; }

   # ── Main ─────────────────────────────────────────────────────────────────────
   input=$(cat)

   # Use jq to extract fields from $input.
   # tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')

   # Default: pass through (no-op).
   exit 0
   ```

2. **Make it executable:**

   ```bash
   chmod +x hooks/<event-name>
   ```

3. **Add at least one bats test** in `test/hooks/<event-name>.bats`. Required by the CLAUDE.md guardrail ("Add tests for any new event handler before wiring it into settings.json"). Use the existing test files as examples. Template:

   ```bash
   #!/usr/bin/env bats
   # test/hooks/<event-name>.bats — unit tests for hooks/<event-name>

   setup() {
     HOOK="$BATS_TEST_DIRNAME/../../hooks/<event-name>"
   }

   @test "passes through on empty input" {
     run bash "$HOOK" <<< '{}'
     [ "$status" -eq 0 ]
   }
   ```

4. **Wire `settings.json`** under `hooks.<ClaudeEvent>`:

   ```json
   {
     "matcher": "<matcher or empty string>",
     "hooks": [
       { "type": "command", "command": "dot hook <event-name>", "timeout": 5 }
     ]
   }
   ```

   Match the indentation of existing entries. If an entry for this event already exists with the same matcher, append to its `hooks[]` array rather than creating a new matcher block.

5. **Update `CLAUDE.md`** — append a row to the hook-dispatch table so the architecture doc keeps tracking what fires when.

6. **Run tests:**

   ```bash
   bats test/hooks/<event-name>.bats
   ```

   Failures block the commit (`lefthook.yml` pre-push runs the suite). Fix at write time.

7. **Verify** — confirm the hook fires by triggering the corresponding event in a new Claude session. Add a temporary `_log "DEBUG: <event-name> fired"` during dev, strip before commit.

## Why a bash script, not a compiled binary

`hooks/` contains standalone bash scripts, one per event. Each is:

- Independently runnable and directly inspectable.
- Unit-testable via bats.
- Wired through `dot hook <event>` so the dispatcher is the single entry point.
- Self-contained (no `source` of sibling files — inline any helpers the script needs).

## Gotchas

- **PreToolUse Bash** handlers can `printf 'BLOCK: ...\n' >&2` + `exit 2` to block. PostToolUse cannot block — emit `hookSpecificOutput.updatedToolOutput` via jq to mutate the response instead.
- **JSON shapes** vary per event — check existing hook scripts for the right jq paths. For example: `.tool_input.command` for Bash, `.tool_input.file_path` for Edit/Write.
- **Performance**: hooks fire on every tool call; avoid unnecessary subprocess spawns. `jq` is the right tool for JSON; `command -v` for binary presence checks.
- **Stdout discipline**: PreToolUse hooks treat stdout as `hookSpecificOutput` JSON. Don't print human-readable text to stdout from a PreToolUse hook — use `>&2` instead.
- **`set -e` omission**: hooks intentionally use `set -uo pipefail` (not `-euo pipefail`) so a missing JSON field doesn't abort the whole hook; handle errors explicitly.
