#!/bin/sh
# tmux-lang-left.sh <pane_current_path>
# Detects dominant language, outputs left-side styled segment.
# Sits between dir (purple bg) and git branch.
# Uses E0B0 (right-pointing) arrows for left-side powerline.

dir="$1"
[ -z "$dir" ] && exit 0
cd "$dir" 2>/dev/null || exit 0

PURPLE="#4a4a4a"

# Detect language from marker files (most specific first)
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

[ -z "$lang" ] && exit 0

case "$lang" in
  node)    COLOR="#4a9070"; LABEL="NODE";  ASDF="nodejs" ;;
  deno)    COLOR="#4a8a8a"; LABEL="DENO";  ASDF="deno" ;;
  python)  COLOR="#5f7faf"; LABEL="PY";    ASDF="python" ;;
  rust)    COLOR="#b06040"; LABEL="RUST";  ASDF="rust" ;;
  go)      COLOR="#5a9aaa"; LABEL="GO";    ASDF="golang" ;;
  ruby)    COLOR="#b05050"; LABEL="RUBY";  ASDF="ruby" ;;
  elixir)  COLOR="#7b60a0"; LABEL="EX";    ASDF="elixir" ;;
  swift)   COLOR="#c06048"; LABEL="SWIFT"; ASDF="" ;;
  java)    COLOR="#a06050"; LABEL="JAVA";  ASDF="java" ;;
  kotlin)  COLOR="#7f52b0"; LABEL="KT";    ASDF="kotlin" ;;
  php)     COLOR="#7070a8"; LABEL="PHP";   ASDF="php" ;;
  zig)     COLOR="#c09040"; LABEL="ZIG";   ASDF="zig" ;;
  *)       exit 0 ;;
esac

# Get version via asdf
ver=""
if [ -n "$ASDF" ]; then
  ver=$(asdf current "$ASDF" 2>/dev/null | awk 'NR>1{print $2}')
fi

# Fallback to runtime commands
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

# Left-side segment: [purple->color]arrow LABEL ver [color->purple]arrow
printf "#[bg=%s,fg=%s]#[bg=%s,fg=#f0f0f0] %s %s #[bg=%s,fg=%s]" \
  "$COLOR" "$PURPLE" "$COLOR" "$LABEL" "$ver" "$PURPLE" "$COLOR"
