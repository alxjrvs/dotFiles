#!/bin/bash
# chmod u+x install.sh
# ./install.sh

echo "Distributing dotFiles...."
echo "Copying .zshrc..."
ln -s ~/dotFiles/.zshrc ~/.zshrc
echo "Copying .asdfrc..."
ln -s ~/dotFiles/.asdfrc ~/.asdfrc
echo "Copying .gitconfig..."
ln -s ~/dotFiles/.gitconfig ~/.gitconfig
echo "Copying .p10k.zsh..."
ln -s ~/dotFiles/.p10k.zsh ~/.p10k.zsh
echo "Installing breww.."
bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo "Installing brew fonts..."
brew tap homebrew/cask-fonts
brew install --cask font-fira-code
echo "Install PostgreSql"
brew install postgresql
brew services start postgresql
