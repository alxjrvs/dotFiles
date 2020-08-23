## A Glimpse Into.... The World That's Coming!


## Command Line Navigation
alias ..='cd ..'
alias ls='ls -AFGp'
alias work='cd ~/Code'

## Enable Zsh Completion
fpath=(/usr/local/share/zsh-completions $fpath)

## Set Colors
export TERM=screen-256color

## Set Editor
export VISUAL=vim
export EDITOR="$VISUAL"
export GEM_EDITOR="$VISUAL"

## Setup 
source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"

export ANDROID_HOME=/Users/alexjarvis/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools

export JAVA_HOME=`/usr/libexec/java_home -v 1.8`

. /usr/local/opt/asdf/asdf.sh
. /usr/local/opt/asdf/etc/bash_completion.d/asdf.bash

eval "$(direnv hook zsh)"
