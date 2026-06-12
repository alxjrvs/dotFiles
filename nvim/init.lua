-- nvim/init.lua — minimal, plugin-free Neovim starter config.
--
-- Synced to ~/.config/nvim/init.lua by `dot sync --only=nvim`.
-- All LSP/formatter binaries live in mise.toml so they're on PATH in every shell.
-- Requires Neovim 0.11+ (native vim.lsp.config / vim.lsp.enable, no lspconfig).

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
opt.termguicolors = true
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
map("n", "grn", vim.lsp.buf.rename, { desc = "LSP rename" })
map("n", "gra", vim.lsp.buf.code_action, { desc = "LSP code action" })
map("n", "grr", vim.lsp.buf.references, { desc = "LSP references" })
map("n", "gd", vim.lsp.buf.definition, { desc = "LSP definition" })
map("n", "K", vim.lsp.buf.hover, { desc = "LSP hover" })

-- ── Language servers (native, no lspconfig) ────────────────────────────────
-- One vim.lsp.config block per language server; enabled together below.
vim.lsp.config("rust_analyzer", {
  cmd = { "rust-analyzer" },
  filetypes = { "rust" },
  root_markers = { "Cargo.toml", ".git" },
})

vim.lsp.config("bashls", {
  cmd = { "bash-language-server", "start" },
  filetypes = { "sh", "bash" },
  root_markers = { ".git" },
})

vim.lsp.config("ts_ls", {
  cmd = { "typescript-language-server", "--stdio" },
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
  root_markers = { "package.json", "tsconfig.json", ".git" },
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

vim.lsp.enable({ "rust_analyzer", "bashls", "ts_ls", "marksman", "taplo" })

-- ── Format on save ─────────────────────────────────────────────────────────
-- External formatters per filetype. Buffers are piped through the formatter's
-- stdin; the buffer is left untouched on error.
local function pipe_format(cmd)
  local view = vim.fn.winsaveview()
  local input = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  local output = vim.fn.system(cmd, input)
  if vim.v.shell_error ~= 0 then
    vim.notify("formatter failed: " .. output, vim.log.levels.WARN)
    return
  end
  local lines = vim.split(output, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.fn.winrestview(view)
end

local formatters = {
  sh = { "shfmt", "-i", "2", "-ci", "-sr" },
  bash = { "shfmt", "-i", "2", "-ci", "-sr" },
  typescript = { "prettier", "--parser", "typescript" },
  typescriptreact = { "prettier", "--parser", "typescript" },
  javascript = { "prettier", "--parser", "babel" },
  javascriptreact = { "prettier", "--parser", "babel" },
  toml = { "taplo", "fmt", "-" },
}

vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("FormatOnSave", { clear = true }),
  callback = function(args)
    local ft = vim.bo[args.buf].filetype
    local cmd = formatters[ft]
    if cmd then
      pipe_format(cmd)
    elseif ft == "rust" then
      vim.lsp.buf.format({ bufnr = args.buf })
    end
  end,
})
