-- Personal nvim overrides loaded after AstroNvim.

-- Disable remote-plugin host providers we don't use. Modern Lua plugins don't
-- need them; leaving them on produces :checkhealth noise about missing
-- `neovim` npm/gem/cpan/pip packages.
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0

-- Yank to system clipboard by default.
vim.opt.clipboard = "unnamedplus"

-- Keep cursor away from the edges.
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- Briefly highlight yanked text.
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("yank_highlight", { clear = true }),
  callback = function() vim.highlight.on_yank({ timeout = 150 }) end,
})

-- Copy file path to clipboard. <leader>yp = relative, <leader>yP = absolute.
local function yank_path(absolute)
  local path = absolute and vim.fn.expand("%:p") or vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
  vim.fn.setreg("+", path)
  vim.notify(path, vim.log.levels.INFO)
end
vim.keymap.set("n", "<leader>yp", function() yank_path(false) end, { desc = "Yank relative path" })
vim.keymap.set("n", "<leader>yP", function() yank_path(true) end, { desc = "Yank absolute path" })
