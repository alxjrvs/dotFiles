-- nvim/init.lua — plugin-free. Neovim 0.11+ native LSP (vim.lsp.config / vim.lsp.enable);
-- the servers and shfmt come from Homebrew.

-- ── Options ──────────────────────────────────────────────────────────────
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = true
opt.clipboard = "unnamedplus"
opt.undofile = true
opt.signcolumn = "yes"
opt.scrolloff = 5
opt.mouse = "a"
opt.splitright = true
opt.splitbelow = true
opt.wrap = false

-- ── Keymaps ──────────────────────────────────────────────────────────────
local map = vim.keymap.set
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit" })
map("n", "<esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
-- grn / gra / grr / K are Neovim's own defaults since 0.11, and mapping K by hand
-- suppresses the default hover it duplicates; `gd` is not a default.
map("n", "gd", vim.lsp.buf.definition, { desc = "LSP definition" })

-- ── Language servers (native, no lspconfig) ────────────────────────────────
-- One vim.lsp.config block per language server; enabled together below.
vim.lsp.config("rust_analyzer", {
  cmd = { "rust-analyzer" },
  filetypes = { "rust" },
  root_markers = { "Cargo.toml", ".git" },
})

-- Formats through shfmt when it is on PATH; these two flags match the old `shfmt -ci -sr`.
vim.lsp.config("bashls", {
  cmd = { "bash-language-server", "start" },
  filetypes = { "sh", "bash" },
  root_markers = { ".git" },
  settings = { bashIde = { shfmt = { caseIndent = true, spaceRedirects = true } } },
})

vim.lsp.config("ts_ls", {
  cmd = { "typescript-language-server", "--stdio" },
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
  root_markers = { "package.json", "tsconfig.json", ".git" },
})

-- Formatter for JS/TS; ts_ls stays for everything else and is filtered out of format-on-save.
vim.lsp.config("biome", {
  cmd = { "biome", "lsp-proxy" },
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "json", "jsonc" },
  root_markers = { "biome.json", "biome.jsonc", "package.json", ".git" },
})

vim.lsp.config("marksman", {
  cmd = { "marksman", "server" },
  filetypes = { "markdown" },
  root_markers = { ".marksman.toml", ".git" },
})

vim.lsp.config("taplo", {
  cmd = { "taplo", "lsp", "stdio" },
  filetypes = { "toml" },
  root_markers = { ".git" },
})

vim.lsp.enable({ "rust_analyzer", "bashls", "ts_ls", "biome", "marksman", "taplo" })

-- ── Format on save: every attached server that can, except ts_ls (biome owns JS/TS) ────────
vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("FormatOnSave", { clear = true }),
  callback = function(args)
    vim.lsp.buf.format({
      bufnr = args.buf,
      filter = function(client)
        return client.name ~= "ts_ls"
      end,
    })
  end,
})
