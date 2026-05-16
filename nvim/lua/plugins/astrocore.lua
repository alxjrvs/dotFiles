---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@param opts AstroCoreOpts
  opts = function(_, opts)
    -- AstroNvim sets diagnostics.jump = { float = true } for nvim 0.11+.
    -- That key is deprecated on nvim 0.12 (replaced by on_jump callback).
    -- Replicate the old auto-open-float behavior using the new API to avoid
    -- the deprecation warning.
    if opts.diagnostics and opts.diagnostics.jump then
      opts.diagnostics.jump = {
        on_jump = function() vim.diagnostic.open_float({ scope = "cursor" }) end,
      }
    end
  end,
}
