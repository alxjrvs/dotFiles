# Dedup PATH/path entries, keeping the first (highest-priority) occurrence.
#
# Note what this does and does not buy. It dedups; it never reorders. This comment used to claim
# the prepend below "survives macOS path_helper" — it does not, and that sentence is a large part
# of why the resulting breakage went unnoticed for so long. In a LOGIN shell, /etc/zprofile runs
# path_helper, which rebuilds PATH from scratch and demotes everything set here below the system
# paths. What `typeset -U` actually buys is making the corrective re-prepend at the end of
# `.zprofile` free: the duplicate entry it creates collapses back to one.
typeset -U path PATH

# mise shims. Sufficient on its own for non-login shells (`zsh -c`, most subprocesses). A LOGIN
# shell additionally needs the re-prepend at the end of `.zprofile` — see the comment there for
# the full mechanism and the version skew it fixes.
export PATH="$HOME/.local/share/mise/shims:$PATH"
