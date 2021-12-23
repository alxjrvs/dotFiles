#!/bin/bash
# chmod u+x install.sh
# ./install.sh

echo "Distributing dotFiles...."

echo "Installing OhMyZsh..."
if [ ! -f ${-~/.oh-my-zsh} ]
then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "Zsh already installed, Skipping"
fi

echo "Setting up Zsh Plugins..."
if [ ! -f ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions ]
then
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
else
    echo "Zsh Suggestions already installed, Skipping"
fi

if [ ! -f f ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-z ]
then
  git clone https://github.com/agkozak/zsh-z ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-z
else
    echo "Zsh-z already installed, skipping"
fi

echo "Copying .gitconfig..."
ln -sfn ~/dotFiles/.gitconfig ~/.gitconfig

exists()
{
  command -v "$1" >/dev/null 2>&1
}

if ! exists brew
then
  echo "Installing brew.."
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$($(brew --prefix)/bin/brew shellenv)"
fi

echo "Running brew bundle..."
brew bundle

echo "Installing Ruby..."
asdf plugin add ruby
asdf install ruby 3.0.3
asdf global ruby 3.0.3

echo "Installing Nodejs..."
asdf plugin add nodejs
asdf install nodejs 17.3.0
asdf global nodejs 17.3.0

echo "Copying .zshrc..."
ln -sfn ~/dotFiles/.zshrc ~/.zshrc

echo "Copying .zprofile..."
ln -sfn ~/dotFiles/.zprofile ~/.zprofile

echo "Copying .tool-versions..."
ln -sfn ~/dotFiles/.tool-versions ~/.tool-versions

echo "Copying .default-npm-packages..."
ln -sfn ~/dotFiles/.default-npm-packages ~/.default-npm-packages

echo "Copying .asdfrc..."
ln -sfn ~/dotFiles/.asdfrc ~/.asdfrc

echo "Installing Yarn..."
npm install --global yarn

echo "GH auth login"
gh auth login

eval "git clone https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z"
eval "git clone https://github.com/kiurchv/asdf.plugin.zsh $ZSH_CUSTOM/plugins/asdf"
eval "$(brew --prefix)/opt/fzf/install"
