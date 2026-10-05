---
name: verify
description: Prove a dotFiles change before committing it - `mise run lint`, then `mise run apply-check`, from the repo root. Use before every commit in this repo.
---

# Verify a dotFiles change

From the repository root:

1. `mise run lint`
2. `mise run apply-check`

Fix what fails and run both again until they pass. apply-check applies the source into a temporary
home and writes nothing else, so it is safe on a Mac, in CI and in a web session. In a web session
the SessionStart hook builds chezmoi in the background; if `chezmoi` is missing, wait a minute.
