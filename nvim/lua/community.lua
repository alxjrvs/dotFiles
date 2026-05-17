---@type LazySpec
-- Viewer mode: no language packs imported (each pack pulls in LSP servers,
-- formatters, and linters that we disable in plugins/disable.lua).
-- The AstroCommunity wrapper itself is retained as a no-op so re-enabling
-- a pack is a one-line addition.
return {
  "AstroNvim/astrocommunity",
}
