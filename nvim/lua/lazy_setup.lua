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
  -- We don't use any plugins that depend on luarocks, so disable Lazy's
  -- rocks integration. Eliminates the hererocks Lua 5.1 / luarocks warnings.
  rocks = { enabled = false },
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
