# asdf to mise Migration Design

## Summary

Replace asdf with mise as the polyglot tool version manager in the dotfiles repo. Clean break — no coexistence period.

## Decisions

- **Config format:** `mise.toml` (mise's native TOML format)
- **Version strategy:** Floating — `lts` for node, `latest` for python and deno. Floating versions are chosen for convenience; use `mise use -g node@22.14.0` to pin if reproducibility is needed.
- **Default npm packages:** Handled via node `postinstall` hook in `mise.toml`
- **Installation:** Via Homebrew (same as asdf today)

## New File: `mise.toml`

```toml
[tools]
node = { version = "lts", postinstall = "npm install -g typescript prettier eslint @anthropic-ai/claude-code" }
python = "latest"
deno = "latest"
```

Symlinked to `~/.config/mise/config.toml` (mise's global config path).

## Files Removed

| File | Reason |
|------|--------|
| `.tool-versions` | Replaced by `mise.toml` |
| `.asdfrc` | No mise equivalent needed |
| `.default-npm-packages` | Handled by postinstall hook in `mise.toml` |

Note: `.npmrc` is **retained** — it is npm config, not asdf-specific.

## File Changes

### `Brewfile`

```diff
- brew "asdf"
+ brew "mise"
```

### `.zshrc`

The `mise activate` line replaces the asdf env var export. It must be placed **before** any commands that depend on managed tools. Currently, line 10 runs `npm config set` at shell startup, which needs mise-managed node to be available. Move the mise activation early in `.zshrc`, after Homebrew completions setup (line 43) and before the npm token line (line 10), or move the npm token line below mise activation.

Recommended approach — move the npm token block below mise activation:

```diff
- # Line 10 (current location)
- [[ -n "$NPM_TOKEN" ]] && npm config set //registry.npmjs.org/:_authToken "$NPM_TOKEN" 2>/dev/null

  # ... sheldon, completions, etc. ...

- # asdf default packages
- command -v asdf &>/dev/null && export ASDF_NPM_DEFAULT_PACKAGES_FILE=~/.default-npm-packages
+ # mise (tool version manager)
+ command -v mise &>/dev/null && eval "$(mise activate zsh)"
+
+ # Inject npm token from secrets (never store in .npmrc)
+ [[ -n "$NPM_TOKEN" ]] && npm config set //registry.npmjs.org/:_authToken "$NPM_TOKEN" 2>/dev/null
```

### `sync.sh`

**Section 5 — replace asdf loop with mise install:**

```bash
# ── 5. mise tools (from mise.toml) ──────────────────────────────────
if should_run mise; then
echo ""
echo "==> mise tools"
warn "Installing/updating tools from mise.toml..."
mise trust ~/.config/mise/config.toml 2>/dev/null || true
mise install
ok "mise tools up to date"
fi # should_run mise
```

Note: `mise trust` ensures the global config is trusted for non-interactive setup.

**Symlinks section — replace asdf block:**

```diff
- if should_run symlinks git shell asdf sheldon starship ghostty nvim gh claude; then
+ if should_run symlinks git shell mise sheldon starship ghostty nvim gh claude; then
```

```diff
- # asdf config (Darwin only)
- if [ "$OS" = "Darwin" ]; then
- if should_run symlinks asdf; then
- link "$DOTFILES_DIR/.tool-versions"        "$HOME/.tool-versions"        ".tool-versions"
- link "$DOTFILES_DIR/.default-npm-packages" "$HOME/.default-npm-packages" ".default-npm-packages"
- link "$DOTFILES_DIR/.asdfrc"               "$HOME/.asdfrc"               ".asdfrc"
- link "$DOTFILES_DIR/.npmrc"                "$HOME/.npmrc"                ".npmrc"
- chmod 600 "$HOME/.npmrc" 2>/dev/null || true
- fi
- fi # Darwin
+ # mise config (Darwin only)
+ if [ "$OS" = "Darwin" ]; then
+ if should_run symlinks mise; then
+ mkdir -p "$HOME/.config/mise"
+ link "$DOTFILES_DIR/mise.toml"  "$HOME/.config/mise/config.toml"  "mise/config.toml"
+ link "$DOTFILES_DIR/.npmrc"     "$HOME/.npmrc"                    ".npmrc"
+ chmod 600 "$HOME/.npmrc" 2>/dev/null || true
+ fi
+ fi # Darwin
```

**Help text — all four `asdf` → `mise` replacements:**

1. Line 32: `--help` section name `asdf` → `mise` and description update
2. Line 232: `should_run asdf` → `should_run mise` (section 5 guard)
3. Line 266: `should_run symlinks ... asdf ...` → `should_run symlinks ... mise ...` (symlinks header)
4. Line 306: `should_run symlinks asdf` → `should_run symlinks mise` (asdf symlinks guard)

**Claude Code section (line 386) — update stale message:**

```diff
- warn "Claude Code not installed — will be auto-installed with Node via .default-npm-packages"
+ warn "Claude Code not installed — will be installed by mise postinstall hook"
```

### Documentation Updates

**`CLAUDE.md` (project root):**

- Symlink table: replace `.tool-versions`, `.asdfrc`, `.default-npm-packages` rows with `mise.toml` → `~/.config/mise/config.toml`
- Key commands: `asdf install` → `mise install`
- Language versions section: reference mise instead of asdf
- Architecture section: update `.tool-versions` reference

**`dot-claude/CLAUDE.md`:**

- Conventions: "Language versions go in `mise.toml`"

**`.claude/CLAUDE.md`:**

- Remove `.tool-versions` mention from structure

**Project memory (`MEMORY.md`):**

- Update any asdf or `.tool-versions` references to mise

## Post-Migration Cleanup

After the migration is complete and verified working:

1. **Remove asdf:** `brew uninstall asdf` (or let `brew bundle cleanup` handle it)
2. **Remove `~/.asdf` directory:** Contains old installed tool versions and shims. Can be several GB. Run `rm -rf ~/.asdf` after confirming mise tools work.
3. **Remove stale symlinks:** `~/.tool-versions`, `~/.asdfrc`, `~/.default-npm-packages` — these will be dangling after source files are deleted from the repo.
4. **Brewfile.lock.json:** Will be regenerated by `brew bundle` — expect changes and commit them.
