FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
$(brew --prefix asdf)/libexec/asdf.sh
eval "$(/opt/homebrew/bin/brew shellenv)"
