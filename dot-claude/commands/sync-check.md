---
description: Audit dotfiles environment — health, symlinks, brew/mise drift
---

# /sync-check

Verify the dotfiles install on this machine is in a known-good state. Most of this is now covered by `dotctl doctor`; this slash command wraps it with the extra package-drift audits that doctor doesn't do.

## Steps

1. **Doctor** — Run `dotctl doctor` and surface the output verbatim. Doctor covers: git identity, tool presence (dotctl, git, gh, mise, brew, node, bun, sheldon, lefthook, hx), symlink integrity (20 expected paths), and dead-string drift in tracked configs.
2. **Brewfile drift** — `brew bundle check --file=~/dotFiles/Brewfile`. Brewfile should be `brew "mise"` + casks only under Lean A; flag anything else.
3. **mise drift** — `mise current` vs `mise.toml`. Report tools not installed at expected version. Run `mise install` to materialize.
4. **Stale local files** — Flag any `~/.gitconfig.local`, `~/.claude/settings.local.json` that exist but don't match expected shape (the latter is fine if user has machine-local overrides).
5. **lefthook** — Confirm `.git/hooks/pre-commit` exists in `~/dotFiles/.git/hooks/` and was written by lefthook. If not, run `lefthook install` from `~/dotFiles/`.
6. **dotctl test suite** — `cargo test --manifest-path=~/dotFiles/dotctl/Cargo.toml --quiet`. Surfaces any regressions in the hot-path binary.

## Report format

One section per category. If all clean, a single line: "✓ All categories pass." Otherwise, group findings under headers (Doctor / Brewfile / mise / Local / lefthook / Tests) with a one-line fix suggestion per item.

Do not modify anything without asking first — this is a read-only audit by default.
