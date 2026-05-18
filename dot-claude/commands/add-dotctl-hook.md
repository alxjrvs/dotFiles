---
description: Scaffold a new dotctl hook arm (Rust) and wire it into settings.json
argument-hint: <event-name> <claude-event> [matcher]
---

# /add-dotctl-hook

Scaffold a new Claude Code hook handler **inside the dotctl Rust binary** (not a bash script). Every hook in this repo routes through `dotctl hook <event-name>` — see `dotctl/src/hook.rs`. Adding a hook means: add a Rust function, register it in the dispatcher, write a unit test, then wire the settings.json entry.

## Arguments

- `<event-name>` — kebab-case slug for the new arm, e.g. `pr-link-injector`. Becomes the argument to `dotctl hook <event-name>`.
- `<claude-event>` — one of: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`, `Stop`, `CwdChanged`, `PreCompact`, `PermissionDenied`.
- `[matcher]` — optional, e.g. `Bash` or `Edit|Write` for PreToolUse/PostToolUse. Empty for the others.

If any are missing, ask before scaffolding.

## Steps

1. **Add the handler function** in `dotctl/src/hook.rs` (above the `#[cfg(test)] mod tests` block). Template:

   ```rust
   // -------------------------------------------- N. <event-name> (<ClaudeEvent>)

   // <one-line purpose>. Exit 0 = allow / continue; exit 2 = block
   // (PreToolUse only; the stderr message surfaces to the model).
   fn <snake_event_name>() -> Result<()> {
       let input = read_stdin_json();
       // Use str_at / bool_at to walk into the JSON.
       // Default to Ok(()) unless the hook has a reason to intervene.
       let _ = input;
       Ok(())
   }
   ```

2. **Register in the dispatcher** at the top of `hook.rs::run()`:

   ```rust
   "<event-name>" => <snake_event_name>(),
   ```

   Add it before the catchall `other =>` arm. Maintain the existing 1:1 ordering by Claude event.

3. **Add at least one unit test** in `mod tests` at the bottom of `hook.rs`. Required by the guardrail in `CLAUDE.md` ("Add tests for any new event handler before wiring it into settings.json"). Use the existing `str_at` / `bool_at` patterns; mock stdin by extracting hook logic into a helper that takes `&Value`. Example:

   ```rust
   #[test]
   fn <snake_event_name>_handles_missing_field_gracefully() {
       let v = serde_json::json!({});
       // ... assert behavior on the empty-input path ...
   }
   ```

4. **Wire `settings.json`** under `hooks.<ClaudeEvent>`:

   ```json
   {
     "matcher": "<matcher or empty string>",
     "hooks": [
       { "type": "command", "command": "dotctl hook <event-name>", "timeout": 5 }
     ]
   }
   ```

   Match the indentation of existing entries. If an entry for this event already exists with the same matcher, append to its `hooks[]` array rather than creating a new matcher block.

5. **Update `CLAUDE.md`** — append a row to the hook-dispatch table so the architecture doc keeps tracking what fires when.

6. **Build + test:**

   ```bash
   cargo test --manifest-path=dotctl/Cargo.toml --quiet
   ```

   Failures block the commit (`lefthook.yml` pre-push runs the same suite). Fix at write time.

7. **Install** (the running `dotctl` binary is replaced by `step_dotctl` during a normal sync; manual install for immediate effect):

   ```bash
   cargo install --path dotctl --root ~/.local --force --quiet
   ```

8. **Verify** — confirm the hook fires by triggering the corresponding event in a new Claude session. Don't commit until you've seen the arm execute (use a `eprintln!("DEBUG: <event-name> fired")` during dev, strip before commit).

## Why a Rust arm, not a bash script

`dot-claude/settings.json` should never gain new `"command": "bash ~/..."` entries. The architecture (CLAUDE.md "Hook dispatch") routes every Claude event through one Rust dispatcher so:

- Hooks are unit-testable.
- A panic or 5s timeout in one hook can't take out the others.
- `lefthook.yml` pre-push runs the suite — silent regressions get caught.
- New hooks compose against shared helpers (`str_at`, `bool_at`, `read_stdin_json`, `append_jsonl`, `home_path`).

## Gotchas

- **PreToolUse Bash** handlers can `eprintln!("BLOCK: ...")` + `std::process::exit(2)` to block. PostToolUse cannot block — emit `hookSpecificOutput.updatedToolOutput` to mutate the response instead.
- **JSON shapes** vary per event — check existing arms for the right `str_at` paths. For example: `["tool_input", "command"]` for Bash, `["tool_input", "file_path"]` for Edit/Write, `["cwd"]` for CwdChanged.
- **Performance**: hooks fire on every tool call; avoid subprocess spawns where possible. `read_stdin_json()` already handles the parse; reuse `which()` for binary presence checks (do not roll your own).
- **Stdout discipline**: PreToolUse hooks treat stdout as `hookSpecificOutput` JSON. Don't print human-readable text to stdout from a PreToolUse arm — go to stderr with `eprintln!` instead.
