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
        "pyright",
        "bash-language-server",
      },
    },
  },
}
