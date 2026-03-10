# asdf to mise Migration — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace asdf with mise as the polyglot tool version manager across all dotfiles.

**Architecture:** Create `mise.toml` with floating tool versions and postinstall hooks. Update `sync.sh` to use `mise install` instead of the asdf plugin loop. Update `.zshrc` shell activation and reorder npm token line. Remove asdf config files. Update all documentation.

**Tech Stack:** mise, Homebrew, zsh, bash (sync.sh)

**Spec:** `docs/superpowers/specs/2026-03-10-asdf-to-mise-migration-design.md`

---

## Chunk 1: Core migration (config files + sync.sh + shell)

### Task 1: Create `mise.toml` and remove asdf config files

**Files:**
- Create: `mise.toml`
- Delete: `.tool-versions`
- Delete: `.asdfrc`
- Delete: `.default-npm-packages`

- [ ] **Step 1: Create `mise.toml`**

```toml
[tools]
node = { version = "lts", postinstall = "npm install -g typescript prettier eslint @anthropic-ai/claude-code" }
python = "latest"
deno = "latest"
```

- [ ] **Step 2: Delete `.tool-versions`**

```bash
git rm .tool-versions
```

- [ ] **Step 3: Delete `.asdfrc`**

```bash
git rm .asdfrc
```

- [ ] **Step 4: Delete `.default-npm-packages`**

```bash
git rm .default-npm-packages
```

- [ ] **Step 5: Commit**

```bash
git add mise.toml
git commit -m "feat: add mise.toml, remove asdf config files"
```

---

### Task 2: Update `Brewfile`

**Files:**
- Modify: `Brewfile:3`

- [ ] **Step 1: Replace asdf with mise in Brewfile**

Change line 3 from:
```
brew "asdf"
```
to:
```
brew "mise"
```

- [ ] **Step 2: Commit**

```bash
git add Brewfile
git commit -m "chore: replace asdf with mise in Brewfile"
```

---

### Task 3: Update `sync.sh` — all asdf references

**Files:**
- Modify: `sync.sh:32` (help text)
- Modify: `sync.sh:231-261` (section 5 — asdf languages)
- Modify: `sync.sh:266` (symlinks header)
- Modify: `sync.sh:304-313` (asdf symlinks block)
- Modify: `sync.sh:386` (Claude Code stale message)

- [ ] **Step 1: Update help text (line 32)**

Change:
```
echo "  asdf      asdf language versions"
```
to:
```
echo "  mise      mise tool versions"
```

- [ ] **Step 2: Replace section 5 (lines 231-261)**

Replace the entire block from `# ── 5. asdf languages` through `fi # should_run asdf` with:

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

- [ ] **Step 3: Update symlinks header (line 266)**

Change:
```bash
if should_run symlinks git shell asdf sheldon starship ghostty nvim gh claude; then
```
to:
```bash
if should_run symlinks git shell mise sheldon starship ghostty nvim gh claude; then
```

- [ ] **Step 4: Replace asdf symlinks block (lines 304-313)**

Replace the entire block from `# asdf config (Darwin only)` through `fi # Darwin` with:

```bash
# mise config (Darwin only)
if [ "$OS" = "Darwin" ]; then
if should_run symlinks mise; then
mkdir -p "$HOME/.config/mise"
link "$DOTFILES_DIR/mise.toml"  "$HOME/.config/mise/config.toml"  "mise/config.toml"
link "$DOTFILES_DIR/.npmrc"     "$HOME/.npmrc"                    ".npmrc"
chmod 600 "$HOME/.npmrc" 2>/dev/null || true
fi
fi # Darwin
```

- [ ] **Step 5: Update Claude Code stale message (line 386)**

Change:
```bash
  warn "Claude Code not installed — will be auto-installed with Node via .default-npm-packages"
```
to:
```bash
  warn "Claude Code not installed — will be installed by mise postinstall hook"
```

- [ ] **Step 6: Commit**

```bash
git add sync.sh
git commit -m "feat: replace asdf with mise in sync.sh"
```

---

### Task 4: Update `.zshrc` — shell activation and npm token reorder

**Files:**
- Modify: `.zshrc:9-10` (remove npm token from current location)
- Modify: `.zshrc:154-155` (replace asdf block with mise activation + relocated npm token)

- [ ] **Step 1: Remove npm token line from its current location (line 9-10)**

Remove these two lines (and the blank line after them, to avoid a double-blank):
```
# Inject npm token from secrets (never store in .npmrc)
[[ -n "$NPM_TOKEN" ]] && npm config set //registry.npmjs.org/:_authToken "$NPM_TOKEN" 2>/dev/null
```

- [ ] **Step 2: Replace asdf block with mise activation + npm token (lines 154-155)**

Replace:
```bash
# asdf default packages
command -v asdf &>/dev/null && export ASDF_NPM_DEFAULT_PACKAGES_FILE=~/.default-npm-packages
```
with:
```bash
# mise (tool version manager)
command -v mise &>/dev/null && eval "$(mise activate zsh)"

# Inject npm token from secrets (never store in .npmrc)
[[ -n "$NPM_TOKEN" ]] && npm config set //registry.npmjs.org/:_authToken "$NPM_TOKEN" 2>/dev/null
```

- [ ] **Step 3: Commit**

```bash
git add .zshrc
git commit -m "feat: replace asdf with mise activation in .zshrc"
```

---

## Chunk 2: Documentation updates

### Task 5: Update `CLAUDE.md` (project root)

**Files:**
- Modify: `CLAUDE.md:12-15` (key commands)
- Modify: `CLAUDE.md:30` (symlink table row)
- Modify: `CLAUDE.md:56-58` (language versions section)

- [ ] **Step 1: Update key commands (lines 12-14)**

Change:
```
./sync.sh             # Full idempotent setup (Homebrew, asdf, symlinks, plugins, macOS defaults)
brew bundle           # Install/update packages from Brewfile
asdf install          # Install language versions from .tool-versions
```
to:
```
./sync.sh             # Full idempotent setup (Homebrew, mise, symlinks, plugins, macOS defaults)
brew bundle           # Install/update packages from Brewfile
mise install          # Install language versions from mise.toml
```

- [ ] **Step 2: Update symlink table (line 30)**

Change:
```
| `.tool-versions`, `.asdfrc`, `.npmrc` | `~/` |
```
to:
```
| `mise.toml` | `~/.config/mise/config.toml` |
| `.npmrc` | `~/` |
```

- [ ] **Step 3: Update language versions section (lines 56-58)**

Change:
```
### Language Versions

Managed by **asdf** via `.tool-versions`. Default npm packages (TypeScript, Prettier, ESLint, Claude Code) auto-install with each Node version via `.default-npm-packages`.
```
to:
```
### Language Versions

Managed by **mise** via `mise.toml`. Default npm packages (TypeScript, Prettier, ESLint, Claude Code) auto-install with each Node version via the `postinstall` hook in `mise.toml`.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for mise migration"
```

---

### Task 6: Update `.claude/CLAUDE.md`

**Files:**
- Modify: `.claude/CLAUDE.md:7` (structure — asdf reference)
- Modify: `.claude/CLAUDE.md:20` (conventions — .tool-versions reference)
- Modify: `.claude/CLAUDE.md:21` (conventions — install.sh reference to sync.sh)

- [ ] **Step 1: Update structure line (line 7)**

Change:
```
- `install.sh` — idempotent installer: brew, asdf, symlinks, macOS defaults
```
to:
```
- `sync.sh` — idempotent installer: brew, mise, symlinks, macOS defaults
```

- [ ] **Step 2: Update conventions (line 20)**

Change:
```
- Language versions go in `.tool-versions`
```
to:
```
- Language versions go in `mise.toml`
```

- [ ] **Step 3: Update symlinks convention (line 21)**

Change:
```
- All symlinks use the `link()` helper in `install.sh` (idempotent, with conflict resolution)
```
to:
```
- All symlinks use the `link()` helper in `sync.sh` (idempotent, with conflict resolution)
```

- [ ] **Step 4: Update adding a dotfile section (lines 26-27)**

Change:
```
2. Add a `link` line in the `Symlinks` section of `install.sh`
3. Run `./install.sh` to verify
```
to:
```
2. Add a `link` line in the `Symlinks` section of `sync.sh`
3. Run `./sync.sh` to verify
```

- [ ] **Step 5: Commit**

```bash
git add .claude/CLAUDE.md
git commit -m "docs: update .claude/CLAUDE.md for mise migration"
```

---

### Task 7: Update project memory

**Files:**
- Modify: `/Users/jarvis/.claude/projects/-Users-jarvis-dotFiles/memory/MEMORY.md`

- [ ] **Step 1: No asdf-specific references exist in MEMORY.md currently**

Verify the file has no asdf or `.tool-versions` references. The current content only covers tool quirks and starship prompt — no changes needed unless references exist.

- [ ] **Step 2: Skip commit** (memory files are not in the repo)

---

## Chunk 3: Post-migration cleanup

### Task 8: Verify and clean up

This task is manual/interactive — the implementer should run these after confirming mise works.

- [ ] **Step 1: Source the new shell config**

```bash
source ~/.zshrc
```

- [ ] **Step 2: Verify mise is active**

```bash
mise --version
mise ls
```

Expected: mise shows installed tools (node, python, deno).

- [ ] **Step 3: Verify node and global packages**

```bash
node --version
which typescript
which prettier
which eslint
which claude
```

- [ ] **Step 4: Remove stale symlinks**

```bash
rm -f ~/.tool-versions ~/.asdfrc ~/.default-npm-packages
```

- [ ] **Step 5: Remove asdf data directory**

```bash
rm -rf ~/.asdf
```

- [ ] **Step 6: Uninstall asdf via brew**

```bash
brew uninstall asdf
```

- [ ] **Step 7: Final commit with any Brewfile.lock.json changes**

```bash
git add Brewfile.lock.json
git commit -m "chore: clean up asdf remnants after mise migration"
```

Note: `dot-claude/CLAUDE.md` was checked and contains no asdf references — no changes needed there.
