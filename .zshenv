# Dedup PATH/path entries, keeping the first (highest-priority) occurrence.
#
# It dedups; it never reorders. In a LOGIN shell, /etc/zprofile runs path_helper, which rebuilds
# PATH from scratch and demotes everything set here below the system paths. What `typeset -U`
# buys is making the corrective re-prepend at the end of `.zprofile` free: the duplicate entry
# it creates collapses back to one.
typeset -U path PATH

# mise shims. Sufficient on its own for non-login shells (`zsh -c`, most subprocesses). A LOGIN
# shell additionally needs the re-prepend at the end of `.zprofile` — see the comment there for
# the full mechanism and the version skew it fixes.
export PATH="$HOME/.local/share/mise/shims:$PATH"
