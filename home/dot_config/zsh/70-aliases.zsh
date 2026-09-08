# Only what is actually typed. Measured against atuin's history (the source of
# truth per zsh/60-tools.zsh), and 15 of the 23 aliases here had never been
# typed once. The zeros are real rather than a recording gap: `ls` at 141 and
# `..` at 143 prove short commands are captured.
#
# The deleted ones were all the same shape — a two-letter contraction of a git
# subcommand (`ga`, `gaa`, `gb`, `gc`, `gds`, `gl`), an eza flag set (`la`,
# `ll`, `lt`, `tree`), or a single letter (`b`, `c`, `q`, `vi`). Each looks
# useful and none survived contact: the full command is short enough, or a tool
# with its own interface won.
#
# Counts are stated here as a dated observation, not as a live claim — nothing
# checks them, so they describe 2026-08-31 and nothing else.

# Git — gpr 157, gco 82, gs 79, gp 40, gd 2
alias gs="git status"
alias gp="git push"
alias gpr='git pull --rebase'
alias gco='git checkout'
alias gd="git diff"

# Navigation — `..` 143
alias ..="cd .."

# Enhanced tools — ls 141. `cat` stays POSIX cat.
alias ls="eza --icons --group-directories-first"

# Editor — vim 11
alias vim="nvim"
