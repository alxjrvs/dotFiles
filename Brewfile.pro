# Brewfile.pro — Pro-specific brew/cask additions.
#
# Installed AFTER the shared `Brewfile` on the M2 Mac Pro. Use for
# casks / formulae that only the Pro needs (e.g. heavier GPU-bound
# tools, virtualization, anything desk-bound).
#
# To dry-run the Air's overlay locally:
#   dotctl sync --only=brew --host=air
