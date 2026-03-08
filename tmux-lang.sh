#!/bin/sh
# tmux-lang.sh <pane_current_path>
# Outputs lang section to the LEFT of the window-number island.
# No lang: just the island opening arrow (\xe2\x97\x84).
# With lang: full lang section flowing into the island via left-facing arrows.

dir="$1"
ISLAND="#8350C2"

cd "$dir" 2>/dev/null || { printf '#[bg=default,fg=%s]' "$ISLAND"; exit 0; }

# Node
if [ -f "package.json" ] || [ -f ".node-version" ] || [ -f ".nvmrc" ]; then
  ver=$(node -v 2>/dev/null)
  if [ -n "$ver" ]; then
    printf '#[bg=default,fg=#2d6b2e]#[bg=#2d6b2e,fg=#ffffff,bold] node #[fg=#2d6b2e,bg=#3C873A]#[bg=#3C873A,fg=#ffffff,bold] %s #[fg=#3C873A,bg=%s]' "$ver" "$ISLAND"
    exit 0
  fi
fi

# Python
if [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f ".python-version" ]; then
  ver=$(python3 --version 2>/dev/null | awk '{print $2}')
  if [ -n "$ver" ]; then
    printf '#[bg=default,fg=#2a5a85]#[bg=#2a5a85,fg=#ffffff,bold] python #[fg=#2a5a85,bg=#3776AB]#[bg=#3776AB,fg=#ffffff,bold] %s #[fg=#3776AB,bg=%s]' "$ver" "$ISLAND"
    exit 0
  fi
fi

# Rust
if [ -f "Cargo.toml" ]; then
  ver=$(rustc --version 2>/dev/null | awk '{print $2}')
  if [ -n "$ver" ]; then
    printf '#[bg=default,fg=#9e3220]#[bg=#9e3220,fg=#ffffff,bold] rust #[fg=#9e3220,bg=#CE422B]#[bg=#CE422B,fg=#ffffff,bold] %s #[fg=#CE422B,bg=%s]' "$ver" "$ISLAND"
    exit 0
  fi
fi

# Ruby
if [ -f "Gemfile" ] || [ -f ".ruby-version" ]; then
  ver=$(ruby --version 2>/dev/null | awk '{print $2}')
  if [ -n "$ver" ]; then
    printf '#[bg=default,fg=#9c2822]#[bg=#9c2822,fg=#ffffff,bold] ruby #[fg=#9c2822,bg=#CC342D]#[bg=#CC342D,fg=#ffffff,bold] %s #[fg=#CC342D,bg=%s]' "$ver" "$ISLAND"
    exit 0
  fi
fi

# No lang -- just the island opening arrow
printf '#[bg=default,fg=%s]' "$ISLAND"
