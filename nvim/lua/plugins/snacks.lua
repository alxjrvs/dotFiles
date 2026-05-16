---@type LazySpec
return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    -- Disable image rendering. Requires magick/ghostscript/tectonic/mmdc and
    -- kitty graphics protocol; not used for plain code editing.
    opts.image = { enabled = false }

    -- Make Snacks own the stdlib UI primitives — fixes "vim.ui.input/select is
    -- not set to Snacks.*" errors in :checkhealth.
    opts.input = vim.tbl_deep_extend("force", opts.input or {}, { enabled = true })
    opts.picker = vim.tbl_deep_extend("force", opts.picker or {}, { enabled = true })

    -- Enable the QoL modules AstroNvim leaves off by default.
    opts.bigfile = { enabled = true }
    opts.quickfile = { enabled = true }
    opts.scroll = { enabled = true }
    opts.statuscolumn = { enabled = true }
    opts.words = { enabled = true }

    return opts
  end,
  init = function()
    -- Wire UI primitives explicitly in case Snacks' auto-wire is suppressed.
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        local ok_snacks, snacks = pcall(require, "snacks")
        if not ok_snacks then return end
        if snacks.input then vim.ui.input = snacks.input.input end
        if snacks.picker and snacks.picker.select then vim.ui.select = snacks.picker.select end
      end,
    })
  end,
}
