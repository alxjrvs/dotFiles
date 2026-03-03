# AstroNvim v5 Integration Design

## Goal

Replace the current minimal Neovim config (`nvim/init.lua`) with AstroNvim v5, a full-featured Neovim distribution. Track the entire config in the dotfiles repo and symlink the directory to `~/.config/nvim`.

## Approach

Inline the AstroNvim template directly in `nvim/`. AstroNvim itself is a lazy.nvim plugin pulled at runtime; only the bootstrap and user config files live in the repo. This matches the existing dotfiles pattern of "everything in the repo, symlinked out."

## File Structure

```
nvim/
  init.lua                 -- Bootstrap lazy.nvim (from AstroNvim template)
  lua/
    lazy_setup.lua         -- lazy.nvim config, AstroNvim plugin spec
    community.lua          -- AstroCommunity plugin imports
    plugins/
      astrocore.lua        -- Core Neovim options and keymaps
      astrolsp.lua         -- LSP configuration
      treesitter.lua       -- Treesitter language grammars
      mason.lua            -- Mason tool installer (formatters, linters)
      user.lua             -- Additional user plugins
```

## Language Support

Via AstroCommunity packs:
- `astrocommunity.pack.typescript-all-in-one` (TypeScript/JavaScript)
- `astrocommunity.pack.lua` (Lua / Neovim config editing)
- `astrocommunity.pack.html-css` (HTML/CSS)
- `astrocommunity.pack.tailwindcss` (Tailwind CSS)
- `astrocommunity.pack.json` (JSON)

Via Mason:
- prettier (formatter)
- eslint_d (linter)

## install.sh Changes

1. Remove the single-file nvim symlink (`init.lua` -> `~/.config/nvim/init.lua`)
2. Symlink the entire `nvim/` directory to `~/.config/nvim`
3. Handle migration: if `~/.config/nvim/init.lua` is an existing symlink to the old config, remove it and the parent dir before creating the new directory symlink

## Settings

Start fresh with AstroNvim defaults. No keybinding overrides, no custom theme (AstroDark default).

## Out of Scope

- Custom colorscheme
- Copilot/AI integration plugins
- Porting old keybindings (AstroNvim defaults cover them)
