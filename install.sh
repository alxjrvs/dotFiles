#!/bin/bash
# chmod u+x install.sh
# ./install.sh

echo "Distributing dotFiles...."
echo "Copying .zshrc..."
ln -s ~/dotFiles/.zshrc ~/.zshrc
echo "Installing OhMyZsh..."
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
echo "Copying .asdfrc..."
ln -s ~/dotFiles/.asdfrc ~/.asdfrc
echo "Copying .gitconfig..."
ln -s ~/dotFiles/.gitconfig ~/.gitconfig
echo "Copying .p10k.zsh..."
ln -s ~/dotFiles/.p10k.zsh ~/.p10k.zsh
echo "Installing breww.."
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo "Run brew bundle once setup concludes. Welcome to Mac!"
