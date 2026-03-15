---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
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
      "python",
      "dockerfile",
      "yaml",
      "toml",
    },
  },
}
