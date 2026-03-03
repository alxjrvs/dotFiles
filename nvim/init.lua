-- init.lua — minimal neovim config (no plugins)
-- Works with: Neovim 0.9+, zsh + vi keybindings, Ghostty

-- ── Leader ────────────────────────────────────────────────────────
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ── Options ───────────────────────────────────────────────────────
local o = vim.opt

-- Line numbers
o.number = true
o.relativenumber = true

-- 2-space tabs, smart indent
o.tabstop = 2
o.shiftwidth = 2
o.softtabstop = 2
o.expandtab = true
o.smartindent = true

-- Search: case-insensitive unless uppercase used
o.ignorecase = true
o.smartcase = true

-- System clipboard
o.clipboard = "unnamedplus"

-- No swap files (git handles history)
o.swapfile = false
o.backup = false
o.undofile = true

-- UI
o.cursorline = true
o.termguicolors = true
o.signcolumn = "yes"
o.scrolloff = 8
o.sidescrolloff = 8
o.showmode = false

-- Splits open in sensible directions
o.splitbelow = true
o.splitright = true

-- Faster updates
o.updatetime = 250
o.timeoutlen = 300

-- Minimal status line (built-in)
o.laststatus = 2
o.statusline = " %f %m%r%= %y  %l:%c  %p%% "

-- ── Keymaps ───────────────────────────────────────────────────────
local map = vim.keymap.set

-- Clear search highlight with Esc
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Window navigation with Ctrl+hjkl
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to below window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to above window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Stay in visual mode when indenting
map("v", "<", "<gv", { desc = "Indent left and reselect" })
map("v", ">", ">gv", { desc = "Indent right and reselect" })

-- ── Autocommands ──────────────────────────────────────────────────
local au = vim.api.nvim_create_autocmd

-- Highlight text on yank
au("TextYankPost", {
  callback = function() vim.highlight.on_yank({ timeout = 200 }) end,
})

-- Remove trailing whitespace on save
au("BufWritePre", {
  pattern = "*",
  command = [[%s/\s\+$//e]],
})
