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
echo "Copying .tmux.conf..."
ln -s ~/dotFiles/.tmux.conf ~/.tmux.conf
echo "Copying neovim setup"
mkdir -p ~/.config/nvim
ln -s ~/dotFiles/nvim/coc-settings.json  ~/.config/nvim/coc-settings.json
ln -s ~/dotFiles/nvim/init.vim  ~/.config/nvim/init.vim
