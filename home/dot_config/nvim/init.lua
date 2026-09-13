-- nvim/init.lua: $EDITOR, plugin-free. Editing is VS Code's and the agent's.
vim.g.mapleader = " "

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

local map = vim.keymap.set
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit" })
map("n", "<esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
