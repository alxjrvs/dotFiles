#!/bin/bash
# chmod u+x install.sh
# ./install.sh

echo "Distributing dotFiles...."

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
  echo 'eval "$($(brew --prefix)/bin/brew shellenv)"' >> ~/.zprofile
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
asdf install nodejs 16.9.0
asdf global nodejs 16.9.0

echo "Copying .asdfrc..."
ln -sfn ~/dotFiles/.asdfrc ~/.asdfrc

"\n. $(brew --prefix asdf)/asdf.sh" >> .zprofile
"\n. $(brew --prefix asdf)/etc/bash_completion.d/asdf.bash" >> ~/.bash_profile

echo "Installing Yarn..."
npm install --global yarn

echo "GH auth login"
gh auth login
