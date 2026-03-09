#!/bin/sh
# tmux-git.sh <pane_current_path>
# Outputs optional lang segment + git branch + status
# Handles all transitions from purple dir background

dir="$1"
PURPLE="#9060C8"
DARK="#4a4a4a"

cd "$dir" 2>/dev/null || { printf '#[bg=default,fg=%s]' "$PURPLE"; exit 0; }

# ── Language detection ───────────────────────────────────────────────────
lang=""
[ -f "build.zig" ]        && lang="zig"
[ -z "$lang" ] && [ -f "Cargo.toml" ]       && lang="rust"
[ -z "$lang" ] && [ -f "go.mod" ]           && lang="go"
[ -z "$lang" ] && [ -f "mix.exs" ]          && lang="elixir"
[ -z "$lang" ] && [ -f "build.gradle.kts" ] && lang="kotlin"
[ -z "$lang" ] && [ -f "Package.swift" ]    && lang="swift"
[ -z "$lang" ] && [ -f "composer.json" ]    && lang="php"
[ -z "$lang" ] && { [ -f "Gemfile" ] || [ -f ".ruby-version" ]; } && lang="ruby"
[ -z "$lang" ] && { [ -f "deno.json" ] || [ -f "deno.jsonc" ]; } && lang="deno"
[ -z "$lang" ] && { [ -f "package.json" ] || [ -f ".nvmrc" ] || [ -f ".node-version" ]; } && lang="node"
[ -z "$lang" ] && { [ -f "pom.xml" ] || [ -f "build.gradle" ]; } && lang="java"
[ -z "$lang" ] && { [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ] || [ -f ".python-version" ]; } && lang="python"

# ── Check git early ──────────────────────────────────────────────────────
is_git=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && is_git=1

# ── No lang, no git: just close from purple ──────────────────────────────
if [ -z "$lang" ] && [ "$is_git" = "0" ]; then
  printf '#[bg=default,fg=%s]' "$PURPLE"
  exit 0
fi

# ── Lang segment ─────────────────────────────────────────────────────────
if [ -n "$lang" ]; then
  case "$lang" in
    node)    LCOLOR="#4a9070"; LABEL="NODE";  ASDF="nodejs" ;;
    deno)    LCOLOR="#4a8a8a"; LABEL="DENO";  ASDF="deno" ;;
    python)  LCOLOR="#5f7faf"; LABEL="PY";    ASDF="python" ;;
    rust)    LCOLOR="#b06040"; LABEL="RUST";  ASDF="rust" ;;
    go)      LCOLOR="#5a9aaa"; LABEL="GO";    ASDF="golang" ;;
    ruby)    LCOLOR="#b05050"; LABEL="RUBY";  ASDF="ruby" ;;
    elixir)  LCOLOR="#7b60a0"; LABEL="EX";    ASDF="elixir" ;;
    swift)   LCOLOR="#c06048"; LABEL="SWIFT"; ASDF="" ;;
    java)    LCOLOR="#a06050"; LABEL="JAVA";  ASDF="java" ;;
    kotlin)  LCOLOR="#7f52b0"; LABEL="KT";    ASDF="kotlin" ;;
    php)     LCOLOR="#7070a8"; LABEL="PHP";   ASDF="php" ;;
    zig)     LCOLOR="#c09040"; LABEL="ZIG";   ASDF="zig" ;;
  esac

  ver=""
  if [ -n "$ASDF" ]; then
    ver=$(asdf current "$ASDF" 2>/dev/null | awk 'NR>1{print $2}')
  fi
  if [ -z "$ver" ] || [ "$ver" = "______" ]; then
    case "$lang" in
      node)    ver=$(node --version 2>/dev/null | sed 's/^v//') ;;
      deno)    ver=$(deno --version 2>/dev/null | head -1 | awk '{print $2}') ;;
      python)  ver=$(python3 --version 2>/dev/null | awk '{print $2}') ;;
      rust)    ver=$(rustc --version 2>/dev/null | awk '{print $2}') ;;
      go)      ver=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//') ;;
      ruby)    ver=$(ruby --version 2>/dev/null | awk '{print $2}') ;;
      elixir)  ver=$(elixir --version 2>/dev/null | tail -1 | awk '{print $2}') ;;
      swift)   ver=$(swift --version 2>/dev/null | head -1 | awk '{print $4}') ;;
      java)    ver=$(java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/') ;;
      kotlin)  ver=$(kotlin -version 2>&1 | awk '{print $3}') ;;
      php)     ver=$(php --version 2>/dev/null | head -1 | awk '{print $2}') ;;
      zig)     ver=$(zig version 2>/dev/null) ;;
    esac
  fi
  [ -z "$ver" ] && ver="?"

  # [purple->dark] LABEL [dark->color] version [color->dark]
  printf '#[bg=%s,fg=%s]#[bg=%s,fg=#cccccc,nobold] %s #[bg=%s,fg=%s]#[bg=%s,fg=#f0f0f0] %s #[bg=%s,fg=%s]' \
    "$DARK" "$PURPLE" "$DARK" "$LABEL" "$LCOLOR" "$DARK" "$LCOLOR" "$ver" "$DARK" "$LCOLOR"

  # If no git, close from dark
  if [ "$is_git" = "0" ]; then
    printf '#[bg=default,fg=%s]' "$DARK"
    exit 0
  fi
else
  # No lang, has git: transition purple -> dark
  printf '#[bg=%s,fg=%s]' "$DARK" "$PURPLE"
fi

# ── Git branch + status (on dark bg) ────────────────────────────────────
branch=$(git branch --show-current 2>/dev/null)
[ -z "$branch" ] && branch=$(git rev-parse --short HEAD 2>/dev/null)
[ -z "$branch" ] && { printf '#[bg=default,fg=%s]' "$DARK"; exit 0; }

porcelain=$(git status --porcelain 2>/dev/null)
conflicted=0; staged=0; modified=0; renamed=0; deleted=0; stashed=0; untracked=0
echo "$porcelain" | grep -q '^[UAD][UAD]' 2>/dev/null && conflicted=1
echo "$porcelain" | grep -q '^[^? ]'      2>/dev/null && staged=1
echo "$porcelain" | grep -q '^.[M]'        2>/dev/null && modified=1
echo "$porcelain" | grep -q '^R'           2>/dev/null && renamed=1
echo "$porcelain" | grep -q '^.[D]'        2>/dev/null && deleted=1
git stash list 2>/dev/null | grep -q .                 && stashed=1
echo "$porcelain" | grep -q '^??'          2>/dev/null && untracked=1

all_status=""
[ "$conflicted" = "1" ] && all_status="${all_status}="
[ "$staged"     = "1" ] && all_status="${all_status}+"
[ "$modified"   = "1" ] && all_status="${all_status}!"
[ "$renamed"    = "1" ] && all_status="${all_status}»"
[ "$deleted"    = "1" ] && all_status="${all_status}✘"
[ "$stashed"    = "1" ] && all_status="${all_status}$$"
[ "$untracked"  = "1" ] && all_status="${all_status}?"

ahead_behind=""
if git rev-parse --verify "@{u}" >/dev/null 2>&1; then
  ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
  behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
  if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    ahead_behind="⇕"
  elif [ "$ahead" -gt 0 ]; then
    ahead_behind="⇡${ahead}"
  elif [ "$behind" -gt 0 ]; then
    ahead_behind="⇣${behind}"
  fi
fi

printf '#[bg=%s,fg=#f0f0f0,nobold]  %s ' "$DARK" "$branch"

combined="${all_status}${ahead_behind}"
if [ -n "$combined" ]; then
  printf '#[bg=#8a6f2a,fg=%s]#[bg=#8a6f2a,fg=#f0f0f0,bold] %s #[bg=default,fg=#8a6f2a]' "$DARK" "$combined"
elif git rev-parse --verify "@{u}" >/dev/null 2>&1; then
  printf '#[bg=#2e8b57,fg=%s]#[bg=#2e8b57,fg=#f0f0f0,bold]  ✓ #[bg=default,fg=#2e8b57]' "$DARK"
else
  printf '#[bg=default,fg=%s]' "$DARK"
fi
