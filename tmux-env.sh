#!/bin/sh
# tmux-env.sh <pane_current_path>
# Outputs left-pointing () tmux format segments for current language env.
# Ends with transition arrow to date segment (#4a4a4a). If no env, just the arrow.

dir="$1"
cd "$dir" 2>/dev/null || { printf '#[fg=#4a4a4a,bg=default]'; exit 0; }

# Node
if [ -f "package.json" ] || [ -f ".node-version" ] || [ -f ".nvmrc" ]; then
  ver=$(node -v 2>/dev/null)
  if [ -n "$ver" ]; then
    printf '#[fg=#2d6b2e,bg=default]#[bg=#2d6b2e,fg=#ffffff,bold] node #[fg=#3C873A,bg=#2d6b2e]#[bg=#3C873A,fg=#ffffff,bold] %s #[fg=#4a4a4a,bg=#3C873A]' "$ver"
    exit 0
  fi
fi

# Python
if [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f ".python-version" ]; then
  ver=$(python3 --version 2>/dev/null | awk '{print $2}')
  if [ -n "$ver" ]; then
    printf '#[fg=#2a5a85,bg=default]#[bg=#2a5a85,fg=#ffffff,bold] python #[fg=#3776AB,bg=#2a5a85]#[bg=#3776AB,fg=#ffffff,bold] %s #[fg=#4a4a4a,bg=#3776AB]' "$ver"
    exit 0
  fi
fi

# Rust
if [ -f "Cargo.toml" ]; then
  ver=$(rustc --version 2>/dev/null | awk '{print $2}')
  if [ -n "$ver" ]; then
    printf '#[fg=#9e3220,bg=default]#[bg=#9e3220,fg=#ffffff,bold] rust #[fg=#CE422B,bg=#9e3220]#[bg=#CE422B,fg=#ffffff,bold] %s #[fg=#4a4a4a,bg=#CE422B]' "$ver"
    exit 0
  fi
fi

# Ruby
if [ -f "Gemfile" ] || [ -f ".ruby-version" ]; then
  ver=$(ruby --version 2>/dev/null | awk '{print $2}')
  if [ -n "$ver" ]; then
    printf '#[fg=#9c2822,bg=default]#[bg=#9c2822,fg=#ffffff,bold] ruby #[fg=#CC342D,bg=#9c2822]#[bg=#CC342D,fg=#ffffff,bold] %s #[fg=#4a4a4a,bg=#CC342D]' "$ver"
    exit 0
  fi
fi

# No env detected — just the transition arrow into date
printf '#[fg=#4a4a4a,bg=default]'
