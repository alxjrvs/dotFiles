# Tmux Status Bar Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a two-row tmux status bar with a prefix/command indicator row above the existing bar, redesign center window tabs to show session name island with named tabs flowing from it, and disable Ghostty native tabs.

**Architecture:** Use `set -g status 2` (tmux 3.6a) to create a second status row. The existing bottom bar (format[0]) gains a redesigned center: a purple session-name island with active/inactive tab pills flowing right. A new top bar (format[1]) shows prefix and current command, left-aligned, conditionally. Ghostty gets `macos-titlebar-style = hidden` since it launches straight into tmux. All tmux.conf edits that touch unicode powerline glyphs (U+E0B0 `\ue0b0`, U+F292 `\uf292`) must use Python to avoid glyph stripping.

**Tech Stack:** tmux 3.6a, Python 3 (file edits with unicode), Ghostty config

---

## Color Palette Reference

| Role | Hex |
|------|-----|
| Session island (purple) | `#8350C2` |
| Active tab (lighter purple) | `#9b6ed0` |
| Inactive tabs | inherit `window-status-style` (`fg=#666666`) |
| Prefix indicator | `#f5c211` (amber) |
| Command text | `#888888` |
| Nerd Font terminal icon | `\uf292` |
| Powerline right arrow | `\ue0b0` |

---

## Tab Label Logic

Tabs show the window name (`#W`) when meaningful, else fall back to `[#I]` (index in brackets):

```
#{?#{==:#{window_name},~},[#I],#W}
```

- `~` (home dir) → `[1]`
- `nvim`, `myproject`, custom name → `nvim` / `myproject` / custom name
- `zsh` at non-home path → shows the path component (set by automatic-rename-format)

---

### Task 1: Redesign tmux.conf (Python)

**Files:**
- Modify: `dotFiles/tmux.conf`

This task uses Python because the format strings contain Nerd Font unicode glyphs (`\uf292`, `\ue0b0`) that the Edit tool strips.

**Step 1: Run the Python script**

```python
#!/usr/bin/env python3

ARROW_R = '\ue0b0'   # U+E0B0  powerline right-fill chevron
ICON    = '\uf292'   # U+F292  Nerd Font terminal icon

with open('/Users/jarvis/dotFiles/tmux.conf', 'r', encoding='utf-8') as f:
    content = f.read()

# ── 1. Enable two status rows ────────────────────────────────────────────────
content = content.replace(
    'set -g history-limit 10000',
    'set -g history-limit 10000\nset -g status 2'
)

# ── 2. Redesign active window tab ────────────────────────────────────────────
# Old: purple island shows icon + window index (#I), no adjacent tab segment
OLD_CURRENT = (
    "set -g window-status-current-format "
    "\"#(~/dotFiles/tmux-lang.sh '#{pane_current_path}')"
    f"#[bg=#8350C2,fg=#ffffff] {ICON} #I "
    f"#[bg=default,fg=#8350C2]{ARROW_R}\""
)
# New: purple island shows icon + session name (#S), light-purple active tab flows right
NEW_CURRENT = (
    "set -g window-status-current-format "
    "\"#(~/dotFiles/tmux-lang.sh '#{pane_current_path}')"
    f"#[bg=#8350C2,fg=#ffffff] {ICON} #S "
    f"#[bg=#9b6ed0,fg=#8350C2]{ARROW_R}"
    "#[bg=#9b6ed0,fg=#ffffff,bold] #{?#{==:#{window_name},~},[#I],#W} "
    f"#[bg=default,fg=#9b6ed0]{ARROW_R}\""
)
assert OLD_CURRENT in content, f"Could not find active format to replace:\n{OLD_CURRENT}"
content = content.replace(OLD_CURRENT, NEW_CURRENT)

# ── 3. Redesign inactive window tab ─────────────────────────────────────────
# Old: icon + window index + directory path
OLD_FORMAT = (
    "set -g window-status-format "
    f"\"  {ICON} #I  #(~/dotFiles/tmux-dir.sh '#{'{pane_current_path}'}') \""
)
# New: just the tab label (name or [id]), no icon or directory
NEW_FORMAT = (
    "set -g window-status-format "
    "\"  #{?#{==:#{window_name},~},[#I],#W}  \""
)
assert OLD_FORMAT in content, f"Could not find inactive format to replace:\n{OLD_FORMAT}"
content = content.replace(OLD_FORMAT, NEW_FORMAT)

# ── 4. Add status-format[1] (top row: prefix + command) ─────────────────────
STATUS_FORMAT_LINE = (
    "set -g status-format[1] "
    "\"#[align=left]"
    "#[bg=default,fg=#f5c211,bold]#{?client_prefix, PREFIX ,}"
    "#[nobold,fg=#888888]#{?#{==:#{pane_current_command},zsh},,#{?client_prefix, | , }#{pane_current_command}}\"\n"
)
# Insert before the TPM run line
TPM_LINE = "run '~/.tmux/plugins/tpm/tpm'"
assert TPM_LINE in content, "Could not find TPM run line"
content = content.replace(TPM_LINE, STATUS_FORMAT_LINE + TPM_LINE)

with open('/Users/jarvis/dotFiles/tmux.conf', 'w', encoding='utf-8') as f:
    f.write(content)

print("tmux.conf updated successfully.")
```

Save this as `/tmp/patch_tmux.py` and run:
```bash
python3 /tmp/patch_tmux.py
```

Expected output: `tmux.conf updated successfully.`
If an `AssertionError` fires, the old string wasn't found — read the error, inspect `tmux.conf`, and adjust the `OLD_*` string.

**Step 2: Verify the changes**

```bash
python3 -c "
with open('/Users/jarvis/dotFiles/tmux.conf', encoding='utf-8') as f:
    for line in f:
        if any(k in line for k in ['status 2', 'status-format', 'window-status-current-format', 'window-status-format ']):
            print(repr(line.rstrip()))
"
```

Expected — you should see:
- `'set -g status 2'`
- `'set -g window-status-format "  #{?#{==:#{window_name},~},[#I],#W}  "'`
- A `window-status-current-format` line containing `#S`, `#9b6ed0`, and two `\ue0b0` glyphs
- A `status-format[1]` line containing `client_prefix` and `pane_current_command`

**Step 3: Reload config in a live tmux session**

```bash
tmux source-file ~/.tmux.conf && echo "Reloaded"
```

**Step 4: Smoke test**

In the tmux session:
1. Press `C-a` (prefix) — the top status row should flash `PREFIX` in amber
2. Open `nvim` — the top row should show `nvim` (or `PREFIX | nvim` if prefix held)
3. At home directory — inactive tabs should show `[N]` not `~`
4. At a named directory — tabs show the directory name
5. The center island should show the session name (e.g., `main`), not a number

**Step 5: Commit**

```bash
cd ~/dotFiles && git add tmux.conf
git commit -m "feat: two-row tmux status bar with session island and named tabs"
```

---

### Task 2: Disable Ghostty Native Tabs

**Files:**
- Modify: `dotFiles/ghostty/config`

Since Ghostty launches directly into tmux (`command = /bin/zsh -l -c "tmux new-session -A -s main"`), native Ghostty tabs bypass tmux entirely and create orphan terminal sessions. Disable them.

**Step 1: Add the config option**

Use the Edit tool to add to `dotFiles/ghostty/config`:

```
# Disable native tabs (using tmux for session/tab management)
macos-titlebar-style = hidden
```

Add it after the `window-padding-balance = false` line.

**Step 2: Verify**

```bash
grep 'macos-titlebar' ~/dotFiles/ghostty/config
```

Expected: `macos-titlebar-style = hidden`

**Step 3: Reload Ghostty**

Restart Ghostty (or use `Cmd+Shift+,` to reload config if supported). The native macOS titlebar with tab strip should be gone.

**Step 4: Commit**

```bash
cd ~/dotFiles && git add ghostty/config
git commit -m "chore: disable ghostty native tabs in favor of tmux"
```

---

## Notes for Implementer

- **Unicode chars stripped by Edit/Write tools** — always use Python for `tmux.conf` edits that touch powerline glyphs
- **`#W` = window name** — set by `automatic-rename` (from tmux-sensible) to the last path component or current command
- **`#S` = session name** — set at session creation (`tmux new-session -s main`). Default is a number if unnamed.
- **`client_prefix` updates immediately** on keypress (not bound to `status-interval`), so PREFIX indicator is real-time
- **`pane_current_command`** reflects the foreground process in the active pane
- If the assert fails in Task 1, run `python3 -c "open(...).read()"` and print the raw line to get the exact byte sequence
