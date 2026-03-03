# AstroNvim v5 Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the minimal Neovim config with AstroNvim v5, tracked inline in the dotfiles repo.

**Architecture:** The AstroNvim template (bootstrap + user config) lives in `nvim/` and is symlinked as a directory to `~/.config/nvim`. AstroNvim itself and all plugins are pulled at runtime by lazy.nvim. Language packs come from AstroCommunity.

**Tech Stack:** Neovim, AstroNvim v5, lazy.nvim, AstroCommunity, Mason, Treesitter

---

### Task 1: Remove old nvim/init.lua and create directory structure

**Files:**
- Delete: `nvim/init.lua`
- Create: `nvim/lua/plugins/` (directory)

**Step 1: Delete the old minimal config**

```bash
rm nvim/init.lua
```

**Step 2: Create the new directory structure**

```bash
mkdir -p nvim/lua/plugins
```

**Step 3: Commit**

```bash
git add nvim/init.lua
git commit -m "chore: remove minimal nvim config in preparation for AstroNvim"
```

---

### Task 2: Create AstroNvim bootstrap init.lua

**Files:**
- Create: `nvim/init.lua`

**Step 1: Write the bootstrap file**

This is the standard AstroNvim template bootstrap. It clones lazy.nvim if missing, then loads `lazy_setup` and `polish`.

```lua
-- This file simply bootstraps the installation of Lazy.nvim and then calls other files for execution
-- This file doesn't necessarily need to be touched, BE CAUTIOUS editing this file and proceed at your own risk.
local lazypath = vim.env.LAZY or vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not (vim.env.LAZY or (vim.uv or vim.loop).fs_stat(lazypath)) then
  -- stylua: ignore
  local result = vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
  if vim.v.shell_error ~= 0 then
    -- stylua: ignore
    vim.api.nvim_echo({ { ("Error cloning lazy.nvim:\n%s\n"):format(result), "ErrorMsg" }, { "Press any key to exit...", "MoreMsg" } }, true, {})
    vim.fn.getchar()
    vim.cmd.quit()
  end
end

vim.opt.rtp:prepend(lazypath)

-- validate that lazy is available
if not pcall(require, "lazy") then
  -- stylua: ignore
  vim.api.nvim_echo({ { ("Unable to load lazy from: %s\n"):format(lazypath), "ErrorMsg" }, { "Press any key to exit...", "MoreMsg" } }, true, {})
  vim.fn.getchar()
  vim.cmd.quit()
end

require "lazy_setup"
require "polish"
```

**Step 2: Commit**

```bash
git add nvim/init.lua
git commit -m "feat(nvim): add AstroNvim bootstrap init.lua"
```

---

### Task 3: Create lazy_setup.lua

**Files:**
- Create: `nvim/lua/lazy_setup.lua`

**Step 1: Write lazy_setup.lua**

This configures lazy.nvim with AstroNvim v5 as the core distribution. Note `version = "^5"` pins to v5.x.

```lua
require("lazy").setup({
  {
    "AstroNvim/AstroNvim",
    version = "^5",
    import = "astronvim.plugins",
    opts = {
      mapleader = " ",
      maplocalleader = ",",
      icons_enabled = true,
      pin_plugins = nil,
      update_notifications = true,
    },
  },
  { import = "community" },
  { import = "plugins" },
} --[[@as LazySpec]], {
  install = { colorscheme = { "astrotheme", "habamax" } },
  ui = { backdrop = 100 },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "zipPlugin",
      },
    },
  },
} --[[@as LazyConfig]])
```

**Step 2: Commit**

```bash
git add nvim/lua/lazy_setup.lua
git commit -m "feat(nvim): add lazy.nvim setup with AstroNvim v5"
```

---

### Task 4: Create community.lua with language packs

**Files:**
- Create: `nvim/lua/community.lua`

**Step 1: Write community.lua**

This imports AstroCommunity and the full web stack language packs.

```lua
---@type LazySpec
return {
  "AstroNvim/astrocommunity",
  { import = "astrocommunity.pack.lua" },
  { import = "astrocommunity.pack.typescript-all-in-one" },
  { import = "astrocommunity.pack.html-css" },
  { import = "astrocommunity.pack.tailwindcss" },
  { import = "astrocommunity.pack.json" },
}
```

**Step 2: Commit**

```bash
git add nvim/lua/community.lua
git commit -m "feat(nvim): add AstroCommunity language packs for full web stack"
```

---

### Task 5: Create polish.lua

**Files:**
- Create: `nvim/lua/polish.lua`

**Step 1: Write polish.lua**

This file runs last and is for pure Lua code that doesn't fit elsewhere. Start with an empty stub.

```lua
-- This file is run last and is a good place for additional Lua code
-- that doesn't fit in other configuration files.
```

**Step 2: Commit**

```bash
git add nvim/lua/polish.lua
git commit -m "feat(nvim): add polish.lua stub"
```

---

### Task 6: Create plugin config files — treesitter.lua

**Files:**
- Create: `nvim/lua/plugins/treesitter.lua`

**Step 1: Write treesitter.lua**

Install parsers for the full web stack plus Lua/Vim for config editing.

```lua
---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "lua",
      "vim",
      "vimdoc",
      "javascript",
      "typescript",
      "tsx",
      "html",
      "css",
      "json",
      "jsonc",
      "markdown",
      "markdown_inline",
      "bash",
    },
  },
}
```

**Step 2: Commit**

```bash
git add nvim/lua/plugins/treesitter.lua
git commit -m "feat(nvim): add Treesitter config with web stack parsers"
```

---

### Task 7: Create plugin config files — mason.lua

**Files:**
- Create: `nvim/lua/plugins/mason.lua`

**Step 1: Write mason.lua**

Auto-install language servers, formatters, and linters via Mason.

```lua
---@type LazySpec
return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    opts = {
      ensure_installed = {
        "lua-language-server",
        "stylua",
        "prettier",
        "eslint_d",
        "tree-sitter-cli",
      },
    },
  },
}
```

**Step 2: Commit**

```bash
git add nvim/lua/plugins/mason.lua
git commit -m "feat(nvim): add Mason config for formatters and linters"
```

---

### Task 8: Create linter/formatter config files

**Files:**
- Create: `nvim/.stylua.toml`
- Create: `nvim/.luarc.json`
- Create: `nvim/.neoconf.json`
- Create: `nvim/selene.toml`

These are the standard AstroNvim template support files for Lua tooling.

**Step 1: Write .stylua.toml**

```toml
column_width = 120
line_endings = "Unix"
indent_type = "Spaces"
indent_width = 2
quote_style = "AutoPreferDouble"
call_parentheses = "None"
collapse_simple_statement = "Always"
```

**Step 2: Write .luarc.json**

```json
{
  "format.enable": false
}
```

**Step 3: Write .neoconf.json**

```json
{
  "neodev": {
    "library": {
      "enabled": true,
      "plugins": true
    }
  },
  "neoconf": {
    "plugins": {
      "lua_ls": {
        "enabled": true
      }
    }
  },
  "lspconfig": {
    "lua_ls": {
      "Lua.format.enable": false
    }
  }
}
```

**Step 4: Write selene.toml**

```toml
std = "neovim"

[rules]
global_usage = "allow"
if_same_then_else = "allow"
incorrect_standard_library_use = "allow"
mixed_table = "allow"
multiple_statements = "allow"
```

**Step 5: Commit**

```bash
git add nvim/.stylua.toml nvim/.luarc.json nvim/.neoconf.json nvim/selene.toml
git commit -m "chore(nvim): add Lua tooling config files from AstroNvim template"
```

---

### Task 9: Update install.sh — change nvim symlink from file to directory

**Files:**
- Modify: `install.sh` (lines 148-150, the nvim symlink section)

**Step 1: Read the current nvim symlink section in install.sh**

Current code (around line 148-150):
```bash
# Neovim config
mkdir -p "$HOME/.config/nvim"
link "$DOTFILES_DIR/nvim/init.lua"        "$HOME/.config/nvim/init.lua"         "nvim/init.lua"
```

**Step 2: Replace with directory symlink and migration logic**

```bash
# Neovim config (AstroNvim — symlink entire directory)
# Migration: remove old single-file symlink if present
if [ -L "$HOME/.config/nvim/init.lua" ] && [ ! -L "$HOME/.config/nvim" ]; then
  warn "Removing old nvim/init.lua symlink (migrating to AstroNvim)"
  rm "$HOME/.config/nvim/init.lua"
  rmdir "$HOME/.config/nvim" 2>/dev/null || true
fi
link "$DOTFILES_DIR/nvim"                 "$HOME/.config/nvim"                  "nvim (AstroNvim)"
```

Key changes:
- No longer creates `~/.config/nvim` directory — the symlink replaces it
- Migration block handles the old `init.lua` symlink
- `link()` now points the entire `nvim/` directory

**Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): switch nvim symlink from single file to AstroNvim directory"
```

---

### Task 10: Update CLAUDE.md — reflect AstroNvim change

**Files:**
- Modify: `CLAUDE.md` (the project-level one at repo root)

**Step 1: Update the nvim symlink row in the table**

Change:
```
| `nvim/init.lua` | `~/.config/nvim/init.lua` |
```

To:
```
| `nvim/` | `~/.config/nvim` (AstroNvim v5 — entire directory) |
```

**Step 2: Update the Shell Stack / Neovim section if present**

No dedicated neovim section exists currently, so no further changes needed.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md to reflect AstroNvim integration"
```

---

### Task 11: Apply the symlink locally and verify

**Step 1: Remove old symlink and apply new one**

```bash
# Remove old file symlink
rm -f ~/.config/nvim/init.lua
rmdir ~/.config/nvim 2>/dev/null || true

# Create new directory symlink
ln -sfn ~/dotFiles/nvim ~/.config/nvim
```

**Step 2: Launch Neovim and verify AstroNvim bootstraps**

```bash
nvim --headless "+Lazy! sync" +qa
```

Expected: lazy.nvim clones, AstroNvim installs, all plugins download. Exit code 0.

**Step 3: Verify Treesitter parsers install**

```bash
nvim --headless "+TSInstallSync lua vim javascript typescript tsx html css json" +qa
```

**Step 4: Commit any lockfiles generated**

If lazy.nvim generates a `lazy-lock.json` in `nvim/`:

```bash
git add nvim/lazy-lock.json
git commit -m "chore(nvim): add lazy-lock.json"
```

---

### Task 12: Push all changes

**Step 1: Push to remote**

```bash
git push
```
