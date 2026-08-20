#!/bin/sh
# Hermetic regression suite for hooks/claude-launcher.sh.
#
# That script is the `claude` entrypoint on this machine — every session, every
# background job and every hook goes through it — so a mistake in it is not a
# stale TCC prompt, it is a machine with no working `claude`. It gets tested for
# the same reason the three PreToolUse guards do, and the same rule applies:
# ADD A CASE BEFORE CHANGING IT.
#
# Hermetic: a fake XDG_DATA_HOME under $TMPDIR, stub "releases" that are shell
# scripts echoing their argv. No network, nothing touched outside the fixture,
# and the real ~/.local/share/claude is only ever READ (one optional case).
#
# Usage: sh hooks/tests/claude-launcher.sh [path-to-claude-launcher.sh]

set -u

launcher=${1:-"$(dirname "$0")/../claude-launcher.sh"}
[ -f "$launcher" ] || {
  echo "claude-launcher-tests: cannot find $launcher" >&2
  exit 1
}

# macOS only, and honestly so rather than by silently passing. The launcher
# exists to satisfy macOS TCC and uses BSD `stat -f %i`; on Linux both it and
# this suite are meaningless. lint.yml (ubuntu) documents why it skips this.
if [ "$(uname -s)" != "Darwin" ]; then
  echo "claude-launcher-tests: skipped (macOS only)"
  exit 0
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/claude-launcher-tests.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT INT TERM

pass=0
fail=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $1"
    echo "  expected: $2"
    echo "  actual:   $3"
  fi
}

V="$T/claude/versions"
BUNDLE="$T/claude/ClaudeCode.app/Contents"
mkdir -p "$V"

mk() { # mk <version> — a stub release that reports its own version and argv
  printf '#!/bin/sh\necho "%s argv:$*"\n' "$1" > "$V/$1"
  chmod +x "$V/$1"
}
run() { XDG_DATA_HOME="$T" sh "$launcher" "$@"; }
ino() { stat -f %i "$1" 2> /dev/null; }
have() { printf '%s\n' "$V"/* | sed 's|.*/||' | sort -V | tr '\n' ' ' | sed 's/ $//'; }

# --- selection ---------------------------------------------------------------
# Semver-aware, not lexical: 2.1.100 must beat 2.1.9. And the `.tmp.N.N` files
# the updater stages mid-download must never be selected — execing a partial
# download is the worst available failure.
mk 2.1.9
mk 2.1.100
mk 2.1.237
printf 'partial-download' > "$V/2.1.238.tmp.1.2"
check "selects newest semver, ignores staging files" \
  "2.1.237 argv:--version x" "$(run --version x)"

# --- bundle construction -----------------------------------------------------
# The bundle executable must BE the release (same inode). A copy would duplicate
# 317MB per update and is the obvious wrong implementation.
check "bundle exec is a hardlink to the release" \
  "$(ino "$V/2.1.237")" "$(ino "$BUNDLE/MacOS/claude")"
check "Info.plist declares the stable bundle id" \
  "0" "$(grep -c 'com.anthropic.claude-code' "$BUNDLE/Info.plist" > /dev/null && echo 0 || echo 1)"

# --- idempotence -------------------------------------------------------------
# The launcher runs on EVERY claude invocation. Relinking when nothing changed
# would rewrite a 317MB hardlink on every shell command.
before=$(ino "$BUNDLE/MacOS/claude")
run > /dev/null
check "no relink when nothing changed" "$before" "$(ino "$BUNDLE/MacOS/claude")"

# --- the update transition ---------------------------------------------------
mk 2.1.238
run > /dev/null
check "follows an update to the new release" \
  "$(ino "$V/2.1.238")" "$(ino "$BUNDLE/MacOS/claude")"
check "execs the new release after an update" \
  "2.1.238 argv:" "$(run)"

# --- pruning -----------------------------------------------------------------
# A custom launcher disables the installer's own version cleanup, so this
# replaces it. Newest three kept; staging files belong to the updater.
mk 2.1.239
run > /dev/null
check "prune keeps newest three on the update transition" \
  "2.1.237 2.1.238 2.1.238.tmp.1.2 2.1.239" "$(have)"

mk 2.1.20
run > /dev/null
check "no prune on a normal launch" \
  "2.1.20 2.1.237 2.1.238 2.1.238.tmp.1.2 2.1.239" "$(have)"

# --- failure modes -----------------------------------------------------------
# Fail LOUD but never silently: a stale TCC prompt is an annoyance, a `claude`
# that will not start is an outage.
mkdir -p "$T/empty/claude/versions"
out=$(XDG_DATA_HOME="$T/empty" sh "$launcher" 2>&1)
rc=$?
check "no installed version exits 127" "127" "$rc"
check "no installed version explains itself" "0" \
  "$(printf '%s' "$out" | grep -c 'no installed version' > /dev/null && echo 0 || echo 1)"

# --- agreement with Claude Code itself ---------------------------------------
# The plist must match the one Claude Code writes for itself byte for byte, or a
# future version that does refresh the bundle will fight this script. Skipped
# where Claude Code is not installed (CI).
real="$HOME/.local/share/claude/ClaudeCode.app/Contents/Info.plist"
if [ -f "$real" ]; then
  check "Info.plist is byte-identical to Claude Code's own" "same" \
    "$(cmp -s "$BUNDLE/Info.plist" "$real" && echo same || echo differs)"
fi

if [ "$fail" -eq 0 ]; then
  echo "claude-launcher-tests: $pass passed"
else
  echo "claude-launcher-tests: $fail failed, $pass passed"
fi
[ "$fail" -eq 0 ]
