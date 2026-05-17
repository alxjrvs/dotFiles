---@type LazySpec
-- Viewer mode: disable AstroNvim's LSP / Mason / formatting / completion /
-- debug cluster. Claude Code owns editing; nvim is for fast browsing,
-- reading, and yanking only. Keep treesitter (syntax), Snacks (UI/picker),
-- neo-tree, gitsigns, which-key, toggleterm.
--
-- If you ever want LSP back for a session: `:Lazy enable <plugin>` and
-- :Lazy load <plugin>. Or just delete this file.
return {
  -- LSP
  { "neovim/nvim-lspconfig",                     enabled = false },
  { "AstroNvim/astrolsp",                        enabled = false },
  { "antosha417/nvim-lsp-file-operations",       enabled = false },
  { "yioneko/nvim-vtsls",                        enabled = false },
  { "folke/lazydev.nvim",                        enabled = false },
  { "folke/neoconf.nvim",                        enabled = false },
  { "b0o/SchemaStore.nvim",                      enabled = false },

  -- Mason (LSP/DAP/formatter installer)
  { "williamboman/mason.nvim",                   enabled = false },
  { "mason-org/mason-lspconfig.nvim",            enabled = false },
  { "WhoIsSethDaniel/mason-tool-installer.nvim", enabled = false },
  { "jay-babu/mason-null-ls.nvim",               enabled = false },
  { "jay-babu/mason-nvim-dap.nvim",              enabled = false },

  -- Formatting / linting
  { "nvimtools/none-ls.nvim",                    enabled = false },

  -- Completion + snippets (LSP-driven)
  { "Saghen/blink.cmp",                          enabled = false },
  { "Saghen/blink.compat",                       enabled = false },
  { "rcarriga/cmp-dap",                          enabled = false },
  { "L3MON4D3/LuaSnip",                          enabled = false },
  { "rafamadriz/friendly-snippets",              enabled = false },

  -- Debugging
  { "mfussenegger/nvim-dap",                     enabled = false },
  { "rcarriga/nvim-dap-ui",                      enabled = false },

  -- LSP-companion UI / helpers
  { "stevearc/aerial.nvim",                      enabled = false },
  { "RRethy/vim-illuminate",                     enabled = false },
  { "vuki656/package-info.nvim",                 enabled = false },
  { "dmmulroy/tsc.nvim",                         enabled = false },
  { "sigmasd/deno-nvim",                         enabled = false },
}
