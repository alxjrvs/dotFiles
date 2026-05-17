---
description: Survey Brewfile + mise drift and draft a bump PR
---

# /dotfiles-bump

Check what's outdated in `~/dotFiles/` and draft an update PR.

## Steps

1. **brew** — `brew update` then `brew outdated --formula` and `brew outdated --cask`. Cross-reference against `Brewfile` to filter out non-managed packages.
2. **mise** — `mise outdated`. Note tools whose declared `"latest"` version drifted from installed.
3. **lazy-lock.json** (nvim) — Check `nvim/lazy-lock.json` last-update time. If >30 days, suggest `nvim --headless "+Lazy! sync" +qa` to refresh.
4. **sheldon** — Check `sheldon/plugins.toml` against latest commits on each repo (skip if rate-limited).

## Output

Group by category. For each outdated item:

```
brew formula: <name>  <current>  →  <latest>     # one-line changelog if interesting
mise tool:    <name>  <current>  →  <latest>
nvim plugins: <N> plugins drifted past 30d, suggest :Lazy sync
```

## PR draft

After reporting, ask the user "Open a `chore(deps): bump …` PR?" If yes:

1. Branch `git switch -c chore/bump-$(date +%Y%m%d)` in `~/dotFiles/`.
2. For each accepted bump: edit Brewfile / mise.toml in place. (Brew formula version isn't pinned in Brewfile, so no edit needed unless you want to add a `version` arg — usually skip.)
3. Run `brew bundle --file=~/dotFiles/Brewfile --no-upgrade` and `mise install` to materialize.
4. Verify with `make lint`.
5. Commit + push + open PR with the bump list in the body.

Don't auto-merge.
