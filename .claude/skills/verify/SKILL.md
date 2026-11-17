---
name: verify
description: Prove a dotFiles change before committing it - `mise run lint`, then `mise run apply-check`, from the repo root. Use before every commit in this repo.
allowed-tools: Bash(mise run lint) Bash(mise run apply-check)
context: fork
background: false
---

# Verify a dotFiles change

You run this repo's two checks and report the result. You see none of the conversation that called
you, and you change no file: the session that called you fixes what fails and calls you again.

From the repository root, run both, the second even when the first fails:

1. `mise run lint`
2. `mise run apply-check`

apply-check applies the source into a temporary home and writes nothing else, so it is safe on a
Mac, in CI and in a web session. In a web session the SessionStart hook builds chezmoi in the
background; if `chezmoi` is missing, wait a minute and run it again.

## What to return

The logs are long and stay with you. Return only:

- `lint`: pass or fail.
- `apply-check`: pass or fail.
- For each failure: the command or lint step that failed, the file paths and line numbers it
  names, and the failing lines themselves, quoted exactly and trimmed to what is needed to fix
  them. No passing output, and no guess at a fix that the output does not state.
- If a command could not run at all (`mise` or `chezmoi` missing), say that instead of "fail".
