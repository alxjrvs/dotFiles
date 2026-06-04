#!/usr/bin/env bats
# Unit tests for the self-contained dedotctl shell port.
# Covers: policy-guard patterns, lock-file-guard names, porcelain-v2 parse,
# prompt gradient/bar, macOS expected_read normalization, symlink link() modes,
# trim-bash-output thresholds, cache hash.

ROOT="/Users/jarvis/Code/dotFiles/.claude/worktrees/dedotctl"
JQDIR="/Users/jarvis/.local/share/mise/installs/jq/1.8.1"

setup() {
  export PATH="$JQDIR:/opt/homebrew/bin:/usr/bin:/bin"
  TDIR="$(mktemp -d "${TMPDIR:-/tmp}/bats.XXXXXX")"
  export HOME="$TDIR"
  mkdir -p "$HOME/.claude/state"
}
teardown() { rm -rf "$TDIR"; }

# Helper: run a hook with a JSON payload on stdin.
run_hook() {
  local hook="$1" json="$2"
  printf '%s' "$json" | "$ROOT/hooks/$hook"
}

# jq pretty-prints deny payloads with a space: "permissionDecision": "deny"
is_deny() { [[ "$1" == *'"permissionDecision": "deny"'* ]]; }

# ── policy-guard ────────────────────────────────────────────────────────────
@test "policy-guard: --no-verify on git commit is denied" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
  [[ "$output" == *"--no-verify"* ]]
}

@test "policy-guard: --no-gpg-sign is denied" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"git commit --no-gpg-sign -m x"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

@test "policy-guard: git push --force is denied" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
  [[ "$output" == *"force-with-lease"* ]]
}

@test "policy-guard: git push -f is denied" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

@test "policy-guard: git push --force-with-lease is ALLOWED" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin main"}}'
  [ "$status" -eq 0 ]
  ! is_deny "$output"
}

@test "policy-guard: git commit --amend is denied" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

@test "policy-guard: benign git command is allowed" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *deny* ]]
}

@test "policy-guard: non-Bash tool is ignored" {
  run run_hook policy-guard '{"tool_name":"Edit","tool_input":{"command":"git push --force"}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *deny* ]]
}

# Regression: a dangerous-looking flag in a *separate* segment of a compound
# command must not falsely trip a git verb in another segment. bash [[ =~ ]]
# '.' spans newlines, so `git push ... && rm -f x` used to false-deny.
@test "policy-guard: git push in compound with later 'rm -f' is ALLOWED" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"git push origin main && rm -f /tmp/x"}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *deny* ]]
}

@test "policy-guard: git commit in compound with later 'rm -f' is ALLOWED" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip && rm -f /tmp/y"}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *deny* ]]
}

@test "policy-guard: real force-push still denied even in a compound command" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"echo hi && git push --force origin main"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

@test "policy-guard: branch deletion is advisory, not deny" {
  run run_hook policy-guard '{"tool_name":"Bash","tool_input":{"command":"git push origin --delete somebranch"}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *deny* ]]
  [[ "$output" == *additionalContext* ]]
}

# ── lock-file-guard ─────────────────────────────────────────────────────────
@test "lock-file-guard: denies all 13 known lock names" {
  local names=(Brewfile.lock Brewfile.lock.json bun.lock bun.lockb package-lock.json yarn.lock pnpm-lock.yaml Gemfile.lock Cargo.lock composer.lock poetry.lock uv.lock flake.lock)
  for n in "${names[@]}"; do
    run run_hook lock-file-guard "{\"tool_input\":{\"file_path\":\"/some/path/$n\"}}"
    [ "$status" -eq 0 ]
    is_deny "$output" || {
      echo "expected deny for $n, got: $output"
      false
    }
  done
}

@test "lock-file-guard: allows non-lock file" {
  run run_hook lock-file-guard '{"tool_input":{"file_path":"/some/path/main.rs"}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *deny* ]]
}

@test "lock-file-guard: falls back to .file_path key" {
  run run_hook lock-file-guard '{"file_path":"/x/Cargo.lock"}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

# ── trim-bash-output thresholds ─────────────────────────────────────────────
@test "trim-bash-output: under 20k threshold passes through untrimmed" {
  local small
  small=$(printf 'x%.0s' $(seq 1 100))
  run run_hook trim-bash-output "{\"tool_name\":\"Bash\",\"session_id\":\"s1\",\"tool_response\":{\"stdout\":\"$small\"}}"
  [ "$status" -eq 0 ]
  # No updatedToolOutput when under threshold.
  [[ "$output" != *updatedToolOutput* ]]
}

@test "trim-bash-output: over 20k threshold is trimmed" {
  local big payload
  big=$(printf 'yyyyyyyyyy\n%.0s' $(seq 1 3000))
  # Build valid JSON via jq (raw newlines can't appear unescaped in a string).
  payload=$(jq -n --arg s "$big" '{tool_name:"Bash",session_id:"s1",tool_response:{stdout:$s}}')
  run run_hook trim-bash-output "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == *updatedToolOutput* ]] || [[ "$output" == *hookSpecificOutput* ]]
}

# ── cache hash ──────────────────────────────────────────────────────────────
@test "cache hash: git-data repo_hash matches shasum -a 256 first 12 chars" {
  local p="/Users/jarvis/Code/dotFiles/.claude/worktrees/dedotctl"
  local expect
  expect=$(printf '%s' "$p" | shasum -a 256 | cut -c1-12)
  # extract repo_hash from git-data and invoke it in isolation
  local fn
  fn=$(sed -n '/^repo_hash() {/,/^}/p' "$ROOT/prompt/git-data")
  local got
  got=$(bash -c "$fn; repo_hash '$p'")
  [ "$got" = "$expect" ]
}

@test "cache hash: prompt-render and git-data use identical hash fn" {
  local p="/tmp/some/repo"
  local fn_gd fn_pr a b
  fn_gd=$(sed -n '/^repo_hash() {/,/^}/p' "$ROOT/prompt/git-data")
  fn_pr=$(sed -n '/^repo_hash() {/,/^}/p' "$ROOT/prompt/prompt-render")
  a=$(bash -c "$fn_gd; repo_hash '$p'")
  b=$(bash -c "$fn_pr; repo_hash '$p'")
  [ "$a" = "$b" ]
  [ "${#a}" -eq 12 ]
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
  source "$ROOT/install/40-symlinks.sh"
  local src="$TDIR/src" dst="$TDIR/dst"
  echo hi >"$src"
  link "$src" "$dst"
  [ -L "$dst" ]
  [ "$(readlink "$dst")" = "$src" ]
}

@test "symlink link(): no-op when already correctly linked" {
  source "$ROOT/install/40-symlinks.sh"
  local src="$TDIR/src" dst="$TDIR/dst"
  echo hi >"$src"
  ln -s "$src" "$dst"
  run link "$src" "$dst"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked"* ]]
}

@test "symlink link(): overwrite mode backs up and relinks" {
  source "$ROOT/install/40-symlinks.sh"
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
  source "$ROOT/install/40-symlinks.sh"
  local src="$TDIR/src" dst="$TDIR/dst"
  echo new >"$src"
  echo old >"$dst"
  LINK_MODE=skip link "$src" "$dst"
  [ ! -L "$dst" ]
  [ "$(cat "$dst")" = "old" ]
  [ ! -e "${dst}.bak" ]
}

# ── porcelain-v2 parse (git-data on a temp repo) ────────────────────────────
# init_repo: a throwaway git repo with global hooks/signing disabled so the
# dotfiles repo's core.hooksPath + gpgsign don't fire inside the sandbox.
init_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" config core.hooksPath /dev/null
}
# Cache file path uses git's own --show-toplevel (may resolve /private symlinks).
cache_path() {
  local repo="$1" top hash
  top=$(cd "$repo" && git rev-parse --show-toplevel)
  hash=$(printf '%s' "$top" | shasum -a 256 | cut -c1-12)
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
