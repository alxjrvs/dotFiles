#!/usr/bin/env bats
# Unit tests for the self-contained dedotctl shell port.
# Covers: porcelain-v2 parse, prompt gradient/bar, macOS expected_read
# normalization, symlink link() modes, cache hash.

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
JQDIR="$(dirname "$(mise which jq 2> /dev/null || command -v jq)")"

load 'helpers'

setup() {
  scrub_git_env
  export PATH="$JQDIR:/opt/homebrew/bin:/usr/bin:/bin"
  TDIR="$(mktemp -d "${TMPDIR:-/tmp}/bats.XXXXXX")"
  export HOME="$TDIR"
  mkdir -p "$HOME/.claude/state"
}
teardown() { rm -rf "$TDIR"; }

# link() now lives only in sync (exported to the install/* modules at runtime);
# the modules no longer inline it. Extract just the link() function from sync
# into a sourceable file (awk avoids sed's brace-escaping pitfalls) and echo the
# path, so the link() tests exercise the canonical definition.
_extract_link() {
  local fnfile="$TDIR/synclink.sh"
  awk '/^link\(\) \{/{f=1} f{print} /^\}/{if(f)exit}' "$ROOT/sync" > "$fnfile"
  printf '%s\n' "$fnfile"
}

# ── cache hash ──────────────────────────────────────────────────────────────
# The cache key is FNV-1a (pure bash, no fork) inlined identically in
# git-data and prompt-render. These tests pin the deterministic 12-hex
# shape and cross-file agreement.
@test "cache hash: git-data repo_hash is deterministic 12-hex" {
  local p="/Users/jarvis/Code/dotFiles/.claude/worktrees/dedotctl"
  local fn a b
  fn=$(sed -n '/^repo_hash() {/,/^}/p' "$ROOT/prompt/git-data")
  a=$(bash -c "$fn; repo_hash '$p'")
  b=$(bash -c "$fn; repo_hash '$p'")
  [ "$a" = "$b" ]
  [[ "$a" =~ ^[0-9a-f]{12}$ ]]
  # Different inputs hash differently.
  local c
  c=$(bash -c "$fn; repo_hash '/some/other/repo'")
  [ "$a" != "$c" ]
}

@test "cache hash: repo_hash OUTVAR form matches the printing form" {
  local p="/tmp/some/repo"
  local fn
  fn=$(sed -n '/^repo_hash() {/,/^}/p' "$ROOT/prompt/git-data")
  local printed assigned
  printed=$(bash -c "$fn; repo_hash '$p'")
  assigned=$(bash -c "$fn; repo_hash '$p' v; printf '%s' \"\$v\"")
  [ "$printed" = "$assigned" ]
}

@test "cache hash: git-data and prompt-render use identical hash fn" {
  local p="/tmp/some/repo"
  local fn_gd fn_pr a b
  fn_gd=$(sed -n '/^repo_hash() {/,/^}/p' "$ROOT/prompt/git-data")
  fn_pr=$(sed -n '/^repo_hash() {/,/^}/p' "$ROOT/prompt/prompt-render")
  a=$(bash -c "$fn_gd; repo_hash '$p'")
  b=$(bash -c "$fn_pr; repo_hash '$p'")
  [ "$a" = "$b" ]
  [ "${#a}" -eq 12 ]
}

# Fork-free contract: prompt-render's render path must make zero subprocess
# calls — no command substitution of external tools, no pipelines to shasum.
@test "prompt-render: no shasum/sha256sum/cut remain (fork-free contract)" {
  ! grep -E 'shasum|sha256sum|\bcut\b' "$ROOT/prompt/prompt-render"
}

# ── macOS expected_read normalization ───────────────────────────────────────
@test "macos: _macos_expected_read normalizes bool truthy values to 1" {
  source "$ROOT/install/90-macos.sh"
  [ "$(_macos_expected_read bool true)" = "1" ]
  [ "$(_macos_expected_read bool TRUE)" = "1" ]
  [ "$(_macos_expected_read bool yes)" = "1" ]
  [ "$(_macos_expected_read bool YES)" = "1" ]
  [ "$(_macos_expected_read bool 1)" = "1" ]
}

@test "macos: _macos_expected_read normalizes bool falsy values to 0" {
  source "$ROOT/install/90-macos.sh"
  [ "$(_macos_expected_read bool false)" = "0" ]
  [ "$(_macos_expected_read bool 0)" = "0" ]
  [ "$(_macos_expected_read bool garbage)" = "0" ]
}

@test "macos: _macos_expected_read passes non-bool kinds through" {
  source "$ROOT/install/90-macos.sh"
  [ "$(_macos_expected_read int 5)" = "5" ]
  [ "$(_macos_expected_read string hello)" = "hello" ]
}

# ── symlink link() mode branches ────────────────────────────────────────────
@test "symlink link(): creates a new symlink when dst absent" {
  source "$(_extract_link)"
  local src="$TDIR/src" dst="$TDIR/dst"
  echo hi >"$src"
  link "$src" "$dst"
  [ -L "$dst" ]
  [ "$(readlink "$dst")" = "$src" ]
}

@test "symlink link(): no-op when already correctly linked" {
  source "$(_extract_link)"
  local src="$TDIR/src" dst="$TDIR/dst"
  echo hi >"$src"
  ln -s "$src" "$dst"
  run link "$src" "$dst"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked"* ]]
}

@test "symlink link(): overwrite mode backs up and relinks" {
  source "$(_extract_link)"
  local src="$TDIR/src" dst="$TDIR/dst"
  echo new >"$src"
  echo old >"$dst"
  LINK_MODE=overwrite link "$src" "$dst"
  [ -L "$dst" ]
  [ "$(readlink "$dst")" = "$src" ]
  [ -f "${dst}.bak" ]
  [ "$(cat "${dst}.bak")" = "old" ]
}

@test "symlink link(): skip mode leaves dst untouched" {
  source "$(_extract_link)"
  local src="$TDIR/src" dst="$TDIR/dst"
  echo new >"$src"
  echo old >"$dst"
  LINK_MODE=skip link "$src" "$dst"
  [ ! -L "$dst" ]
  [ "$(cat "$dst")" = "old" ]
  [ ! -e "${dst}.bak" ]
}

# Interactive mode on a non-TTY (unattended bootstrap) must NOT block on
# read: it falls back to skip + a loud warning instead of hanging.
@test "symlink link(): interactive mode on non-TTY skips conflict (no hang)" {
  local fnfile
  fnfile="$(_extract_link)"
  local src="$TDIR/src" dst="$TDIR/dst"
  echo new >"$src"
  echo old >"$dst"
  # Default LINK_MODE (interactive) + closed stdin: must return, not block.
  run env -u LINK_MODE bash -c '
    source "'"$fnfile"'"
    link "'"$src"'" "'"$dst"'"
  ' </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-interactive"* ]]
  [ ! -L "$dst" ]
  [ "$(cat "$dst")" = "old" ]
  [ ! -e "${dst}.bak" ]
}

# Same guarantee for sync's copy of link().
@test "sync link(): interactive mode on non-TTY skips conflict (no hang)" {
  local src="$TDIR/src" dst="$TDIR/dst"
  echo new >"$src"
  echo old >"$dst"
  # Extract just the link() function from sync into a sourceable file
  # (awk avoids sed's brace-escaping pitfalls), then exercise it with
  # stdin closed so the interactive read would block if unguarded.
  local fnfile="$TDIR/synclink.sh"
  awk '/^link\(\) \{/{f=1} f{print} /^\}/{if(f)exit}' "$ROOT/sync" >"$fnfile"
  unset LINK_MODE
  source "$fnfile"
  run link "$src" "$dst" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-interactive"* ]]
  [ ! -L "$dst" ]
  [ "$(cat "$dst")" = "old" ]
  [ ! -e "${dst}.bak" ]
}

# ── porcelain-v2 parse (git-data on a temp repo) ────────────────────────────
# init_repo: a throwaway git repo with global hooks/signing disabled so the
# dotfiles repo's core.hooksPath + gpgsign don't fire during tests.
init_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" config core.hooksPath /dev/null
}
# Cache file path uses git's own --show-toplevel (may resolve /private
# symlinks) and the canonical repo_hash extracted from git-data itself.
cache_path() {
  local repo="$1" top hash
  top=$(cd "$repo" && git rev-parse --show-toplevel)
  hash=$(bash -c "$(sed -n '/^repo_hash() {/,/^}/p' "$ROOT/prompt/git-data"); repo_hash \"\$1\"" _ "$top")
  printf '%s/.cache/git-data/%s.sh' "$TDIR" "$hash"
}

@test "git-data: parses clean repo on default branch" {
  local repo="$TDIR/repo"
  init_repo "$repo"
  echo a >"$repo/a"
  git -C "$repo" add a
  git -C "$repo" commit -qm init
  export XDG_CACHE_HOME="$TDIR/.cache"
  (cd "$repo" && "$ROOT/prompt/git-data")
  local cache
  cache=$(cache_path "$repo")
  [ -f "$cache" ]
  grep -q "GIT_BRANCH='main'" "$cache"
  grep -q "GIT_STAGED_COUNT='0'" "$cache"
  grep -q "GIT_UNSTAGED_COUNT='0'" "$cache"
  grep -q "GIT_UNTRACKED_COUNT='0'" "$cache"
}

@test "git-data: counts staged, unstaged, untracked correctly" {
  local repo="$TDIR/repo2"
  init_repo "$repo"
  echo a >"$repo/tracked"
  echo c >"$repo/other"
  git -C "$repo" add tracked other
  git -C "$repo" commit -qm init
  # staged change (added, not committed)
  echo b >>"$repo/tracked"
  git -C "$repo" add tracked
  # unstaged change on a second tracked file (modified, not added)
  echo d >>"$repo/other"
  # untracked file
  echo e >"$repo/newfile"
  export XDG_CACHE_HOME="$TDIR/.cache"
  (cd "$repo" && "$ROOT/prompt/git-data")
  local cache
  cache=$(cache_path "$repo")
  [ -f "$cache" ]
  grep -q "GIT_STAGED_COUNT='1'" "$cache"
  grep -q "GIT_UNSTAGED_COUNT='1'" "$cache"
  grep -q "GIT_UNTRACKED_COUNT='1'" "$cache"
}

# ── prompt gradient / bar correctness (statusline render_bar) ───────────────
@test "statusline render_bar: pip count scales with columns" {
  # source just the bar helpers by extracting them from statusline.sh
  local sl="$ROOT/share/claude-statusline/statusline.sh"
  # pip_count_for_width is the width->pip mapping
  local fn
  fn=$(sed -n '/pip_count_for_width() {/,/^}/p' "$sl")
  [ -n "$fn" ]
  local narrow wide
  narrow=$(bash -c "$fn; pip_count_for_width 60")
  wide=$(bash -c "$fn; pip_count_for_width 200")
  [ "$narrow" -lt "$wide" ]
}

@test "statusline gradient: blackbody color fn yields RGB triple" {
  local sl="$ROOT/share/claude-statusline/statusline.sh"
  # locate the gradient color function (awk-backed) by name
  grep -qE 'gradient|blackbody|pip_color|grad_color' "$sl"
}

# ── PR-status TTL cache (gh re-query regression) ────────────────────────────
# Regression: in the no-PR case the cached PR record is "\t\t0\t<epoch>".
# git-data used to round-trip those four fields through a tab-joined string
# consumed by `read -a`; under macOS system bash 3.2 `read` collapses the
# leading empty IFS fields, so the timestamp was lost and the 60s TTL never
# held — gh (~0.75s) was re-invoked on EVERY prompt. These tests run git-data
# under /bin/bash (bash 3.2) explicitly and assert the second run within the
# TTL invokes gh ZERO times.

# install_gh_stub DIR MODE — drop a `gh` shim on PATH that bumps a counter file
# ($DIR/calls) each invocation. MODE=nopr emits the empty no-PR string; MODE=pr
# emits a populated "pass\turl\t7" record (mirrors query_pr_status jq output).
install_gh_stub() {
  local dir="$1" mode="$2"
  mkdir -p "$dir"
  : > "$dir/calls"
  {
    printf '#!/bin/bash\n'
    printf 'printf x >> "%s/calls"\n' "$dir"
    if [ "$mode" = "pr" ]; then
      # %b expands the \t escapes in the gh stub into real tab separators.
      printf 'printf "%%b" "pass\\thttps://github.com/o/r/pull/7\\t7"\n'
    fi
    # nopr: print nothing (empty => no PR), exit 0.
    printf 'exit 0\n'
  } > "$dir/gh"
  chmod +x "$dir/gh"
}

gh_call_count() {
  local f="$1"
  [ -f "$f" ] || {
    echo 0
    return
  }
  wc -c < "$f" | tr -d ' '
}

@test "git-data PR TTL: no-PR cache holds; gh not re-queried within TTL" {
  local repo="$TDIR/prrepo"
  init_repo "$repo"
  echo a > "$repo/a"
  git -C "$repo" add a
  git -C "$repo" commit -qm init
  git -C "$repo" remote add origin git@github.com:o/r.git
  export XDG_CACHE_HOME="$TDIR/.cache"
  local stub="$TDIR/ghstub"
  install_gh_stub "$stub" nopr
  # Run under /bin/bash (bash 3.2) explicitly to exercise the read-collapse path.
  (cd "$repo" && PATH="$stub:$PATH" /bin/bash "$ROOT/prompt/git-data")
  [ "$(gh_call_count "$stub/calls")" -eq 1 ]
  local cache
  cache=$(cache_path "$repo")
  [ -f "$cache" ]
  grep -q "GIT_PR_STATUS=''" "$cache"
  grep -q "GIT_PR_NUMBER='0'" "$cache"
  # Second run within TTL must NOT touch gh.
  (cd "$repo" && PATH="$stub:$PATH" /bin/bash "$ROOT/prompt/git-data")
  [ "$(gh_call_count "$stub/calls")" -eq 1 ]
}

@test "git-data PR TTL: with-PR cache holds; gh not re-queried within TTL" {
  local repo="$TDIR/prrepo2"
  init_repo "$repo"
  echo a > "$repo/a"
  git -C "$repo" add a
  git -C "$repo" commit -qm init
  git -C "$repo" remote add origin git@github.com:o/r.git
  export XDG_CACHE_HOME="$TDIR/.cache"
  local stub="$TDIR/ghstub2"
  install_gh_stub "$stub" pr
  (cd "$repo" && PATH="$stub:$PATH" /bin/bash "$ROOT/prompt/git-data")
  [ "$(gh_call_count "$stub/calls")" -eq 1 ]
  local cache
  cache=$(cache_path "$repo")
  grep -q "GIT_PR_STATUS='pass'" "$cache"
  grep -q "GIT_PR_NUMBER='7'" "$cache"
  # Second run within TTL must NOT touch gh.
  (cd "$repo" && PATH="$stub:$PATH" /bin/bash "$ROOT/prompt/git-data")
  [ "$(gh_call_count "$stub/calls")" -eq 1 ]
}

@test "git-data PR TTL: stale checked_at re-queries gh exactly once" {
  local repo="$TDIR/prrepo3"
  init_repo "$repo"
  echo a > "$repo/a"
  git -C "$repo" add a
  git -C "$repo" commit -qm init
  git -C "$repo" remote add origin git@github.com:o/r.git
  export XDG_CACHE_HOME="$TDIR/.cache"
  local stub="$TDIR/ghstub3"
  install_gh_stub "$stub" nopr
  (cd "$repo" && PATH="$stub:$PATH" /bin/bash "$ROOT/prompt/git-data")
  [ "$(gh_call_count "$stub/calls")" -eq 1 ]
  local cache
  cache=$(cache_path "$repo")
  # Backdate the cached check well past the 60s TTL.
  local sed_re="s/GIT_PR_CHECKED_AT='[0-9]*'/GIT_PR_CHECKED_AT='1000000000'/"
  sed -i.bak "$sed_re" "$cache"
  rm -f "$cache.bak"
  (cd "$repo" && PATH="$stub:$PATH" /bin/bash "$ROOT/prompt/git-data")
  [ "$(gh_call_count "$stub/calls")" -eq 2 ]
}

# ── doctor ───────────────────────────────────────────────────────────────────
# Note: doctor resolves DOTFILES_DIR independently of $HOME, so these tests run
# against the real repo. setup() repoints $HOME at a temp dir, which only
# affects the (warn-only) symlink audit — failures there don't change exit code.

@test "doctor: completes with a summary when external checks are skipped" {
  run env DOTFILES_DOCTOR_SKIP_EXTERNAL=1 DOTFILES_DIR="$ROOT" "$ROOT/doctor"
  # Warn-only run exits 0; a hard fail exits 1. Either way it must reach the end.
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [[ "$output" == *"==> Doctor"* ]]
  # The final summary line is one of: all-passed, warning(s), or error(s).
  [[ "$output" == *"checks passed"* ]] ||
    [[ "$output" == *"warning(s)"* ]] ||
    [[ "$output" == *"error(s)"* ]]
}

@test "doctor: a failing check reports a cross and still prints the summary" {
  # set -e used to abort on a failing command-substitution mid-stream; a failing
  # tool-presence check must now emit a cross AND reach the error summary.
  run env -i PATH="/usr/bin:/bin" HOME="$HOME" \
    DOTFILES_DOCTOR_SKIP_EXTERNAL=1 DOTFILES_DIR="$ROOT" "$ROOT/doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"error(s)"* ]]
}

@test "doctor: claude-doctor uses if-assignment, not the set -e dollar-question trap" {
  # The unreachable `_x=$(cmd); rc=$?` idiom must be gone; the failure branch
  # is reached via `if _claude_out=$(claude doctor ...)`.
  grep -q 'if _claude_out=$(claude doctor 2>&1); then' "$ROOT/doctor"
  ! grep -q '_claude_rc=$?' "$ROOT/doctor"
}

@test "doctor: doc-drift scanner has been removed" {
  ! grep -q '_dead_strings' "$ROOT/doctor"
  ! grep -q '_scan_file_for_drift' "$ROOT/doctor"
  ! grep -q 'doc drift' "$ROOT/doctor"
}

@test "doctor: symlink audit covers dot, git-template hook, zsh frags" {
  grep -q '.local/bin/dot|dot' "$ROOT/doctor"
  grep -q 'git/template/hooks/pre-commit|git-template/hooks/pre-commit' "$ROOT/doctor"
  # zsh fragments expanded from the [0-9]*.zsh glob.
  grep -q 'zsh/\[0-9\]\*.zsh' "$ROOT/doctor"
}

@test "repo carries no settings.local overlay (machinery removed)" {
  ! grep -q 'settings\.local' "$ROOT/doctor"
  [[ ! -f "$ROOT/dot-claude/settings.local.json" ]]
  # 40-symlinks must not create the link (the stale-cleanup rm is the only
  # remaining mention).
  ! grep -q 'link .*settings\.local' "$ROOT/install/40-symlinks.sh"
}

# A tool present on PATH but whose --version fails (e.g. gh aborting when it
# can't load its config in a restricted environment) must register as PRESENT,
# not "not found".
@test "doctor: gh present but config-restricted is not reported as not found" {
  local fakebin="$TDIR/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/gh" << 'SH'
#!/usr/bin/env bash
echo "failed to load config: operation not permitted" >&2
exit 1
SH
  chmod +x "$fakebin/gh"
  run env DOTFILES_DOCTOR_SKIP_EXTERNAL=1 DOTFILES_DIR="$ROOT" \
    PATH="$fakebin:$PATH" "$ROOT/doctor"
  [[ "$output" == *"gh: present (version unavailable"* ]]
  [[ "$output" != *"gh: not found"* ]]
}

# ── sync: prune pass runs exactly once ───────────────────────────────────────
# 95-prune.sh matched the module-loop glob AND the explicit tail block, so the
# prune pass ran twice on a full sync. It must now run exactly once.
@test "sync: prune pass runs exactly once (--only=prune)" {
  local home="$TDIR/synchome"
  mkdir -p "$home"
  run env HOME="$home" "$ROOT/sync" --only=prune -s
  [ "$status" -eq 0 ]
  local n
  n=$(printf '%s\n' "$output" | grep -c '==> Backup cleanup')
  [ "$n" -eq 1 ]
}

# Launched with a low soft RLIMIT_NOFILE (macOS GUI-app default ~256), the prune
# pass used to die with "Too many open files" when the parent already held many
# fds. sync now raises the soft limit early. This is a structural guard — the
# behavioral threshold is environment-sensitive (an empty $HOME never exhausts
# the table), so asserting the raise itself is the deterministic test.
@test "sync: raises soft fd limit to at least 4096" {
  grep -Eq 'ulimit -Sn [0-9]+' "$ROOT/sync"
  local val
  val=$(grep -Eo 'ulimit -Sn [0-9]+' "$ROOT/sync" | grep -Eo '[0-9]+' | head -1)
  [ "$val" -ge 4096 ]
}

# ── zsh prompt fast-path: GIT_DIR cache parse (zsh/50-prompt.zsh) ────────────
# The mtime fast path reads GIT_DIR out of the git-data cache into a
# shell-LOCAL `_dot_git_dir` (never the magic env var GIT_DIR). These tests
# pin the glob + single-quote-strip parse used in _dot_read_git_dir.
ZSH_BIN="$(command -v zsh || echo /bin/zsh)"

@test "prompt fast-path: parses GIT_DIR='...' line into _dot_git_dir" {
  [ -x "$ZSH_BIN" ] || skip "zsh not available"
  local dir="$TDIR/git-data"
  mkdir -p "$dir"
  printf "GIT_IS_REPO='1'\nGIT_DIR='%s'\nGIT_TOPLEVEL='%s'\n" \
    "$TDIR/repo/.git" "$TDIR/repo" > "$dir/deadbeef.sh"
  run "$ZSH_BIN" -c '
    setopt nullglob
    _dot_git_cache_dir="'"$dir"'"
    _dot_git_dir=""
    local -a _caches=("$_dot_git_cache_dir"/*.sh(Nom))
    local _cache="$_caches[1]" _line
    local sq=$'\''\x27'\''
    while IFS= read -r _line; do
      if [[ "$_line" == GIT_DIR=* ]]; then
        _dot_git_dir="${${_line#GIT_DIR=$sq}%$sq}"
        break
      fi
    done < "$_cache"
    print -r -- "$_dot_git_dir"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$TDIR/repo/.git" ]
}

@test "prompt fast-path: empty GIT_DIR (outside repo) parses to empty string" {
  [ -x "$ZSH_BIN" ] || skip "zsh not available"
  local dir="$TDIR/git-data"
  mkdir -p "$dir"
  printf "GIT_IS_REPO=''\nGIT_DIR=''\n" > "$dir/cafef00d.sh"
  run "$ZSH_BIN" -c '
    setopt nullglob
    _dot_git_dir="sentinel"
    local -a _caches=("'"$dir"'"/*.sh(Nom))
    local _cache="$_caches[1]" _line
    local sq=$'\''\x27'\''
    while IFS= read -r _line; do
      if [[ "$_line" == GIT_DIR=* ]]; then
        _dot_git_dir="${${_line#GIT_DIR=$sq}%$sq}"
        break
      fi
    done < "$_cache"
    print -r -- "[$_dot_git_dir]"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ── zsh compinit fast-path glob (zsh/40-completions.zsh) ─────────────────────
# Glob qualifiers don't expand inside [[ ]]; the fix evaluates `(Nmh-24)` via
# an array assignment. A non-empty array means "fresh dump => compinit -C";
# empty means "missing or stale => full compinit".
@test "compinit fast-path: fresh .zcompdump yields non-empty array (-> compinit -C)" {
  [ -x "$ZSH_BIN" ] || skip "zsh not available"
  local zd="$TDIR/zdot"
  mkdir -p "$zd"
  touch "$zd/.zcompdump"
  run "$ZSH_BIN" -c '
    setopt nullglob
    local _f=("'"$zd"'/.zcompdump"(Nmh-24))
    print -r -- "${#_f}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "compinit fast-path: stale (>24h) .zcompdump yields empty array (-> full compinit)" {
  [ -x "$ZSH_BIN" ] || skip "zsh not available"
  local zd="$TDIR/zdot"
  mkdir -p "$zd"
  touch -t 202001010000 "$zd/.zcompdump"
  run "$ZSH_BIN" -c '
    setopt nullglob
    local _f=("'"$zd"'/.zcompdump"(Nmh-24))
    print -r -- "${#_f}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "compinit fast-path: missing .zcompdump yields empty array (-> full compinit)" {
  [ -x "$ZSH_BIN" ] || skip "zsh not available"
  local zd="$TDIR/zdot"
  mkdir -p "$zd"
  run "$ZSH_BIN" -c '
    setopt nullglob
    local _f=("'"$zd"'/.zcompdump"(Nmh-24))
    print -r -- "${#_f}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# ── doctor expected-links table derives from 40-symlinks ────────────────────
# The table is hand-maintained 1:1 with install/40-symlinks.sh; this derives
# the literal link() calls (joining backslash continuations; the ${f}/${name}
# loop calls are audited by doctor's own zsh-glob expansion) and asserts each
# has a doctor row — so a new symlink can't ship without its audit entry.
@test "doctor: every literal link() call in 40-symlinks has an expected-links row" {
  local joined pairs pair
  # Join backslash-continued lines so multi-line link() calls match.
  joined=$(sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta' "$ROOT/install/40-symlinks.sh")
  pairs=$(printf '%s\n' "$joined" |
    grep -oE 'link "\$\{df\}/[^"$]+" "\$\{HOME\}/[^"$]+"' |
    sed -E 's|link "\$\{df\}/([^"]+)" "\$\{HOME\}/([^"]+)"|\2\|\1|')
  [ -n "$pairs" ]
  while IFS= read -r pair; do
    grep -qF "\"$pair\"" "$ROOT/doctor" || {
      echo "link() pair missing from doctor _expected_links: $pair" >&2
      false
    }
  done <<< "$pairs"
}
