#!/bin/bash
# chmod u+x install.sh
# ./install.sh

echo "Distributing dotFiles...."
echo "Copying .zshrc..."
ln -sfn ~/dotFiles/.zshrc ~/.zshrc
echo "Installing OhMyZsh..."
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

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

echo "Copying .asdfrc..."
ln -sfn ~/dotFiles/.asdfrc ~/.asdfrc
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
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "Running brew bundle..."
brew bundle

echo "Installing Ruby..."
asdf plugin add ruby
asdf install ruby 3.0.3
asdf global ruby 3.0.3

echo "Installing Nodejs..."
asdf plugin add nodejs
asdf install nodejs 16.9.0
asdf global nodejs 16.9.0

echo "GH auth login"
gh auth login
